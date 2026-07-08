import AppKit
import ApplicationServices
import CoreGraphics

/// Real `AXBackend` over `AXUIElement` (U2).
///
/// Requires the process to be Accessibility-trusted; calls throw
/// `AXWindowError.notPermitted` otherwise. Because of that, automated tests
/// never exercise this type — they drive `AXWindowController` through a fake
/// backend. Live behavior is covered by the manual checklist below.
///
/// ## Manual integration checklist (requires a trusted runner)
///
/// Run from an Accessibility-trusted build (the assembled Quintile.app, or a
/// terminal with Accessibility granted):
///
/// 1. Open TextEdit with one document window; verify `windows()` includes it
///    and `focusedWindow()` returns it while TextEdit is frontmost.
/// 2. `setFrame` the TextEdit window to a known rect (e.g. 100,100,800,600);
///    verify `frame(of:)` reads back the same rect within 1.5 pt.
/// 3. Move the window to a secondary display (if present) and repeat step 2 —
///    read-back must match in global Quartz coordinates (origin relative to
///    the primary display's top-left; negative/large offsets are expected).
/// 4. Minimize the window; verify it disappears from `windows()`.
/// 5. Click the desktop (Finder, no windows); verify `focusedWindow()` is nil.
/// 6. Try `setFrame` on an Electron app (e.g. VS Code) sized below its minimum
///    size; verify `.writeRejected` is thrown by `AXWindowController.setFrame`
///    rather than a silent no-op.
/// 7. `kill -STOP` a GUI app, then enumerate: `windows()` must return within
///    ~0.3 s per hung app (messaging timeout), not stall for ~6 s.
public final class LiveAXBackend: AXBackend {

    /// Messaging timeout (seconds) applied to every element we talk to, so a
    /// single hung app degrades to a fast `.cannotComplete` instead of a ~6 s
    /// stall per keystroke.
    private static let messagingTimeout: Float = 0.3

    /// Seam over `AXIsProcessTrusted` so the permission gate stays honest.
    private let isProcessTrusted: () -> Bool

    public init(isProcessTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isProcessTrusted = isProcessTrusted
    }

    // MARK: - AXBackend

    public func focusedWindow() throws -> AXWindowHandle? {
        try ensurePermitted()
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)

