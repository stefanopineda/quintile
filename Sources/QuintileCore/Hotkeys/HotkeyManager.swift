/// Global hotkey registration and dispatch (U5).
///
/// Pure logic over the `EventTapProviding` seam: exact modifier-chord + key
/// matching on key-down, first registration wins, everything else passes
/// through untouched.
///
/// ## Tap lifecycle (plan requirement)
/// `CGEvent.tapCreate` returns NULL while the process is not
/// Accessibility-trusted, so the manager must NOT create its tap at init.
/// Wire-up in the app layer:
///
/// ```swift
/// let hotkeys = HotkeyManager(tap: CGEventTapProvider())
/// permissionManager.onGrantedTransition { try? hotkeys.activate() }
/// permissionManager.checkOnLaunch()
/// // If already trusted at launch, onGrantedTransition fires immediately
/// // via the first trusted check, so activate() runs exactly when usable.
/// ```
///
/// `activate()` is idempotent: the handler fires on *every*
/// notDetermined/denied/revoked → granted transition (first-run users grant
/// permission mid-session and must not need a relaunch), and a second
/// activation re-enables the existing tap instead of creating another.
/// `handleTapDisabledByTimeout()` re-enables a tap the OS disabled with
/// `kCGEventTapDisabledByTimeout` (the real `CGEventTapProvider` also does
/// this inline in its callback; this hook exists for app-level recovery).
public final class HotkeyManager {

    private struct Registration {
        let id: String
        let binding: HotkeyBinding
        let action: () -> Void
    }

    private let tap: EventTapProviding
    private var registrations: [Registration] = []
    private var tapCreated = false

    public init(tap: EventTapProviding) {
        self.tap = tap
    }

    // MARK: Registration

    /// Registers `action` for an exact `binding` match. Re-registering an
    /// existing `id` replaces its binding and action.
    public func register(_ binding: HotkeyBinding, id: String, action: @escaping () -> Void) {
        registrations.removeAll { $0.id == id }
        registrations.append(Registration(id: id, binding: binding, action: action))
    }

    public func unregister(id: String) {
        registrations.removeAll { $0.id == id }
    }

    /// Current bindings keyed by action id — the data source for U8's
    /// shortcuts reference panel.
    public var bindings: [String: HotkeyBinding] {
        Dictionary(uniqueKeysWithValues: registrations.map { ($0.id, $0.binding) })
    }

    // MARK: Tap lifecycle

    /// Whether a tap exists and is currently enabled.
    public var isActive: Bool { tap.isActive }

    /// Creates and enables the event tap. Call only once Accessibility is
    /// granted (see the type doc for wiring). Safe to call repeatedly: after
    /// the first success it just re-enables, so re-grant transitions and
    /// double-activation are harmless.
    public func activate() throws {
        if !tapCreated {
            try tap.createTap { [weak self] event in
                self?.dispatch(event) ?? .passThrough
            }
            tapCreated = true
        }
        tap.enable()
    }

    /// Disables event delivery without tearing down registrations. Suitable
    /// for the granted → revoked transition.
    public func deactivate() {
        tap.disable()
    }

    /// Re-enables the tap after the OS disabled it for slow callback
    /// servicing (`kCGEventTapDisabledByTimeout` / `...ByUserInput`).
    /// No-op if the tap was never created.
    public func handleTapDisabledByTimeout() {
        guard tapCreated else { return }
        tap.enable()
    }

    // MARK: Dispatch

    /// Exact-match dispatch: key-down whose chord and key equal a registered
    /// binding runs that action and is consumed; everything else (key-ups,
    /// unbound keys, supersets/subsets of a bound chord) passes through, so
    /// two different bindings can never cross-fire.
    private func dispatch(_ event: KeyEvent) -> EventDisposition {
        guard event.isKeyDown else { return .passThrough }
        guard let match = registrations.first(where: {
            $0.binding.keyCode == event.keyCode && $0.binding.modifiers == event.modifiers
        }) else {
            return .passThrough
        }
        match.action()
        return .consume
    }
}
