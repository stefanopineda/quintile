import Foundation

/// A single grid cell address (top-left origin, like `CellSpan`).
public struct GridCell: Equatable, Hashable, Sendable {
    public var col: Int
    public var row: Int

    public init(col: Int, row: Int) {
        self.col = col
        self.row = row
    }
}

/// U6: the grid-select interaction state machine (keyboard-only).
///
/// Pure and fully unit-testable: no AppKit/SwiftUI, no timers, no AX calls.
/// Every input method returns the `Effect`s the app layer must perform
/// (show/update/dismiss the overlay, place the window); the machine itself
/// only tracks selection state. Implements exactly the transition diagram in
/// the plan's "Grid-select interaction state machine" section, including the
/// two-keypress `cornerPending` fast path and the interruption transitions.
public final class GridSelectionStateMachine {

    // MARK: - Observable state

    public enum SelectionState: Equatable {
        case idle
        /// Overlay open, single-cell selection at `anchor` (arrow-key path).
        case anchorSet(anchor: GridCell)
        /// A cell key jumped the anchor to a cell; the next cell key sets the
        /// opposite corner and auto-confirms (fast path).
        case cornerPending(anchor: GridCell)
        /// Shift+Arrow span selection. `span` is always the rectangle between
        /// the (hidden) anchor and `cursor`, so it is rectangular and ≥1×1 by
        /// construction.
        case extending(span: CellSpan, cursor: GridCell)
    }

    public enum InterruptionReason: Equatable, Sendable {
        case targetWindowClosed
        case appDeactivated
        case displayConfigurationChanged
    }

    public enum DismissReason: Equatable, Sendable {
        case confirmed
        case cancelled
        case interrupted(InterruptionReason)
    }

    /// Side effects for the app layer, in order. Confirm is emitted exactly
    /// once per session (leader press → idle), guarded by `hasConfirmed`.
    public enum Effect: Equatable {
        case showOverlay(GridProfile)
        case updateSelection(CellSpan)
        case confirm(CellSpan)
        case dismissOverlay(DismissReason)
        case noWindowToPlace
    }

    public private(set) var state: SelectionState = .idle

    /// The active profile for the session; nil while idle.
    public private(set) var profile: GridProfile?

    /// The fixed corner of the selection while `extending` (the cursor is the
    /// moving corner). Tracked here because `CellSpan` alone cannot tell which
    /// corner is anchored once the span is wider than one cell.
    private var anchor: GridCell?
    private var hasConfirmed = false

    public init() {}

    /// The current selection as a span (1×1 for anchor states), nil when idle.
    public var currentSelection: CellSpan? {
        switch state {
        case .idle: return nil
        case .anchorSet(let a), .cornerPending(let a): return singleCellSpan(a)
        case .extending(let span, _): return span
        }
    }

    // MARK: - Inputs

    /// Leader pressed with a focused window. The anchor is the start cell of
    /// the window's current span (`GridMath.frameToNearestSpan` upstream),
    /// clamped into the grid. Re-entrant: a second leader press restarts the
    /// session on the (possibly new) profile.
    @discardableResult
    public func begin(profile: GridProfile, initialSpan: CellSpan) -> [Effect] {
        self.profile = profile
        hasConfirmed = false
        let a = clamped(GridCell(col: initialSpan.startCol, row: initialSpan.startRow))
        anchor = a
        state = .anchorSet(anchor: a)
        return [.showOverlay(profile), .updateSelection(singleCellSpan(a))]
    }

    /// Leader pressed with no focused window: no overlay, brief indicator only.
    @discardableResult
    public func beginFailedNoWindow() -> [Effect] {
        guard case .idle = state else { return [] }
        return [.noWindowToPlace]
    }

    /// Arrow (no Shift): moves the anchor one cell, clamped at grid edges (no
    /// wraparound). From `extending` it collapses the span back to a
    /// single-cell `anchorSet` at the cursor position. From `cornerPending`
    /// (not covered by the diagram) it abandons the fast path and moves the
    /// anchor like `anchorSet` — the least surprising refinement behavior.
    @discardableResult
    public func arrow(_ direction: MoveDirection) -> [Effect] {
        switch state {
        case .idle:
            return []
        case .anchorSet(let a), .cornerPending(let a):
            let moved = clamped(a.moved(direction))
            anchor = moved
            state = .anchorSet(anchor: moved)
            return [.updateSelection(singleCellSpan(moved))]
        case .extending(_, let cursor):
            anchor = cursor
            state = .anchorSet(anchor: cursor)
            return [.updateSelection(singleCellSpan(cursor))]
        }
    }

