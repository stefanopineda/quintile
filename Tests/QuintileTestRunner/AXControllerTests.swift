import ApplicationServices
import CoreGraphics
import QuintileCore

// MARK: - Tests
//
// Real AX cannot run here: the test runner is not Accessibility-trusted, by
// design. Everything below drives `AXWindowController` through the shared
// `FakeAXBackend` (see SharedFakes.swift); live-AX behavior is covered by
// the manual integration checklist documented in `LiveAXBackend.swift`.

/// Usable area stand-in: menu-bar-sized inset from the top (Quartz top-left
/// origin, so the inset raises minY and shrinks height).
private func makeDisplay(id: CGDirectDisplayID, quartzBounds: CGRect) -> DisplayDescriptor {
    makeFakeDisplay(id: id, quartzBounds: quartzBounds, menuBarInset: 25)
}

/// U2 test scenarios: typed AX errors and display partitioning, driven
/// through the backend seam.
func axControllerTests(_ t: TestHarness) {
    t.suite("AXWindowController") { t in
        t.test("setFrame on an accepting window reads back within tolerance") {
            let backend = FakeAXBackend()
            let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
            backend.allWindows = [window]
            let controller = AXWindowController(backend: backend)

            let target = CGRect(x: 120, y: 80, width: 900, height: 650)
            try controller.setFrame(target, of: window)
            let readBack = try controller.frame(of: window)
            t.expectNearlyEqual(readBack.minX, target.minX, accuracy: 1.5)
            t.expectNearlyEqual(readBack.minY, target.minY, accuracy: 1.5)
            t.expectNearlyEqual(readBack.width, target.width, accuracy: 1.5)
            t.expectNearlyEqual(readBack.height, target.height, accuracy: 1.5)
        }

        t.test("setFrame on a size-rejecting window surfaces .writeRejected, not a silent no-op") {
            let backend = FakeAXBackend()
            let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 400))
            window.ignoresSizeWrites = true
            let controller = AXWindowController(backend: backend)

            var thrown: AXWindowError?
            do {
                try controller.setFrame(CGRect(x: 10, y: 10, width: 900, height: 650), of: window)
            } catch let error as AXWindowError {
                thrown = error
            }
            t.expectEqual(thrown, .writeRejected(attribute: "size"))
            // Position write did land — only the size was rejected.
            t.expectNearlyEqual(window.frame.minX, 10)
            t.expectNearlyEqual(window.frame.width, 500)
        }

        t.test("focusedWindow is nil when nothing is focused — no crash") {
            let backend = FakeAXBackend()
            let controller = AXWindowController(backend: backend)
            t.expect(try controller.focusedWindow() == nil)
        }

        t.test("focusedWindow returns the focused handle when one exists") {
            let backend = FakeAXBackend()
            let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            backend.focused = window
            let controller = AXWindowController(backend: backend)
            t.expect(try controller.focusedWindow()?.isSame(as: window) == true)
        }

        // Side-by-side displays in Quartz top-left global space.
        let displayA = makeDisplay(id: 1, quartzBounds: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let displayB = makeDisplay(id: 2, quartzBounds: CGRect(x: 1000, y: 0, width: 1000, height: 1000))

        t.test("windows(onDisplay:) assigns a 60/40 straddler to the majority display") {
            let backend = FakeAXBackend()
            backend.displayList = [displayA, displayB]
            // 600 pt of width on A, 400 pt on B.
            let straddler = FakeWindow(frame: CGRect(x: 400, y: 100, width: 1000, height: 500))
            let onB = FakeWindow(frame: CGRect(x: 1200, y: 100, width: 400, height: 400))
            backend.allWindows = [straddler, onB]
            let controller = AXWindowController(backend: backend)

            let aWindows = try controller.windows(onDisplay: displayA)
            let bWindows = try controller.windows(onDisplay: displayB)
            t.expectEqual(aWindows.count, 1)
            t.expect(aWindows.first?.isSame(as: straddler) == true)
            t.expectEqual(bWindows.count, 1)
            t.expect(bWindows.first?.isSame(as: onB) == true)
        }

        t.test("a 50/50 straddler goes to the display containing its center") {
            let backend = FakeAXBackend()
            backend.displayList = [displayA, displayB]
            // Equal 500 pt shares on A and B; center x = 1000 sits exactly on
            // the shared edge, which Quartz min-edge-inclusive containment
            // assigns to B — deterministic, never ambiguous.
            let straddler = FakeWindow(frame: CGRect(x: 500, y: 100, width: 1000, height: 500))
            backend.allWindows = [straddler]
            let controller = AXWindowController(backend: backend)

            t.expectEqual(try controller.windows(onDisplay: displayA).count, 0)
            let bWindows = try controller.windows(onDisplay: displayB)
            t.expectEqual(bWindows.count, 1)
            t.expect(bWindows.first?.isSame(as: straddler) == true)
        }

        t.test("display(containing:) applies the majority-area rule") {
            let backend = FakeAXBackend()
            backend.displayList = [displayA, displayB]
            let window = FakeWindow(frame: CGRect(x: 400, y: 100, width: 1000, height: 500))
            backend.allWindows = [window]
            let controller = AXWindowController(backend: backend)

            t.expectEqual(try controller.display(containing: window)?.id, displayA.id)
        }

        t.test("display(containing:) is nil for a fully off-screen window") {
            let backend = FakeAXBackend()
            backend.displayList = [displayA, displayB]
            let window = FakeWindow(frame: CGRect(x: 5000, y: 5000, width: 300, height: 300))
            backend.allWindows = [window]
            let controller = AXWindowController(backend: backend)

            t.expect(try controller.display(containing: window) == nil)
        }

        t.test("backend cannotComplete surfaces as .cannotComplete — never swallowed") {
            let backend = FakeAXBackend()
            let window = FakeWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            window.accessError = .cannotComplete
            let controller = AXWindowController(backend: backend)

            var thrown: AXWindowError?
            do {
                _ = try controller.frame(of: window)
            } catch let error as AXWindowError {
                thrown = error
            }
            t.expectEqual(thrown, .cannotComplete)

            thrown = nil
            do {
                try controller.setFrame(CGRect(x: 1, y: 2, width: 3, height: 4), of: window)
            } catch let error as AXWindowError {
                thrown = error
            }
            t.expectEqual(thrown, .cannotComplete)
        }

        t.test("a window with an unreadable frame is skipped by enumeration, not fatal") {
            let backend = FakeAXBackend()
            backend.displayList = [displayA]
            let healthy = FakeWindow(frame: CGRect(x: 100, y: 100, width: 400, height: 300))
            let hung = FakeWindow(frame: CGRect(x: 200, y: 200, width: 400, height: 300))
            hung.accessError = .cannotComplete
            backend.allWindows = [healthy, hung]
            let controller = AXWindowController(backend: backend)

            let windows = try controller.windows(onDisplay: displayA)
            t.expectEqual(windows.count, 1)
            t.expect(windows.first?.isSame(as: healthy) == true)
        }
    }

    // Pure AXError → AXWindowError mapping: needs no AX trust, so the live
    // backend's error surface is at least unit-covered here.
    t.suite("LiveAXBackend.mapAXError") { t in
        t.test(".success maps to nil (no error)") {
            t.expect(LiveAXBackend.mapAXError(.success) == nil)
        }

        t.test("each specific AXError code maps to its typed AXWindowError") {
            let expectations: [(AXError, AXWindowError)] = [
                (.cannotComplete, .cannotComplete),
                (.apiDisabled, .notPermitted),
                (.invalidUIElement, .invalidWindow),
                (.attributeUnsupported, .attributeUnsupported),
                (.parameterizedAttributeUnsupported, .attributeUnsupported),
                (.actionUnsupported, .attributeUnsupported),
                (.notificationUnsupported, .attributeUnsupported),
                (.notImplemented, .attributeUnsupported),
            ]
            for (axError, expected) in expectations {
                t.expectEqual(LiveAXBackend.mapAXError(axError), expected,
                              "AXError(\(axError.rawValue))")
            }
        }

        t.test("unlisted codes are preserved as .unexpected(code:)") {
            for axError: AXError in [.failure, .illegalArgument, .invalidUIElementObserver,
                                     .notificationAlreadyRegistered, .noValue] {
                t.expectEqual(LiveAXBackend.mapAXError(axError),
                              .unexpected(code: axError.rawValue),
                              "AXError(\(axError.rawValue))")
            }
        }
    }
}