        guard let appElement = try copyElement(systemWide, attribute: kAXFocusedApplicationAttribute) else {
            return nil // no frontmost app with AX focus
        }
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)

        guard let windowElement = try copyElement(appElement, attribute: kAXFocusedWindowAttribute) else {
            return nil // frontmost app has no focused window (e.g. Finder desktop)
        }
        return LiveAXWindowHandle(element: windowElement)
    }

    public func windows() throws -> [AXWindowHandle] {
        try ensurePermitted()
        var result: [AXWindowHandle] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)

            var windowsRef: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
            // One hung/AX-less app must not fail enumeration for every other
            // app — skip it. This is a deliberate exception to "never swallow":
            // the timeout above already bounded the cost, and per-window
            // operations still surface typed errors.
            guard error == .success, let items = windowsRef as? [AnyObject] else { continue }

            for item in items {
                guard CFGetTypeID(item) == AXUIElementGetTypeID() else { continue }
                let element = item as! AXUIElement
                if isStandardNonMinimizedWindow(element) {
                    result.append(LiveAXWindowHandle(element: element))
                }
            }
        }
        return result
    }

    public func frame(of window: AXWindowHandle) throws -> CGRect {
        let element = try element(of: window)
        // AX positions are already Quartz top-left-origin global coordinates —
        // no flip here (see the coordinate rule on `AXBackend`).
        var origin = CGPoint.zero
        try readAXValue(element, attribute: kAXPositionAttribute, type: .cgPoint, into: &origin)
        var size = CGSize.zero
        try readAXValue(element, attribute: kAXSizeAttribute, type: .cgSize, into: &size)
        return CGRect(origin: origin, size: size)
    }

    public func setFrame(_ frame: CGRect, of window: AXWindowHandle) throws {
        let element = try element(of: window)
        // The classic AX dance — size, position, size — so a window shrinking
        // or growing while crossing displays lands exactly: position writes are
        // clamped against the *current* size, and size writes against the
        // *current* position, so a single pass can end up off by the delta.
        var size = frame.size
        var origin = frame.origin
        try writeAXValue(element, attribute: kAXSizeAttribute, type: .cgSize, rawValue: &size)
        try writeAXValue(element, attribute: kAXPositionAttribute, type: .cgPoint, rawValue: &origin)
        try writeAXValue(element, attribute: kAXSizeAttribute, type: .cgSize, rawValue: &size)
        // Read-back verification (→ `.writeRejected`) happens in
        // `AXWindowController.setFrame`, uniformly for live and fake backends.
    }

    public func displays() -> [DisplayDescriptor] {
        let screens = NSScreen.screens
        // The primary screen (menu bar, Cocoa origin 0,0) anchors the flip:
        // in Cocoa its frame spans y ∈ [0, primaryHeight] bottom-up; in Quartz
        // the same display spans y ∈ [0, primaryHeight] top-down.
        guard let primaryHeight = screens.first?.frame.maxY else { return [] }

        return screens.compactMap { screen in
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)

            // Every NSScreen-derived rect entering the core is flipped
            // against the PRIMARY display's height via the shared helper
            // (see `QuartzCocoa`).
            let usable = QuartzCocoa.quartzRect(fromCocoa: screen.visibleFrame,
                                                primaryHeight: primaryHeight)

            let info = DisplayInfo(
                vendorNumber: CGDisplayVendorNumber(displayID),
                modelNumber: CGDisplayModelNumber(displayID),
                serialNumber: CGDisplaySerialNumber(displayID),
                localizedName: screen.localizedName,
                pixelSize: CGSize(width: CGDisplayPixelsWide(displayID),
                                  height: CGDisplayPixelsHigh(displayID))
            )
            return DisplayDescriptor(id: displayID,
                                     quartzBounds: CGDisplayBounds(displayID), // already Quartz — no flip
                                     usableBounds: usable,
                                     info: info)
        }
    }

    // MARK: - Window filtering

    private func isStandardNonMinimizedWindow(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)

        // Filter on subrole only where readable: some apps don't expose it,
        // and excluding their windows outright would be worse than including.
        var subroleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef) == .success,
           let subrole = subroleRef as? String,
           subrole != kAXStandardWindowSubrole as String {
            return false
        }

        var minimizedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
           let minimized = minimizedRef as? Bool,
           minimized {
            return false
        }
        return true
    }

    // MARK: - AX plumbing

    private func ensurePermitted() throws {
        guard isProcessTrusted() else { throw AXWindowError.notPermitted }
    }

    private func element(of window: AXWindowHandle) throws -> AXUIElement {
        guard let live = window as? LiveAXWindowHandle else {
            // A foreign handle type can only mean a wiring bug (fake handle
            // passed to the live backend); treat as an invalid window.
            throw AXWindowError.invalidWindow
        }
        return live.element
    }

    /// Copies an element-valued attribute; nil on `.noValue` (a legitimate
    /// "nothing focused" answer), throws on real errors.
    private func copyElement(_ element: AXUIElement, attribute: String) throws -> AXUIElement? {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        if error == .noValue { return nil }
        if let mapped = Self.mapAXError(error) { throw mapped }
        guard let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func readAXValue(_ element: AXUIElement, attribute: String,
                             type: AXValueType, into out: UnsafeMutableRawPointer) throws {
        var ref: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        if let mapped = Self.mapAXError(error) { throw mapped }
        guard let value = ref, CFGetTypeID(value) == AXValueGetTypeID(),
              AXValueGetType(value as! AXValue) == type,
              AXValueGetValue(value as! AXValue, type, out) else {
            throw AXWindowError.attributeUnsupported
        }
    }

    private func writeAXValue(_ element: AXUIElement, attribute: String,
                              type: AXValueType, rawValue: UnsafeRawPointer) throws {
        guard let axValue = AXValueCreate(type, rawValue) else {
            throw AXWindowError.attributeUnsupported
        }
        let error = AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
        if let mapped = Self.mapAXError(error) { throw mapped }
    }

    /// Maps a raw `AXError` to the typed error surface; nil for `.success`.
    static func mapAXError(_ error: AXError) -> AXWindowError? {
        switch error {
        case .success:
            return nil
        case .cannotComplete:
            return .cannotComplete
        case .apiDisabled:
            // kAXErrorAPIDisabled; an untrusted process is caught earlier by
            // `ensurePermitted()`.
            return .notPermitted
        case .invalidUIElement:
            return .invalidWindow
        case .attributeUnsupported, .parameterizedAttributeUnsupported,
             .actionUnsupported, .notificationUnsupported, .notImplemented:
            return .attributeUnsupported
        default:
            return .unexpected(code: error.rawValue)
        }
    }
}

/// Live window handle: an `AXUIElement` with the messaging timeout applied.
public final class LiveAXWindowHandle: AXWindowHandle {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
        AXUIElementSetMessagingTimeout(element, 0.3)
    }

    /// Underlying-element identity: the backend creates a fresh wrapper per
    /// enumeration (`focusedWindow()` vs `windows()`), so two distinct
    /// `LiveAXWindowHandle`s can refer to the same window. `CFEqual` on
    /// `AXUIElement` compares the referenced accessibility object.
    public func isSame(as other: AXWindowHandle) -> Bool {
        guard let live = other as? LiveAXWindowHandle else { return false }
        return CFEqual(element, live.element)
    }
}
