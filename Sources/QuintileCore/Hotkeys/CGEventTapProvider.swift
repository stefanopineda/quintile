import CoreGraphics
import Foundation

/// Real `EventTapProviding` backed by a `CGEventTap` (U5).
///
/// Placement: `.cgSessionEventTap` + `.headInsertEventTap`, so Quintile's
/// callback runs before other session taps — the earliest interception point
/// available to a non-privileged, SIP-respecting process (see
/// `SystemShortcutBridge` for what that does and does not buy us against
/// WindowServer's built-in Fn+Ctrl+Arrow handler).
///
/// Requires Accessibility trust: `CGEvent.tapCreate` returns NULL for an
/// untrusted process, surfaced here as `EventTapError.creationFailed`.
/// `HotkeyManager.activate()` therefore only calls this after
/// `AccessibilityPermissionManager` reports the granted transition.
///
/// ## fn-flag disambiguation
/// Arrow keys (and other "secondary function" keys) carry
/// `.maskSecondaryFn` in their event flags *even when the physical fn key is
/// up* — so the raw flag cannot distinguish Ctrl+→ from Fn+Ctrl+→. This
/// provider tracks the physical fn key via `flagsChanged` events for
/// `kVK_Function` (key code 63) and, for arrow key codes, reports `.fn` from
/// that tracked state instead of the raw mask. Non-arrow keys use the raw
/// mask (where it is only set by a real fn press).
public final class CGEventTapProvider: EventTapProviding {

    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ((KeyEvent) -> EventDisposition)?
    /// Physical fn key state, tracked from flagsChanged (see type doc).
    private var physicalFnIsDown = false

    public init() {}

    deinit {
        disable()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    public var isActive: Bool {
        guard let machPort else { return false }
        return CGEvent.tapIsEnabled(tap: machPort)
    }

    public func createTap(handler: @escaping (KeyEvent) -> EventDisposition) throws {
        guard machPort == nil else {
            self.handler = handler // replace handler; keep the existing tap
            return
        }
        self.handler = handler

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let provider = Unmanaged<CGEventTapProvider>.fromOpaque(refcon).takeUnretainedValue()
            return provider.process(type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // NULL ⇒ the process is not Accessibility-trusted (or taps are
            // otherwise forbidden). Typed error so HotkeyManager's caller can
            // retry on the next granted transition.
            self.handler = nil
            throw EventTapError.creationFailed
        }

        machPort = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        // Created disabled per the EventTapProviding contract; enable() turns
        // delivery on.
        CGEvent.tapEnable(tap: port, enable: false)
    }

    public func enable() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: true)
    }

    public func disable() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: false)
    }

    // MARK: Event conversion

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The OS disables taps whose callbacks run slowly (or on certain
            // secure-input transitions). Re-enable immediately — hotkeys
            // silently dying is the worst failure mode for a tiling app.
            enable()
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == KeyCode.function {
                physicalFnIsDown = event.flags.contains(.maskSecondaryFn)
            }
            return Unmanaged.passUnretained(event)

        case .keyDown, .keyUp:
            guard let handler else { return Unmanaged.passUnretained(event) }
            let keyEvent = makeKeyEvent(from: event, isKeyDown: type == .keyDown)
            switch handler(keyEvent) {
            case .consume: return nil
            case .passThrough: return Unmanaged.passUnretained(event)
            }

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func makeKeyEvent(from event: CGEvent, isKeyDown: Bool) -> KeyEvent {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        var modifiers: KeyModifiers = []
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }

        let isArrow = (KeyCode.leftArrow...KeyCode.upArrow).contains(keyCode)
        let fnPressed = isArrow ? physicalFnIsDown : flags.contains(.maskSecondaryFn)
        if fnPressed { modifiers.insert(.fn) }

        return KeyEvent(keyCode: keyCode, modifiers: modifiers, isKeyDown: isKeyDown)
    }
}
