import CoreGraphics
import QuintileCore

/// U4 test scenarios: grid math is pure and side-effect-free.
func gridMathTests(_ t: TestHarness) {
    // A 32"-class usable area with a non-zero origin to catch origin-handling bugs.
    let bounds = CGRect(x: 100, y: 50, width: 3000, height: 1600)
    let fiveByTwo = GridProfile(name: "standard", rows: 2, cols: 5)

    t.suite("GridMath") { t in
        t.test("5×2 cell (2,0) maps to fractional rect x=0.4 w=0.2 h=0.5") {
            let frame = GridMath.cellSpanToFrame(
                profile: fiveByTwo, displayBounds: bounds,
                span: CellSpan(startCol: 2, startRow: 0))
            t.expectNearlyEqual(frame.minX, bounds.minX + 0.4 * bounds.width)
            t.expectNearlyEqual(frame.minY, bounds.minY)
            t.expectNearlyEqual(frame.width, 0.2 * bounds.width)
            t.expectNearlyEqual(frame.height, 0.5 * bounds.height)
        }

        t.test("horizontal 2-cell span produces the union rect") {
            let quad = GridProfile(name: "quad", rows: 2, cols: 2)
            let frame = GridMath.cellSpanToFrame(
                profile: quad, displayBounds: bounds,
                span: CellSpan(startCol: 0, startRow: 0, colSpan: 2, rowSpan: 1))
            t.expectEqual(frame, CGRect(x: bounds.minX, y: bounds.minY,
                                        width: bounds.width, height: bounds.height / 2))
        }

        t.test("exact cell frame round-trips to the same cell") {
            let span = CellSpan(startCol: 3, startRow: 1)
            let frame = GridMath.cellSpanToFrame(profile: fiveByTwo, displayBounds: bounds, span: span)
            t.expectEqual(GridMath.frameToNearestSpan(profile: fiveByTwo, displayBounds: bounds, frame: frame), span)
        }

        t.test("round-trip is exact for every valid span on a 5×2 grid") {
            for startCol in 0..<5 {
                for startRow in 0..<2 {
                    for colSpan in 1...(5 - startCol) {
                        for rowSpan in 1...(2 - startRow) {
                            let span = CellSpan(startCol: startCol, startRow: startRow,
                                                colSpan: colSpan, rowSpan: rowSpan)
                            let frame = GridMath.cellSpanToFrame(profile: fiveByTwo, displayBounds: bounds, span: span)
                            let back = GridMath.frameToNearestSpan(profile: fiveByTwo, displayBounds: bounds, frame: frame)
                            t.expectEqual(back, span, "round-trip failed for \(span)")
                        }
                    }
                }
            }
        }

        t.test("quadrant frame on 5×2 resolves to a proportionate span, never one cell") {
            let quadrant = CGRect(x: bounds.minX, y: bounds.minY,
                                  width: bounds.width / 2, height: bounds.height / 2)
            let span = GridMath.frameToNearestSpan(profile: fiveByTwo, displayBounds: bounds, frame: quadrant)
            t.expectEqual(span.startCol, 0)
            t.expectEqual(span.startRow, 0)
            t.expectEqual(span.rowSpan, 1)
            t.expect((2...3).contains(span.colSpan), "expected 2–3 column span, got \(span.colSpan)")
        }

        t.test("misaligned frame resolves to a valid ≥1×1 span without throwing") {
            let messy = CGRect(x: bounds.minX + 37, y: bounds.minY + 11, width: 123, height: 47)
            let span = GridMath.frameToNearestSpan(profile: fiveByTwo, displayBounds: bounds, frame: messy)
            t.expect(span.colSpan >= 1 && span.rowSpan >= 1)
            t.expect(span.startCol >= 0 && span.startCol + span.colSpan <= 5)
            t.expect(span.startRow >= 0 && span.startRow + span.rowSpan <= 2)
        }

        t.test("frame outside bounds clamps to a valid span") {
            let outside = CGRect(x: bounds.minX - 500, y: bounds.minY - 500, width: 200, height: 200)
            let span = GridMath.frameToNearestSpan(profile: fiveByTwo, displayBounds: bounds, frame: outside)
            t.expectEqual(span, CellSpan(startCol: 0, startRow: 0))
        }

        t.test("translated moves the whole footprint one cell") {
            let span = CellSpan(startCol: 1, startRow: 0, colSpan: 2, rowSpan: 1)
            t.expectEqual(GridMath.translated(span: span, direction: .right, in: fiveByTwo),
                          CellSpan(startCol: 2, startRow: 0, colSpan: 2, rowSpan: 1))
        }

        t.test("translated returns nil when any part of the footprint would leave the grid") {
            let wide = CellSpan(startCol: 3, startRow: 0, colSpan: 2, rowSpan: 1)
            t.expect(GridMath.translated(span: wide, direction: .right, in: fiveByTwo) == nil)
            t.expect(GridMath.translated(span: CellSpan(startCol: 0, startRow: 0), direction: .left, in: fiveByTwo) == nil)
            t.expect(GridMath.translated(span: CellSpan(startCol: 0, startRow: 0), direction: .up, in: fiveByTwo) == nil)
            t.expect(GridMath.translated(span: CellSpan(startCol: 0, startRow: 1), direction: .down, in: fiveByTwo) == nil)
        }

        t.test("CellSpan.between is order-independent") {
            let a = CellSpan.between((col: 4, row: 1), (col: 1, row: 0))
            let b = CellSpan.between((col: 1, row: 0), (col: 4, row: 1))
            t.expectEqual(a, b)
            t.expectEqual(a, CellSpan(startCol: 1, startRow: 0, colSpan: 4, rowSpan: 2))
        }

        t.test("CellSpan.intersects detects overlap and non-overlap") {
            let a = CellSpan(startCol: 0, startRow: 0, colSpan: 2, rowSpan: 1)
            t.expect(a.intersects(CellSpan(startCol: 1, startRow: 0)))
            t.expect(!a.intersects(CellSpan(startCol: 2, startRow: 0)))
            t.expect(!a.intersects(CellSpan(startCol: 0, startRow: 1)))
        }

        t.test("default profiles match the product decisions") {
            // Decision: standard = 5×2 (first-run active), secondary = 2×2, tertiary = 3×2.
            let standard = GridProfile.defaultProfile(for: .standard)
            t.expectEqual(standard.cols, 5)
            t.expectEqual(standard.rows, 2)
            t.expectEqual(GridProfile.defaultProfile(for: .secondary).cols, 2)
            t.expectEqual(GridProfile.defaultProfile(for: .tertiary).cols, 3)
        }

        t.test("profile slots cycle standard → secondary → tertiary → standard") {
            t.expectEqual(ProfileSlot.standard.next, .secondary)
            t.expectEqual(ProfileSlot.secondary.next, .tertiary)
            t.expectEqual(ProfileSlot.tertiary.next, .standard)
        }
    }
}
