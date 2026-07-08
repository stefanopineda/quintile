import Foundation

/// A named grid definition: how a display is divided into rows × columns.
public struct GridProfile: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var rows: Int
    public var cols: Int

    public init(name: String, rows: Int, cols: Int) {
        precondition(rows >= 1 && cols >= 1, "GridProfile requires at least a 1×1 grid")
        self.name = name
        self.rows = rows
        self.cols = cols
    }

    private enum CodingKeys: String, CodingKey {
        case name, rows, cols
    }

    /// Custom decode so a corrupt/hand-edited profiles.json surfaces as a
    /// `DecodingError` (which `GridProfileStore.init` throws and the app's
    /// fallback path handles) instead of tripping the memberwise
    /// precondition and crash-looping on every launch.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let rows = try container.decode(Int.self, forKey: .rows)
        let cols = try container.decode(Int.self, forKey: .cols)
        guard (1...100).contains(rows), (1...100).contains(cols) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: container.codingPath,
                debugDescription: "GridProfile requires 1...100 rows and cols, got \(rows)×\(cols)"))
        }
        self.name = name
        self.rows = rows
        self.cols = cols
    }
}

/// The three per-display profile slots. The slot is the stable identity a
/// display's configuration cycles through; the profile is its current value.
public enum ProfileSlot: String, Codable, CaseIterable, Sendable {
    case standard
    case secondary
    case tertiary

    /// Cycle order: standard → secondary → tertiary → standard.
    public var next: ProfileSlot {
        switch self {
        case .standard: return .secondary
        case .secondary: return .tertiary
        case .tertiary: return .standard
        }
    }
}

public extension GridProfile {
    /// First-run defaults. `standard` is the 5×2 daily-driver grid and is the
    /// active profile on first connect; all three are user-editable placeholders.
    static func defaultProfile(for slot: ProfileSlot) -> GridProfile {
        switch slot {
        case .standard: return GridProfile(name: "standard", rows: 2, cols: 5)
        case .secondary: return GridProfile(name: "secondary", rows: 2, cols: 2)
        case .tertiary: return GridProfile(name: "tertiary", rows: 2, cols: 3)
        }
    }
}

/// A rectangular selection of grid cells: origin cell plus spans.
/// Invariants: 0 ≤ startCol, startCol + colSpan ≤ cols, colSpan ≥ 1 (same for rows).
public struct CellSpan: Codable, Equatable, Hashable, Sendable {
    public var startCol: Int
    public var startRow: Int
    public var colSpan: Int
    public var rowSpan: Int

    public init(startCol: Int, startRow: Int, colSpan: Int = 1, rowSpan: Int = 1) {
        precondition(colSpan >= 1 && rowSpan >= 1, "CellSpan requires spans of at least 1")
        self.startCol = startCol
        self.startRow = startRow
        self.colSpan = colSpan
        self.rowSpan = rowSpan
    }

    public var endCol: Int { startCol + colSpan - 1 }
    public var endRow: Int { startRow + rowSpan - 1 }

    public func contains(col: Int, row: Int) -> Bool {
        col >= startCol && col <= endCol && row >= startRow && row <= endRow
    }

    public func intersects(_ other: CellSpan) -> Bool {
        startCol <= other.endCol && other.startCol <= endCol &&
        startRow <= other.endRow && other.startRow <= endRow
    }

    /// The rectangular span between two cells (order-independent corners).
    public static func between(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int)) -> CellSpan {
        let minCol = min(a.col, b.col), maxCol = max(a.col, b.col)
        let minRow = min(a.row, b.row), maxRow = max(a.row, b.row)
        return CellSpan(startCol: minCol, startRow: minRow,
                        colSpan: maxCol - minCol + 1, rowSpan: maxRow - minRow + 1)
    }
}
