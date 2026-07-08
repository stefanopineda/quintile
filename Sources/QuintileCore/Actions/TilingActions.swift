import CoreGraphics

/// Outcome of a one-shot tiling action (U7). The app layer turns these into
/// user feedback (indicator flash, sound); actions themselves never crash on
/// "nothing to place" and never swallow AX errors.
public enum ActionOutcome: Equatable {
    /// The window was placed.
    case performed
    /// No app has a focused window (or the window overlaps no display) —
    /// nothing to place, no writes performed.
    case noFocusedWindow
    /// Send-to-display only: a single display is connected, nowhere to send.
    case onlyOneDisplay
    /// An AX call failed; the typed error is preserved for diagnostics.
    case failed(AXWindowError)
}

/// The fixed preset actions (R1): quadrants, horizontal thirds, vertical
/// halves, and the six third×half "sixths".
///
/// Presets are expressed against an *implicit* grid (quadrants = 2×2,
/// thirds = 3×1, halves = 1×2, sixths = 3×2) — always, regardless of the
/// display's active standard/secondary/tertiary profile (plan decision:
/// presets are a separate, always-available action set). A preset frame
/// generally does not align to the active profile's boundaries; that is fine —
/// `GridMath.frameToNearestSpan`'s edge-rounding resolves it to a
/// proportionate span when a later move-within-grid needs one.
public enum PresetAction: String, CaseIterable, Sendable {
    /// Quadrants on the implicit 2×2 grid: 1 = top-left, 2 = top-right,
    /// 3 = bottom-left, 4 = bottom-right.
    case quadrant1, quadrant2, quadrant3, quadrant4
    /// Horizontal thirds on the implicit 3×1 grid (full height).
    case thirdLeft, thirdCenter, thirdRight
    /// Vertical halves on the implicit 1×2 grid (full width).
    case halfTop, halfBottom
    /// Sixths on the implicit 3×2 grid, enumerated left/center/right ×
    /// top/bottom: 1 = left-top, 2 = left-bottom, 3 = center-top,
    /// 4 = center-bottom, 5 = right-top, 6 = right-bottom.
    case sixth1, sixth2, sixth3, sixth4, sixth5, sixth6

    /// The implicit grid this preset tiles against.
    public var implicitProfile: GridProfile {
        switch self {
        case .quadrant1, .quadrant2, .quadrant3, .quadrant4:
            return GridProfile(name: "quadrants", rows: 2, cols: 2)
        case .thirdLeft, .thirdCenter, .thirdRight:
            return GridProfile(name: "thirds", rows: 1, cols: 3)
        case .halfTop, .halfBottom:
            return GridProfile(name: "halves", rows: 2, cols: 1)
        case .sixth1, .sixth2, .sixth3, .sixth4, .sixth5, .sixth6:
            return GridProfile(name: "sixths", rows: 2, cols: 3)
        }
    }

    /// The single-cell span of this preset within `implicitProfile`.
    public var span: CellSpan {
        switch self {
        case .quadrant1: return CellSpan(startCol: 0, startRow: 0)
        case .quadrant2: return CellSpan(startCol: 1, startRow: 0)
        case .quadrant3: return CellSpan(startCol: 0, startRow: 1)
        case .quadrant4: return CellSpan(startCol: 1, startRow: 1)
        case .thirdLeft: return CellSpan(startCol: 0, startRow: 0)
        case .thirdCenter: return CellSpan(startCol: 1, startRow: 0)
        case .thirdRight: return CellSpan(startCol: 2, startRow: 0)
        case .halfTop: return CellSpan(startCol: 0, startRow: 0)
        case .halfBottom: return CellSpan(startCol: 0, startRow: 1)
        case .sixth1: return CellSpan(startCol: 0, startRow: 0)
        case .sixth2: return CellSpan(startCol: 0, startRow: 1)
        case .sixth3: return CellSpan(startCol: 1, startRow: 0)
        case .sixth4: return CellSpan(startCol: 1, startRow: 1)
        case .sixth5: return CellSpan(startCol: 2, startRow: 0)
        case .sixth6: return CellSpan(startCol: 2, startRow: 1)
        }
    }
}

/// Executes preset actions against the focused window's display (U7).
public final class TilingActions {
    private let windowController: AXWindowController

    public init(windowController: AXWindowController) {
        self.windowController = windowController
    }

    /// Places the focused window into `preset`'s region of its display's
    /// usable bounds. No focused window (or an off-screen window belonging to
    /// no display) is a `.noFocusedWindow` outcome, never a crash.
    public func perform(_ preset: PresetAction) -> ActionOutcome {
        do {
            guard let window = try windowController.focusedWindow() else {
                return .noFocusedWindow
            }
            guard let display = try windowController.display(containing: window) else {
                // Fully off-screen window: no display to tile against.
                return .noFocusedWindow
            }
            let frame = GridMath.cellSpanToFrame(profile: preset.implicitProfile,
                                                 displayBounds: display.usableBounds,
                                                 span: preset.span)
            try windowController.setFrame(frame, of: window)
            return .performed
        } catch {
            return .failed(error.asAXWindowError)
        }
    }
}

// MARK: - Shared action helpers (module-internal)

extension CellSpan {
    /// This span's dimensions re-anchored at `start`, clamped so the result
    /// fits inside `profile` (spans shrink to the grid size if oversized,
    /// then the start is pulled back so the footprint stays in bounds).
    func anchored(at start: (col: Int, row: Int), in profile: GridProfile) -> CellSpan {
        let colSpan = Swift.min(self.colSpan, profile.cols)
        let rowSpan = Swift.min(self.rowSpan, profile.rows)
        let startCol = Swift.max(0, Swift.min(start.col, profile.cols - colSpan))
        let startRow = Swift.max(0, Swift.min(start.row, profile.rows - rowSpan))
        return CellSpan(startCol: startCol, startRow: startRow,
                        colSpan: colSpan, rowSpan: rowSpan)
    }
}

extension Error {
    /// Every failing backend call throws `AXWindowError`; anything else is
    /// preserved as `.unexpected` so no error is ever silently dropped.
    var asAXWindowError: AXWindowError {
        (self as? AXWindowError) ?? .unexpected(code: -1)
    }
}
