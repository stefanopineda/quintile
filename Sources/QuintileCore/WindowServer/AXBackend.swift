import CoreGraphics
import Foundation

/// Opaque identity for a window managed through the AX backend (U2).
///
/// Class-constrained so identity is reference identity: two handles refer to
/// the same window iff they are the same object (`ObjectIdentifier`). The live
/// implementation wraps an `AXUIElement`; tests use plain fake objects.
public protocol AXWindowHandle: AnyObject {}

public extension AXWindowHandle {
    /// Hashable-friendly identity for use in dictionaries/sets of windows.
    var id: ObjectIdentifier { ObjectIdentifier(self) }

    /// Reference-identity comparison between two opaque handles.
    func isSame(as other: AXWindowHandle) -> Bool { self === other }
}

/// Typed AX failure surface (U2). AX errors are never silently swallowed —
/// every failing backend call throws one of these so callers can distinguish
/// "app is hung" from "window rejected the write" from "permission missing".
public enum AXWindowError: Error, Equatable, CustomStringConvertible {
    /// The AX messaging round-trip failed (`kAXErrorCannotComplete`) — the
    /// target app is hung, dying, or not answering within the messaging timeout.
    case cannotComplete
    /// The window does not support the requested attribute
    /// (`kAXErrorAttributeUnsupported` and friends).
    case attributeUnsupported
    /// The write "succeeded" at the AX layer but the read-back frame is
    /// grossly off — the app rejected or clamped the write (known behavior of
    /// some Electron/Java apps). `attribute` is `"position"` or `"size"`.
    case writeRejected(attribute: String)
    /// The AX element no longer refers to a live window (`kAXErrorInvalidUIElement`).
    case invalidWindow
    /// Accessibility is not granted / the AX API is disabled for this process
    /// (`kAXErrorAPIDisabled`, `kAXErrorNotTrusted`, or an untrusted process).
    case notPermitted
    /// Any other AXError code, preserved for diagnostics.
    case unexpected(code: Int32)

    public var description: String {
        switch self {
        case .cannotComplete: return "AX request could not complete (app hung or unresponsive)"
        case .attributeUnsupported: return "window does not support the requested AX attribute"
        case .writeRejected(let attribute): return "window rejected the \(attribute) write"
        case .invalidWindow: return "AX element no longer refers to a live window"
        case .notPermitted: return "Accessibility permission not granted"
        case .unexpected(let code): return "unexpected AXError code \(code)"
        }
    }
}

/// A display as the window-manipulation core sees it: identity facts plus its
/// bounds in the canonical Quartz top-left-origin global coordinate space.
public struct DisplayDescriptor: Equatable {
    /// The current `CGDirectDisplayID` — valid for this session only, never
    /// persisted (see `DisplayIdentity` for the stable key).
    public let id: CGDirectDisplayID
    /// Full display bounds in Quartz top-left-origin global coordinates
    /// (`CGDisplayBounds` shape) — used for window→display partitioning.
    public let quartzBounds: CGRect
    /// Usable area (menu bar and Dock excluded; `NSScreen.visibleFrame`
    /// converted to Quartz top-left space) — what grids tile against.
    public let usableBounds: CGRect
    /// Display facts snapshot used to compute the stable persisted identity.
    public let info: DisplayInfo

    /// Stable persistence key for this display (see U3).
    public var identity: DisplayIdentity { DisplayIdentity(info: info) }

    public init(id: CGDirectDisplayID, quartzBounds: CGRect, usableBounds: CGRect, info: DisplayInfo) {
        self.id = id
        self.quartzBounds = quartzBounds
        self.usableBounds = usableBounds
        self.info = info
    }
}

/// Seam over the Accessibility API (U2).
///
/// `LiveAXBackend` implements this over real `AXUIElement`s; tests drive
/// everything through a fake, because live AX requires a trusted process and
/// cannot run under the unprivileged test runner (by design — see the manual
/// integration checklist in `LiveAXBackend.swift`).
///
/// Coordinate rule: every `CGRect` crossing this seam is in Quartz
/// top-left-origin global coordinates. AX positions already are; the single
/// Cocoa→Quartz flip for NSScreen-derived rects happens inside
/// `LiveAXBackend.displays()` and nowhere else.
public protocol AXBackend {
    /// The focused window of the frontmost application, or nil when no app
    /// has a focused window (e.g. Finder desktop focus). Never a crash.
    func focusedWindow() throws -> AXWindowHandle?

    /// All on-screen standard (non-minimized) windows across regular apps.
    func windows() throws -> [AXWindowHandle]

    /// The window's frame in Quartz top-left global coordinates.
    func frame(of window: AXWindowHandle) throws -> CGRect

    /// Best-effort raw frame write (position + size). Verification that the
    /// window actually honored the write lives in `AXWindowController.setFrame`,
    /// which reads back and throws `.writeRejected` — so rejection detection is
    /// uniform across live and fake backends.
    func setFrame(_ frame: CGRect, of window: AXWindowHandle) throws

    /// Currently connected displays.
    func displays() -> [DisplayDescriptor]
}
