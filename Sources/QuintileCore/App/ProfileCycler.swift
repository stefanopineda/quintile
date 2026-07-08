/// U8's profile-cycle core: advances a display's active-profile POINTER and
/// nothing else.
///
/// Extracted from the app coordinator so the product guarantee "cycling never
/// retiles" is enforced by construction and testable: this type has no access
/// to `AXWindowController` or any `AXBackend`, so it cannot possibly write a
/// window frame. The coordinator's cycle flow calls this, then performs
/// feedback only (menu-bar transient indicator + overlay grid flash).
public final class ProfileCycler {

    /// The result the app layer turns into feedback, e.g. the transient
    /// menu-bar text "5×2 standard" and the overlay flash of `profile`.
    public struct CycleResult: Equatable {
        public let slot: ProfileSlot
        public let profile: GridProfile

        public init(slot: ProfileSlot, profile: GridProfile) {
            self.slot = slot
            self.profile = profile
        }
    }

    private let store: GridProfileStore

    public init(store: GridProfileStore) {
        self.store = store
    }

    /// Advances `identity`'s active slot (standard → secondary → tertiary →
    /// standard), persists via the store, and returns the newly active slot
    /// and its profile. Performs zero window writes by construction.
    @discardableResult
    public func cycle(for identity: DisplayIdentity) -> CycleResult {
        let slot = store.cycleActiveSlot(for: identity)
        let profile = store.config(for: identity)[slot]
        return CycleResult(slot: slot, profile: profile)
    }
}
