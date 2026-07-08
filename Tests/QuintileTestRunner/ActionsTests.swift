import CoreGraphics
import Foundation
import QuintileCore

// MARK: - Fakes
//
// The plain backend/window fakes live in SharedFakes.swift (shared with
// AXControllerTests). Only the wrapper-identity fixture below stays local.

/// Handle with WRAPPER identity: the backend below returns a FRESH wrapper
/// object per call (like `LiveAXBackend` wrapping `AXUIElement`s), so
/// reference identity cannot tell two handles to the same window apart —
/// `isSame` must compare the shared underlying identity, and callers must
/// reach it via dynamic dispatch (the protocol requirement).
private final class WrapperFakeWindow: AXWindowHandle {
    let underlying: FakeWindow

    init(underlying: FakeWindow) {
        self.underlying = underlying
    }

    func isSame(as other: AXWindowHandle) -> Bool {
        guard let wrapper = other as? WrapperFakeWindow else { return false }
        return underlying === wrapper.underlying
    }
}

/// Backend whose `focusedWindow()` and `windows()` hand out DISTINCT wrapper
/// objects for the same underlying window — the live backend's shape.
private final class WrapperFakeBackend: AXBackend {
    var allWindows: [FakeWindow] = []
    var focused: FakeWindow?
    var displayList: [DisplayDescriptor] = []
    private(set) var setFrameCallCount = 0

    func focusedWindow() throws -> AXWindowHandle? {
        focused.map(WrapperFakeWindow.init(underlying:))
    }

    func windows() throws -> [AXWindowHandle] {
        allWindows.map(WrapperFakeWindow.init(underlying:))
    }

    func frame(of window: AXWindowHandle) throws -> CGRect {
        (window as! WrapperFakeWindow).underlying.frame
    }

    func setFrame(_ frame: CGRect, of window: AXWindowHandle) throws {
        setFrameCallCount += 1
        (window as! WrapperFakeWindow).underlying.frame = frame
    }

    func displays() -> [DisplayDescriptor] { displayList }
}

// MARK: - Fixtures

/// A display whose usableBounds equals its quartzBounds, so expected frames
/// are exact grid fractions (the menu-bar inset is exercised elsewhere).
private func makeActionDisplay(id: CGDirectDisplayID, bounds: CGRect) -> DisplayDescriptor {
    makeFakeDisplay(id: id, quartzBounds: bounds)
}

/// Fresh store in a unique temp directory — auto-assigns first-run defaults
/// (standard 5×2 active) to any identity on first access.
private func makeStore() throws -> GridProfileStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("quintile-actions-tests-\(UUID().uuidString)", isDirectory: true)
    return try GridProfileStore(directory: dir)
}

private func expectFrame(_ t: TestHarness, _ actual: CGRect, _ expected: CGRect,
                         accuracy: Double = 0.01,
                         file: StaticString = #filePath, line: UInt = #line) {
    t.expectNearlyEqual(actual.minX, expected.minX, accuracy: accuracy, file: file, line: line)
    t.expectNearlyEqual(actual.minY, expected.minY, accuracy: accuracy, file: file, line: line)
    t.expectNearlyEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
    t.expectNearlyEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
}

// MARK: - Tests

