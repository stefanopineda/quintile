import Foundation
import QuintileCore

/// U6 test scenarios: grid-select state machine over a 5×2 profile.
func stateMachineTests(_ t: TestHarness) {
    typealias Effect = GridSelectionStateMachine.Effect
    typealias State = GridSelectionStateMachine.SelectionState
    typealias Reason = GridSelectionStateMachine.InterruptionReason

    let p52 = GridProfile(name: "secondary", rows: 2, cols: 5)

    func span(_ col: Int, _ row: Int, _ colSpan: Int = 1, _ rowSpan: Int = 1) -> CellSpan {
        CellSpan(startCol: col, startRow: row, colSpan: colSpan, rowSpan: rowSpan)
    }

    func begun(at col: Int = 0, _ row: Int = 0) -> GridSelectionStateMachine {
        let machine = GridSelectionStateMachine()
        machine.begin(profile: p52, initialSpan: span(col, row))
        return machine
    }

    func confirmCount(_ effects: [Effect]) -> Int {
        effects.filter { if case .confirm = $0 { return true } else { return false } }.count
    }

    t.suite("GridSelectionStateMachine session entry") { t in
        t.test("begin sets anchor to the initial span's start cell and shows overlay") {
            let machine = GridSelectionStateMachine()
            let effects = machine.begin(profile: p52, initialSpan: span(2, 1, 2, 1))
            t.expectEqual(effects, [.showOverlay(p52), .updateSelection(span(2, 1))])
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 2, row: 1)))
        }

        t.test("begin clamps an out-of-grid initial cell into the grid") {
            let machine = GridSelectionStateMachine()
            let effects = machine.begin(profile: p52, initialSpan: span(9, 5))
            t.expectEqual(effects, [.showOverlay(p52), .updateSelection(span(4, 1))])
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 4, row: 1)))
        }

        t.test("beginFailedNoWindow stays idle, emits noWindowToPlace, no overlay") {
            let machine = GridSelectionStateMachine()
            let effects = machine.beginFailedNoWindow()
            t.expectEqual(effects, [.noWindowToPlace])
            t.expectEqual(machine.state, .idle)
        }
    }

    t.suite("GridSelectionStateMachine arrow movement") { t in
        t.test("arrow moves the anchor exactly one cell") {
            let machine = begun(at: 1, 0)
            let effects = machine.arrow(.right)
            t.expectEqual(effects, [.updateSelection(span(2, 0))])
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 2, row: 0)))
        }

        t.test("arrow clamps at grid boundaries: 10× left from col 0 stays col 0") {
            let machine = begun(at: 0, 0)
            for _ in 0..<10 { machine.arrow(.left) }
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 0, row: 0)))
            for _ in 0..<10 { machine.arrow(.up) }
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 0, row: 0)))
        }

        t.test("arrow clamps at far edges: 10× right/down on 5×2 stays at (4,1)") {
            let machine = begun(at: 4, 1)
            for _ in 0..<10 { machine.arrow(.right) }
            for _ in 0..<10 { machine.arrow(.down) }
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 4, row: 1)))
        }
    }

    t.suite("GridSelectionStateMachine extending") { t in
        t.test("shiftArrow from anchorSet enters extending with exactly 2 cells") {
            let machine = begun(at: 1, 0)
            let effects = machine.shiftArrow(.right)
            t.expectEqual(effects, [.updateSelection(span(1, 0, 2, 1))])
            t.expectEqual(machine.state, .extending(span: span(1, 0, 2, 1),
                                                    cursor: GridCell(col: 2, row: 0)))
        }

        t.test("repeated shiftArrow grows monotonically and clamps at the edge") {
            let machine = begun(at: 0, 0)
            machine.shiftArrow(.right) // cols 0-1
            machine.shiftArrow(.right) // cols 0-2
            machine.shiftArrow(.right) // cols 0-3
            machine.shiftArrow(.right) // cols 0-4
            t.expectEqual(machine.state, .extending(span: span(0, 0, 5, 1),
                                                    cursor: GridCell(col: 4, row: 0)))
            let clampedEffects = machine.shiftArrow(.right) // clamped: unchanged
            t.expectEqual(clampedEffects, [.updateSelection(span(0, 0, 5, 1))])
            t.expectEqual(machine.state, .extending(span: span(0, 0, 5, 1),
                                                    cursor: GridCell(col: 4, row: 0)))
            machine.shiftArrow(.down) // grows to 5×2, still rectangular
            t.expectEqual(machine.state, .extending(span: span(0, 0, 5, 2),
                                                    cursor: GridCell(col: 4, row: 1)))
        }

        t.test("reversing shiftArrow shrinks back down, never below 1×1") {
            let machine = begun(at: 2, 0)
            machine.shiftArrow(.right) // cols 2-3
            let shrunk = machine.shiftArrow(.left) // back to single cell, still extending
            t.expectEqual(shrunk, [.updateSelection(span(2, 0))])
            t.expectEqual(machine.state, .extending(span: span(2, 0),
                                                    cursor: GridCell(col: 2, row: 0)))
            // Continuing past the anchor grows to the other side (rectangular from anchor).
            machine.shiftArrow(.left)
            t.expectEqual(machine.state, .extending(span: span(1, 0, 2, 1),
                                                    cursor: GridCell(col: 1, row: 0)))
        }

        t.test("shiftArrow into an edge from anchorSet still enters extending with a 1×1 span") {
            let machine = begun(at: 0, 0)
            let effects = machine.shiftArrow(.left)
            t.expectEqual(effects, [.updateSelection(span(0, 0))])
            t.expectEqual(machine.state, .extending(span: span(0, 0),
                                                    cursor: GridCell(col: 0, row: 0)))
        }

        t.test("arrow (no shift) from extending collapses to a single cell at the cursor") {
            let machine = begun(at: 0, 0)
            machine.shiftArrow(.right)
            machine.shiftArrow(.right) // span cols 0-2, cursor (2,0)
            let effects = machine.arrow(.left)
            t.expectEqual(effects, [.updateSelection(span(2, 0))])
            t.expectEqual(machine.state, .anchorSet(anchor: GridCell(col: 2, row: 0)))
        }
    }

    t.suite("GridSelectionStateMachine cell-key fast path") { t in
        t.test("first cellKey jumps the anchor into cornerPending with a 1×1 selection") {
            let machine = begun(at: 0, 0)
            let effects = machine.cellKey(col: 1, row: 0)
            t.expectEqual(effects, [.updateSelection(span(1, 0))])
            t.expectEqual(machine.state, .cornerPending(anchor: GridCell(col: 1, row: 0)))
        }

        t.test("second cellKey confirms the span between the two cells exactly once and returns to idle") {
            let machine = begun(at: 0, 0)
            let first = machine.cellKey(col: 1, row: 0)
            let second = machine.cellKey(col: 4, row: 1)
            t.expectEqual(second, [.confirm(span(1, 0, 4, 2)), .dismissOverlay(.confirmed)])
            t.expectEqual(confirmCount(first + second), 1)
            t.expectEqual(machine.state, .idle)
        }

        t.test("second cellKey with corners reversed yields the same normalized span") {
            let machine = begun(at: 0, 0)
            machine.cellKey(col: 4, row: 1)
            let effects = machine.cellKey(col: 1, row: 0)
            t.expectEqual(effects, [.confirm(span(1, 0, 4, 2)), .dismissOverlay(.confirmed)])
        }

        t.test("same cellKey twice confirms a 1×1 span") {
            let machine = begun(at: 0, 0)
            machine.cellKey(col: 2, row: 1)
            let effects = machine.cellKey(col: 2, row: 1)
            t.expectEqual(effects, [.confirm(span(2, 1)), .dismissOverlay(.confirmed)])
            t.expectEqual(machine.state, .idle)
        }

        t.test("cellKey from extending abandons the span and enters cornerPending") {
            let machine = begun(at: 0, 0)
            machine.shiftArrow(.right)
            let effects = machine.cellKey(col: 3, row: 1)
            t.expectEqual(effects, [.updateSelection(span(3, 1))])
            t.expectEqual(machine.state, .cornerPending(anchor: GridCell(col: 3, row: 1)))
        }
    }

    t.suite("GridSelectionStateMachine confirm, cancel, interrupt") { t in
        t.test("enter from anchorSet confirms the single cell exactly once and goes idle") {
            let machine = begun(at: 3, 1)
            let effects = machine.enter()
            t.expectEqual(effects, [.confirm(span(3, 1)), .dismissOverlay(.confirmed)])
            t.expectEqual(machine.state, .idle)
        }

        t.test("enter from extending confirms the current span exactly once and goes idle") {
            let machine = begun(at: 0, 0)
            machine.shiftArrow(.right)
            machine.shiftArrow(.down)
            let effects = machine.enter()
            t.expectEqual(effects, [.confirm(span(0, 0, 2, 2)), .dismissOverlay(.confirmed)])
            t.expectEqual(machine.state, .idle)
        }

        t.test("enter from cornerPending confirms the single cell at the anchor") {
            let machine = begun(at: 0, 0)
            machine.cellKey(col: 2, row: 0)
            let effects = machine.enter()
            t.expectEqual(effects, [.confirm(span(2, 0)), .dismissOverlay(.confirmed)])
            t.expectEqual(machine.state, .idle)
        }

        t.test("double enter emits a single confirm") {
            let machine = begun(at: 1, 1)
            let first = machine.enter()
            let second = machine.enter()
            t.expectEqual(confirmCount(first), 1)
            t.expectEqual(second, [])
            t.expectEqual(machine.state, .idle)
        }

        t.test("escape from each non-idle state dismisses with no confirm") {
            let fromAnchorSet = begun(at: 1, 0)
            let fromCornerPending = begun(at: 1, 0)
            fromCornerPending.cellKey(col: 2, row: 1)
            let fromExtending = begun(at: 1, 0)
            fromExtending.shiftArrow(.down)

            for machine in [fromAnchorSet, fromCornerPending, fromExtending] {
                let effects = machine.escape()
                t.expectEqual(effects, [.dismissOverlay(.cancelled)])
                t.expectEqual(confirmCount(effects), 0)
                t.expectEqual(machine.state, .idle)
            }
        }

        t.test("interrupted (each reason) from each non-idle state dismisses with no confirm") {
            let reasons: [Reason] = [.targetWindowClosed, .appDeactivated, .displayConfigurationChanged]
            for reason in reasons {
                let fromAnchorSet = begun(at: 1, 0)
                let fromCornerPending = begun(at: 1, 0)
                fromCornerPending.cellKey(col: 2, row: 1)
                let fromExtending = begun(at: 1, 0)
                fromExtending.shiftArrow(.right)

                for machine in [fromAnchorSet, fromCornerPending, fromExtending] {
                    let effects = machine.interrupted(reason)
                    t.expectEqual(effects, [.dismissOverlay(.interrupted(reason))])
                    t.expectEqual(confirmCount(effects), 0)
                    t.expectEqual(machine.state, .idle)
                }
            }
        }

        t.test("interrupted while idle is a no-op") {
            let machine = GridSelectionStateMachine()
            for reason in [Reason.targetWindowClosed, .appDeactivated, .displayConfigurationChanged] {
                t.expectEqual(machine.interrupted(reason), [])
                t.expectEqual(machine.state, .idle)
            }
        }

        t.test("inputs after a confirmed session are no-ops (no second confirm)") {
            let machine = begun(at: 0, 0)
            machine.cellKey(col: 0, row: 0)
            machine.cellKey(col: 4, row: 1) // fast-path confirm
            var trailing: [GridSelectionStateMachine.Effect] = []
            trailing += machine.enter()
            trailing += machine.cellKey(col: 1, row: 1)
            trailing += machine.arrow(.left)
            trailing += machine.shiftArrow(.right)
            trailing += machine.escape()
            t.expectEqual(trailing, [])
            t.expectEqual(machine.state, .idle)
        }
    }

    t.suite("GridSelectionStateMachine cell-key layout") { t in
        t.test("cellKeyLayout for 5×2 is 12345 / QWERT") {
            let layout = GridSelectionStateMachine.cellKeyLayout(for: p52)
            t.expectEqual(layout, [["1", "2", "3", "4", "5"], ["Q", "W", "E", "R", "T"]])
        }

        t.test("cell(forKey:) round-trips every label in the layout") {
            for (row, labels) in GridSelectionStateMachine.cellKeyLayout(for: p52).enumerated() {
                for (col, key) in labels.enumerated() {
                    t.expectEqual(GridSelectionStateMachine.cell(forKey: key, profile: p52),
                                  GridCell(col: col, row: row), "key \(key)")
                }
            }
        }

        t.test("cell(forKey:) is case-insensitive and nil for unmapped keys") {
            t.expectEqual(GridSelectionStateMachine.cell(forKey: "t", profile: p52),
                          GridCell(col: 4, row: 1))
            t.expectEqual(GridSelectionStateMachine.cell(forKey: "Z", profile: p52), nil)
            t.expectEqual(GridSelectionStateMachine.cell(forKey: "6", profile: p52), nil)
        }

        t.test("grids beyond 10×4 have no key layout (arrow-only fallback)") {
            let wide = GridProfile(name: "wide", rows: 2, cols: 11)
            let tall = GridProfile(name: "tall", rows: 5, cols: 3)
            t.expectEqual(GridSelectionStateMachine.cellKeyLayout(for: wide), [])
            t.expectEqual(GridSelectionStateMachine.cellKeyLayout(for: tall), [])
            t.expectEqual(GridSelectionStateMachine.cell(forKey: "1", profile: wide), nil)
        }

        t.test("exposed labeling limits are 10 columns × 4 rows (preferences steppers read these)") {
            t.expectEqual(GridSelectionStateMachine.maxLabeledCols, 10)
            t.expectEqual(GridSelectionStateMachine.maxLabeledRows, 4)
        }
    }
}
