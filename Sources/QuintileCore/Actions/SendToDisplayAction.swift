import CoreGraphics

/// Send-focused-window-to-next-display (U7). The minimal multi-display escape
/// hatch shipped with U7 so multi-display users are never forced back to the
/// mouse; the richer cell-by-cell cross-display move stays deferred (plan).
///
/// Placement rule: the window's current span in its display's ACTIVE profile
/// is carried over as the "equivalent span" on the destination display's own
/// active profile — same (startCol, startRow, colSpan, rowSpan), clamped into
/// the destination grid (spans shrink to fit, starts pull back in-bounds) —
/// then framed against the destination's usableBounds.
public final class SendToDisplayAction {
    private let windowController: AXWindowController
    private let store: GridProfileStore

    public init(windowController: AXWindowController, store: GridProfileStore) {
        self.windowController = windowController
        self.store = store
    }

    public func send() -> ActionOutcome {
        do {
            guard let window = try windowController.focusedWindow() else {
                return .noFocusedWindow
            }
            // Cycle order: displays sorted by CGDirectDisplayID, wrap-around.
            let displays = windowController.displays().sorted { $0.id < $1.id }
            guard displays.count > 1 else {
                return .onlyOneDisplay // zero writes
            }
            guard let current = try windowController.display(containing: window),
                  let index = displays.firstIndex(where: { $0.id == current.id }) else {
                // Fully off-screen window: no source display to send from.
                return .noFocusedWindow
            }
            let next = displays[(index + 1) % displays.count]

            let sourceProfile = store.activeProfile(for: current.identity)
            let frame = try windowController.frame(of: window)
            let span = GridMath.frameToNearestSpan(profile: sourceProfile,
                                                   displayBounds: current.usableBounds,
                                                   frame: frame)

            let destProfile = store.activeProfile(for: next.identity)
            let clamped = span.anchored(at: (span.startCol, span.startRow), in: destProfile)
            let destFrame = GridMath.cellSpanToFrame(profile: destProfile,
                                                     displayBounds: next.usableBounds,
                                                     span: clamped)
            try windowController.setFrame(destFrame, of: window)
            return .performed
        } catch {
            return .failed(error.asAXWindowError)
        }
    }
}