/// U7 test scenarios: preset tiling, footprint-translation move-within-grid,
/// and send-to-next-display.
func actionsTests(_ t: TestHarness) {
    // 1000×600 usable area: quadrants are 500×300, fifths are 200 wide,
    // thirds are 1000/3 wide, rows are 300 tall.
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let third = 1000.0 / 3.0

    /// Backend + controller + store with one display and one focused window.
    func makeWorld(windowFrame: CGRect = CGRect(x: 10, y: 10, width: 400, height: 350))
        throws -> (FakeAXBackend, AXWindowController, GridProfileStore, FakeWindow) {
        let backend = FakeAXBackend()
        let display = makeActionDisplay(id: 1, bounds: bounds)
        backend.displayList = [display]
        let window = FakeWindow(frame: windowFrame)
        backend.allWindows = [window]
        backend.focused = window
        let controller = AXWindowController(backend: backend)
        let store = try makeStore()
        return (backend, controller, store, window)
    }

    t.suite("TilingActions (presets)") { t in
        t.test("each quadrant is the exact screen quarter, independent of the 5×2 active profile") {
            let (backend, controller, store, window) = try makeWorld()
            // Active profile is the 5×2 standard default — presets must ignore it.
            let display = backend.displayList[0]
            t.expectEqual(store.activeProfile(for: display.identity), GridProfile(name: "standard", rows: 2, cols: 5))

            let actions = TilingActions(windowController: controller)
            let expectations: [(PresetAction, CGRect)] = [
                (.quadrant1, CGRect(x: 0, y: 0, width: 500, height: 300)),
                (.quadrant2, CGRect(x: 500, y: 0, width: 500, height: 300)),
                (.quadrant3, CGRect(x: 0, y: 300, width: 500, height: 300)),
                (.quadrant4, CGRect(x: 500, y: 300, width: 500, height: 300)),
            ]
            for (preset, expected) in expectations {
                t.expectEqual(actions.perform(preset), .performed, "\(preset)")
                expectFrame(t, window.frame, expected)
            }
        }

        t.test("thirds are one-third width at full height") {
            let (_, controller, _, window) = try makeWorld()
            let actions = TilingActions(windowController: controller)
            let expectations: [(PresetAction, CGRect)] = [
                (.thirdLeft, CGRect(x: 0, y: 0, width: third, height: 600)),
                (.thirdCenter, CGRect(x: third, y: 0, width: third, height: 600)),
                (.thirdRight, CGRect(x: 2 * third, y: 0, width: third, height: 600)),
            ]
            for (preset, expected) in expectations {
                t.expectEqual(actions.perform(preset), .performed, "\(preset)")
                expectFrame(t, window.frame, expected)
            }
        }

        t.test("halves are full width at half height") {
            let (_, controller, _, window) = try makeWorld()
            let actions = TilingActions(windowController: controller)
            t.expectEqual(actions.perform(.halfTop), .performed)
            expectFrame(t, window.frame, CGRect(x: 0, y: 0, width: 1000, height: 300))
            t.expectEqual(actions.perform(.halfBottom), .performed)
            expectFrame(t, window.frame, CGRect(x: 0, y: 300, width: 1000, height: 300))
        }

        t.test("each sixth is the correct third × half region") {
            let (_, controller, _, window) = try makeWorld()
            let actions = TilingActions(windowController: controller)
            // Enumerated left/center/right × top/bottom (see PresetAction docs).
            let expectations: [(PresetAction, CGRect)] = [
                (.sixth1, CGRect(x: 0, y: 0, width: third, height: 300)),
                (.sixth2, CGRect(x: 0, y: 300, width: third, height: 300)),
                (.sixth3, CGRect(x: third, y: 0, width: third, height: 300)),
                (.sixth4, CGRect(x: third, y: 300, width: third, height: 300)),
                (.sixth5, CGRect(x: 2 * third, y: 0, width: third, height: 300)),
                (.sixth6, CGRect(x: 2 * third, y: 300, width: third, height: 300)),
            ]
            for (preset, expected) in expectations {
                t.expectEqual(actions.perform(preset), .performed, "\(preset)")
                expectFrame(t, window.frame, expected)
            }
        }
    }

    t.suite("MoveWithinGridAction (footprint translation)") { t in
        t.test("quadrant on a 5×2 profile then move-right keeps a multi-column span (marquee regression)") {
            let (_, controller, store, window) = try makeWorld()
            // Quadrant 1 = left half × top half: does NOT align to 5-column
            // boundaries. frameToNearestSpan must resolve it to a
            // proportionate multi-column span, never a single 20% cell.
            t.expectEqual(TilingActions(windowController: controller).perform(.quadrant1), .performed)
            expectFrame(t, window.frame, CGRect(x: 0, y: 0, width: 500, height: 300))

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: []))
            // 500 pt right edge rounds to boundary 3 of 5 → span cols 0..2,
            // translated one column right → cols 1..3 = x 200, width 600.
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 600, height: 300))
        }

        t.test("move-right with empty destination moves only the focused window") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 200, height: 300)) // cell (0,0) on 5×2
            let bystander = FakeWindow(frame: CGRect(x: 0, y: 300, width: 200, height: 300)) // (0,1)
            backend.allWindows.append(bystander)

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: []))
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 200, height: 300))
            expectFrame(t, bystander.frame, CGRect(x: 0, y: 300, width: 200, height: 300))
            t.expectEqual(backend.setFrameCallCount, 1)
        }

        t.test("move-right into an identical-span occupant swaps both frames exactly") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 200, height: 300)) // cell (0,0)
            let occupant = FakeWindow(frame: CGRect(x: 200, y: 0, width: 200, height: 300)) // cell (1,0)
            backend.allWindows.append(occupant)

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: []))
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 200, height: 300))
            expectFrame(t, occupant.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
            t.expectEqual(backend.setFrameCallCount, 2)
        }

        t.test("2×1 mover over a 1×1 occupant: occupant keeps its size, anchored in the vacated footprint") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 400, height: 300)) // span (0,0) 2×1
            // Destination = cols 1..2; occupant is the 1×1 at col 2.
            let occupant = FakeWindow(frame: CGRect(x: 400, y: 0, width: 200, height: 300))
            backend.allWindows.append(occupant)

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: []))
            // Mover: whole 2-wide footprint translated one column.
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 400, height: 300))
            // Occupant: own 1×1 size preserved, anchored at the vacated
            // span's start cell (0,0) — NOT resized to the mover's 2×1.
            expectFrame(t, occupant.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
        }

        t.test("multi-occupant destination: every occupant relocates into the vacated footprint") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 400, height: 600)) // span (0,0) 2×2 (full height)
            // Destination = cols 1..2 × rows 0..1; two 1×1 occupants in col 2.
            let occupantTop = FakeWindow(frame: CGRect(x: 400, y: 0, width: 200, height: 300)) // (2,0)
            let occupantBottom = FakeWindow(frame: CGRect(x: 400, y: 300, width: 200, height: 300)) // (2,1)
            backend.allWindows.append(contentsOf: [occupantTop, occupantBottom])

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: []))
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 400, height: 600))
            // Both occupants anchored at the vacated start cell, own sizes kept.
            expectFrame(t, occupantTop.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
            expectFrame(t, occupantBottom.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
            // Vacated footprint = cols 0..1: both occupants are inside it.
            t.expect(occupantTop.frame.maxX <= 400.01)
            t.expect(occupantBottom.frame.maxX <= 400.01)
        }

        t.test("distinct wrapper handles for the same window: mover is never its own occupant") {
            // Regression for isSame(as:) as a PROTOCOL REQUIREMENT: with the
            // live backend's wrapper-object shape, `===` between the
            // focusedWindow() and windows() handles is always false, so a
            // statically-dispatched isSame would treat the mover as an
            // occupant of its own destination and issue a spurious extra
            // write before the real move.
            let backend = WrapperFakeBackend()
            backend.displayList = [makeActionDisplay(id: 1, bounds: bounds)]
            // 2-wide span (cols 0..1) on 5×2: destination cols 1..2 overlaps
            // the mover's own current span — the self-occupant trap.
            let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            backend.allWindows = [window]
            backend.focused = window
            let controller = AXWindowController(backend: backend)
            let store = try makeStore()

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: []))
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 400, height: 300))
            t.expectEqual(backend.setFrameCallCount, 1,
                          "exactly one write: no occupant-relocation of the mover itself")
        }

        t.test("move-right at the rightmost column is .boundaryReached with ZERO writes") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 800, y: 0, width: 200, height: 300)) // cell (4,0) on 5×2

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .boundaryReached)
            expectFrame(t, window.frame, CGRect(x: 800, y: 0, width: 200, height: 300))
            t.expectEqual(backend.setFrameCallCount, 0)
        }
    }

    t.suite("Action no-focus & SendToDisplay") { t in
        t.test("all three actions report no-focused-window with zero writes when nothing is focused") {
            let backend = FakeAXBackend()
            backend.displayList = [makeActionDisplay(id: 1, bounds: bounds),
                                   makeActionDisplay(id: 2, bounds: bounds.offsetBy(dx: 1000, dy: 0))]
            let controller = AXWindowController(backend: backend)
            let store = try makeStore()

            t.expectEqual(TilingActions(windowController: controller).perform(.quadrant1), .noFocusedWindow)
            t.expectEqual(MoveWithinGridAction(windowController: controller, store: store).move(.right), .noFocusedWindow)
            t.expectEqual(SendToDisplayAction(windowController: controller, store: store).send(), .noFocusedWindow)
            t.expectEqual(backend.setFrameCallCount, 0)
        }

        t.test("send-to-display clamps the span into the destination's 3×2 grid on its usableBounds") {
            let backend = FakeAXBackend()
            let displayA = makeActionDisplay(id: 1, bounds: bounds) // 5×2 standard default
            let displayB = makeActionDisplay(id: 2, bounds: CGRect(x: 1000, y: 0, width: 900, height: 600))
            backend.displayList = [displayA, displayB]
            // Window at span (4,1) 1×1 on A's 5×2 grid.
            let window = FakeWindow(frame: CGRect(x: 800, y: 300, width: 200, height: 300))
            backend.allWindows = [window]
            backend.focused = window
            let controller = AXWindowController(backend: backend)
            let store = try makeStore()
            // Display B's active profile: 3×2.
            store.updateProfile(GridProfile(name: "standard", rows: 2, cols: 3),
                                slot: .standard, for: displayB.identity)

            let send = SendToDisplayAction(windowController: controller, store: store)
            t.expectEqual(send.send(), .performed)
            // (col 4, row 1) clamps to (col 2, row 1) on 3×2; B's cells are
            // 300×300 over usableBounds starting at x=1000.
            expectFrame(t, window.frame, CGRect(x: 1600, y: 300, width: 300, height: 300))
        }

        t.test("send-to-display with a single display is .onlyOneDisplay with zero writes") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 200, height: 300))

            let send = SendToDisplayAction(windowController: controller, store: store)
            t.expectEqual(send.send(), .onlyOneDisplay)
            expectFrame(t, window.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
            t.expectEqual(backend.setFrameCallCount, 0)
        }
    }

    // Partial-failure semantics of MoveWithinGridAction (documented on the
    // implementation): occupants are written first, the mover last; occupant
    // errors are collected — the move still counts as .moved — and only a
    // failed MOVER write makes the whole move .failed (with any occupants
    // already relocated staying where they landed).
    t.suite("Failed AX writes (.failed / occupantErrors)") { t in
        t.test("occupant write failure is collected in .moved(occupantErrors:) and the mover still lands") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 200, height: 300)) // cell (0,0) on 5×2
            let occupant = FakeWindow(frame: CGRect(x: 200, y: 0, width: 200, height: 300)) // cell (1,0)
            occupant.setFrameError = .cannotComplete // enumerates/reads fine, write fails
            backend.allWindows.append(occupant)

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .moved(occupantErrors: [.cannotComplete]))
            // Mover relocated despite the occupant failure…
            expectFrame(t, window.frame, CGRect(x: 200, y: 0, width: 200, height: 300))
            // …and the occupant stayed put (its write threw).
            expectFrame(t, occupant.frame, CGRect(x: 200, y: 0, width: 200, height: 300))
        }

        t.test("mover write failure after an occupant relocated is .failed — occupant stays relocated") {
            let (backend, controller, store, window) = try makeWorld(
                windowFrame: CGRect(x: 0, y: 0, width: 200, height: 300)) // cell (0,0) on 5×2
            window.setFrameError = .cannotComplete // mover reads fine, write fails
            let occupant = FakeWindow(frame: CGRect(x: 200, y: 0, width: 200, height: 300)) // cell (1,0)
            backend.allWindows.append(occupant)

            let move = MoveWithinGridAction(windowController: controller, store: store)
            t.expectEqual(move.move(.right), .failed(.cannotComplete))
            // Mover write failed, so the mover stayed where it was…
            expectFrame(t, window.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
            // …but the occupant had ALREADY relocated into the vacated
            // footprint — the implementation's documented partial-failure
            // contract (occupants first, mover last, writes not atomic).
            expectFrame(t, occupant.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
        }

        t.test("TilingActions.perform surfaces a failed focused-window write as .failed(error)") {
            let (_, controller, _, window) = try makeWorld()
            window.setFrameError = .cannotComplete
            t.expectEqual(TilingActions(windowController: controller).perform(.quadrant1),
                          .failed(.cannotComplete))
        }

        t.test("SendToDisplayAction.send surfaces a failed focused-window write as .failed(error)") {
            let backend = FakeAXBackend()
            backend.displayList = [makeActionDisplay(id: 1, bounds: bounds),
                                   makeActionDisplay(id: 2, bounds: bounds.offsetBy(dx: 1000, dy: 0))]
            let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
            window.setFrameError = .invalidWindow
            backend.allWindows = [window]
            backend.focused = window
            let controller = AXWindowController(backend: backend)
            let store = try makeStore()

            t.expectEqual(SendToDisplayAction(windowController: controller, store: store).send(),
                          .failed(.invalidWindow))
            expectFrame(t, window.frame, CGRect(x: 0, y: 0, width: 200, height: 300))
        }
    }
}
