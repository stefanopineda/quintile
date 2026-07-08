/// Event-tap seam (U5). `HotkeyManager` dispatches over this protocol so its
/// logic is unit-testable with a fake tap; the real `CGEventTapProvider`
/// wraps `CGEvent.tapCreate` and requires an Accessibility-trusted process.

/// What the tap callback tells the OS to do with an event.
public enum EventDisposition {
    /// Swallow the event — neither WindowServer nor the focused app sees it.
    case consume
    /// Deliver the event unchanged.
    case passThrough
}

/// Errors thrown by tap creation.
public enum EventTapError: Error, Equatable {
    /// `CGEvent.tapCreate` returned NULL — in practice this means the process
    /// is not Accessibility-trusted (yet). Callers retry after the grant
    /// transition; see `HotkeyManager.activate()`.
    case creationFailed
}

/// Seam over a session-level keyboard event tap.
///
/// Contract:
/// - `createTap` installs the handler but does not enable delivery.
/// - `enable()`/`disable()` toggle delivery; both are idempotent and no-ops
///   before `createTap` succeeds.
/// - `destroyTap()` tears the tap down completely; a later `createTap` must
///   build a fresh one. Idempotent; no-op before `createTap` succeeds.
/// - `isActive` is true only while a created tap is enabled.
public protocol EventTapProviding: AnyObject {
    func createTap(handler: @escaping (KeyEvent) -> EventDisposition) throws
    func enable()
    func disable()
    func destroyTap()
    var isActive: Bool { get }
}
