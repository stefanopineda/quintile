import CoreGraphics

/// Outcome of a move-within-grid action (U7).
public enum MoveOutcome: Equatable {
    /// The mover reached its destination. `occupantErrors` collects any
    /// occupant relocations that failed along the way (the move itself still
    /// counts as performed — the mover landed).
    case moved(occupantErrors: [AXWindowError])
    /// The translated footprint would leave the grid: no write occurred; the
    /// app layer plays the boundary-reached signal.
    case boundaryReached
    /// No app has a focused window (or it overlaps no display) — no writes.
    case noFocusedWindow
    /// The mover's own frame write failed (typed AX error preserved).
    case failed(AXWindowError)
}

/// Move-focused-window-one-cell with FOOTPRINT TRANSLATION semantics
/// (product decision, plan Key Technical Decisions):
///
/// - The mover's whole span translates one cell in the direction; span
///   dimensions are preserved by construction (`GridMath.translated`).
/// - At the grid boundary the translation is nil → no-op + boundary signal.
/// - Every other window whose nearest-span footprint intersects the
///   destination relocates into the VACATED footprint (the mover's previous
///   span), each preserving its own colSpan/rowSpan, anchored at the vacated
///   span's start cell and clamped to fit the grid. A single occupant with an
///   identical span is the classic swap.
public final class MoveWithinGridAction {
    private let windowController: AXWindowController
    private let store: GridProfileStore

    public init(windowController: AXWindowController, store: GridProfileStore) {
        self.windowController = windowController
        self.store = store
    }

    public func move(_ direction: MoveDirection) -> MoveOutcome {
        do {
            guard let mover = try windowController.focusedWindow() else {
                return .noFocusedWindow
            }
            guard let display = try windowController.display(containing: mover) else {
                // Fully off-screen window: no grid to move within.
                return .noFocusedWindow
            }
            let profile = store.activeProfile(for: display.identity)
            let bounds = display.usableBounds

            // A manually-resized or preset-placed frame resolves to its
            // nearest span first; the destination is that span translated.
            let currentFrame = try windowController.frame(of: mover)
            let currentSpan = GridMath.frameToNearestSpan(profile: profile,
                                                          displayBounds: bounds,
                                                          frame: currentFrame)
            guard let destSpan = GridMath.translated(span: currentSpan,
                                                     direction: direction,
                                                     in: profile) else {
                return .boundaryReached // zero writes; caller surfaces the signal
            }

            // Occupants: every OTHER window on this display whose nearest-span
            // footprint intersects the destination. Windows with unreadable
            // frames (hung app, just-closed) are skipped, never fatal.
            var occupants: [(window: AXWindowHandle, span: CellSpan)] = []
            for other in try windowController.windows(onDisplay: display)
            where !other.isSame(as: mover) {
                guard let otherFrame = try? windowController.frame(of: other) else { continue }
                let otherSpan = GridMath.frameToNearestSpan(profile: profile,
                                                            displayBounds: bounds,
                                                            frame: otherFrame)
                if otherSpan.intersects(destSpan) {
                    occupants.append((other, otherSpan))
                }
            }

            // AX writes are not atomic: a partial failure can leave occupants
            // already relocated. Occupants are written first and the mover
            // last (so the mover ends up frontmost at its destination and a
            // mover failure leaves it where it was). Occupant errors are
            // collected — remaining writes continue — and surfaced in the
            // outcome; only a failed MOVER write makes the whole move .failed.
            var occupantErrors: [AXWindowError] = []
            for (occupant, span) in occupants {
                let relocated = span.anchored(at: (currentSpan.startCol, currentSpan.startRow),
                                              in: profile)
                let frame = GridMath.cellSpanToFrame(profile: profile,
                                                     displayBounds: bounds,
                                                     span: relocated)
                do {
                    try windowController.setFrame(frame, of: occupant)
                } catch {
                    occupantErrors.append(error.asAXWindowError)
                }
            }

            let destFrame = GridMath.cellSpanToFrame(profile: profile,
                                                     displayBounds: bounds,
                                                     span: destSpan)
            do {
                try windowController.setFrame(destFrame, of: mover)
            } catch {
                return .failed(error.asAXWindowError)
            }
            return .moved(occupantErrors: occupantErrors)
        } catch {
            return .failed(error.asAXWindowError)
        }
    }
}
