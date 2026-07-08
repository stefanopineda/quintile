import CoreGraphics

/// Pure placement math. All frames are in the canonical Quartz top-left-origin
/// global coordinate space, and `displayBounds` is always the display's *usable
/// area* (visibleFrame converted to Quartz space) — menu bar and Dock excluded.
/// The single NSScreen→Quartz flip happens in the AX/display layer, never here.
public enum GridMath {

    /// Frame covering a rectangular cell span of `profile` within `displayBounds`.
    public static func cellSpanToFrame(profile: GridProfile, displayBounds: CGRect, span: CellSpan) -> CGRect {
        let cols = CGFloat(profile.cols)
        let rows = CGFloat(profile.rows)
        let fracX = CGFloat(span.startCol) / cols
        let fracY = CGFloat(span.startRow) / rows
        let fracW = CGFloat(span.colSpan) / cols
        let fracH = CGFloat(span.rowSpan) / rows
        return CGRect(
            x: displayBounds.origin.x + fracX * displayBounds.width,
            y: displayBounds.origin.y + fracY * displayBounds.height,
            width: fracW * displayBounds.width,
            height: fracH * displayBounds.height
        )
    }

    /// Inverse of `cellSpanToFrame`: each frame edge rounds to its nearest grid
    /// boundary (minimum span 1×1), so preset- or manually-sized frames resolve
    /// to a proportionate multi-cell span rather than collapsing to one cell.
    public static func frameToNearestSpan(profile: GridProfile, displayBounds: CGRect, frame: CGRect) -> CellSpan {
        let cellW = displayBounds.width / CGFloat(profile.cols)
        let cellH = displayBounds.height / CGFloat(profile.rows)

        // Boundary indices: left/top in 0...cols-1 / 0...rows-1, right/bottom clamped
        // to guarantee at least one cell.
        let leftBoundary = boundaryIndex((frame.minX - displayBounds.minX) / cellW, max: profile.cols)
        let topBoundary = boundaryIndex((frame.minY - displayBounds.minY) / cellH, max: profile.rows)
        let startCol = min(leftBoundary, profile.cols - 1)
        let startRow = min(topBoundary, profile.rows - 1)

        let rightBoundary = boundaryIndex((frame.maxX - displayBounds.minX) / cellW, max: profile.cols)
        let bottomBoundary = boundaryIndex((frame.maxY - displayBounds.minY) / cellH, max: profile.rows)
        let endCol = max(rightBoundary, startCol + 1)
        let endRow = max(bottomBoundary, startRow + 1)

        return CellSpan(startCol: startCol, startRow: startRow,
                        colSpan: endCol - startCol, rowSpan: endRow - startRow)
    }

    /// Translate a span one cell in a direction; nil when any part of the
    /// footprint would leave the grid (callers no-op and surface the boundary
    /// signal rather than clamping).
    public static func translated(span: CellSpan, direction: MoveDirection, in profile: GridProfile) -> CellSpan? {
        var moved = span
        switch direction {
        case .left: moved.startCol -= 1
        case .right: moved.startCol += 1
        case .up: moved.startRow -= 1
        case .down: moved.startRow += 1
        }
        guard moved.startCol >= 0, moved.startRow >= 0,
              moved.startCol + moved.colSpan <= profile.cols,
              moved.startRow + moved.rowSpan <= profile.rows else { return nil }
        return moved
    }

    private static func boundaryIndex(_ raw: CGFloat, max maxIndex: Int) -> Int {
        let rounded = Int((raw).rounded())
        return Swift.max(0, Swift.min(maxIndex, rounded))
    }
}

/// Direction for move-within-grid, in grid coordinates (top-left origin:
/// `up` decreases the row index).
public enum MoveDirection: String, CaseIterable, Sendable {
    case left, right, up, down
}