    /// Shift+Arrow: enters/continues `extending`. The span is always the
    /// rectangle between the anchor and the cursor, so growth and shrink are
    /// monotonic and rectangular. At a grid edge the cursor clamps — the span
    /// is unchanged but the state still becomes/stays `extending`.
    @discardableResult
    public func shiftArrow(_ direction: MoveDirection) -> [Effect] {
        switch state {
        case .idle:
            return []
        case .anchorSet(let a), .cornerPending(let a):
            anchor = a
            let cursor = clamped(a.moved(direction))
            let span = CellSpan.between((a.col, a.row), (cursor.col, cursor.row))
            state = .extending(span: span, cursor: cursor)
            return [.updateSelection(span)]
        case .extending(_, let cursor):
            guard let a = anchor else { return [] } // unreachable by construction
            let moved = clamped(cursor.moved(direction))
            let span = CellSpan.between((a.col, a.row), (moved.col, moved.row))
            state = .extending(span: span, cursor: moved)
            return [.updateSelection(span)]
        }
    }

    /// Direct cell addressing. First press jumps the anchor to the cell
    /// (`cornerPending`); a second press sets the opposite corner and
    /// auto-confirms the rectangle between the two cells (fast path).
    @discardableResult
    public func cellKey(col: Int, row: Int) -> [Effect] {
        let cell = clamped(GridCell(col: col, row: row))
        switch state {
        case .idle:
            return []
        case .anchorSet, .extending:
            anchor = cell
            state = .cornerPending(anchor: cell)
            return [.updateSelection(singleCellSpan(cell))]
        case .cornerPending(let a):
            return confirm(CellSpan.between((a.col, a.row), (cell.col, cell.row)))
        }
    }

    /// Enter confirms the current selection (single cell in the anchor
    /// states, the span while extending) exactly once per session.
    @discardableResult
    public func enter() -> [Effect] {
        switch state {
        case .idle:
            return []
        case .anchorSet(let a), .cornerPending(let a):
            return confirm(singleCellSpan(a))
        case .extending(let span, _):
            return confirm(span)
        }
    }

    /// Esc cancels from any non-idle state: overlay dismissed, no confirm.
    @discardableResult
    public func escape() -> [Effect] {
        guard state != .idle else { return [] }
        endSession()
        return [.dismissOverlay(.cancelled)]
    }

    /// Interruption (target window closed / app deactivated / display config
    /// changed) from any non-idle state: overlay dismissed, no confirm.
    /// A no-op while idle.
    @discardableResult
    public func interrupted(_ reason: InterruptionReason) -> [Effect] {
        guard state != .idle else { return [] }
        endSession()
        return [.dismissOverlay(.interrupted(reason))]
    }

    // MARK: - Private

    private func confirm(_ span: CellSpan) -> [Effect] {
        guard !hasConfirmed else { return [] } // exactly once per session
        hasConfirmed = true
        endSession()
        return [.confirm(span), .dismissOverlay(.confirmed)]
    }

    private func endSession() {
        state = .idle
        anchor = nil
        profile = nil
    }

    private func singleCellSpan(_ cell: GridCell) -> CellSpan {
        CellSpan(startCol: cell.col, startRow: cell.row)
    }

    private func clamped(_ cell: GridCell) -> GridCell {
        guard let profile else { return cell }
        return GridCell(col: min(max(cell.col, 0), profile.cols - 1),
                        row: min(max(cell.row, 0), profile.rows - 1))
    }
}

// MARK: - Cell-key labels

public extension GridSelectionStateMachine {

    /// Keyboard rows used for direct cell addressing, top to bottom.
    private static let keyRows: [[Character]] = [
        Array("1234567890"),
        Array("QWERTYUIOP"),
        Array("ASDFGHJKL;"),
        Array("ZXCVBNM,./"),
    ]

    /// Per-cell key labels for a profile: row r of the grid maps to keyboard
    /// row r truncated to `cols` keys (digits, then QWERTY home rows).
    ///
    /// Limit: grids up to 10 columns × 4 rows. Larger grids return `[]` and
    /// the overlay falls back to arrow-key-only selection (no labels).
    static func cellKeyLayout(for profile: GridProfile) -> [[Character]] {
        guard profile.rows <= keyRows.count,
              profile.cols <= keyRows[0].count else { return [] }
        return (0..<profile.rows).map { Array(keyRows[$0].prefix(profile.cols)) }
    }

    /// Reverse lookup used by the app layer to translate a typed character
    /// into `cellKey(col:row:)`. Case-insensitive; nil for keys outside the
    /// profile's layout (including any grid beyond the 10×4 labeling limit).
    static func cell(forKey key: Character, profile: GridProfile) -> GridCell? {
        let upper = key.uppercased()
        let normalized = upper.count == 1 ? Character(upper) : key
        for (row, labels) in cellKeyLayout(for: profile).enumerated() {
            if let col = labels.firstIndex(of: normalized) {
                return GridCell(col: col, row: row)
            }
        }
        return nil
    }
}

private extension GridCell {
    /// One step in a grid direction (unclamped; callers clamp).
    func moved(_ direction: MoveDirection) -> GridCell {
        switch direction {
        case .left: return GridCell(col: col - 1, row: row)
        case .right: return GridCell(col: col + 1, row: row)
        case .up: return GridCell(col: col, row: row - 1)
        case .down: return GridCell(col: col, row: row + 1)
        }
    }
}
