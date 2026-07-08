import CoreGraphics
import Foundation
import QuintileCore

/// Fake event tap: tests inject `KeyEvent`s and observe consume/passThrough
/// decisions, and count tap creations/enables to verify the permission-gated
/// lifecycle without a real `CGEventTap`.
private final class FakeEventTap: EventTapProviding {
    private(set) var createCount = 0
    private(set) var enableCount = 0
    private(set) var disableCount = 0
    private var handler: ((KeyEvent) -> EventDisposition)?
    private var enabled = false

    var isActive: Bool { handler != nil && enabled }

    func createTap(handler: @escaping (KeyEvent) -> EventDisposition) throws {
        createCount += 1
        self.handler = handler
    }

    func enable() {
        guard handler != nil else { return }
        enabled = true
        enableCount += 1
    }

    func disable() {
        enabled = false
        disableCount += 1
    }

    /// Simulates the OS disabling the tap (kCGEventTapDisabledByTimeout)
    /// without going through the public seam.
    func simulateOSDisable() { enabled = false }

    /// Delivers an event as the OS would: only an existing, enabled tap sees
    /// it; otherwise the event passes through untouched.
    @discardableResult
    func inject(_ event: KeyEvent) -> EventDisposition {
        guard let handler, enabled else { return .passThrough }
        return handler(event)
    }
}

private func down(_ keyCode: CGKeyCode, _ modifiers: KeyModifiers) -> KeyEvent {
    KeyEvent(keyCode: keyCode, modifiers: modifiers, isKeyDown: true)
}

/// U5 test scenarios: hotkey dispatch + tap lifecycle over the fake tap.
func hotkeyTests(_ t: TestHarness) {
    let leader: KeyModifiers = [.control, .option]

    t.suite("HotkeyManager dispatch") { t in
        t.test("registered leader+arrow binding fires exactly once and is consumed") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            try manager.activate()
            var fires = 0
            manager.register(HotkeyBinding(keyCode: KeyCode.leftArrow, modifiers: leader),
                             id: "move.left") { fires += 1 }

            let disposition = tap.inject(down(KeyCode.leftArrow, leader))
            t.expect(disposition == .consume, "matching key-down must be consumed")
            t.expectEqual(fires, 1, "action runs exactly once per event")
        }

        t.test("two different bindings do not cross-fire") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            try manager.activate()
            var leftFires = 0
            var gridFires = 0
            manager.register(HotkeyBinding(keyCode: KeyCode.leftArrow, modifiers: leader),
                             id: "move.left") { leftFires += 1 }
            manager.register(HotkeyBinding(keyCode: KeyCode.ansiG, modifiers: leader),
                             id: "grid.select") { gridFires += 1 }

            tap.inject(down(KeyCode.leftArrow, leader))
            t.expectEqual(leftFires, 1)
            t.expectEqual(gridFires, 0, "grid.select must not fire for move.left's chord")

            tap.inject(down(KeyCode.ansiG, leader))
            t.expectEqual(leftFires, 1, "move.left must not fire for grid.select's chord")
            t.expectEqual(gridFires, 1)
        }

        t.test("unregister stops triggering: passThrough, no action") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            try manager.activate()
            var fires = 0
            manager.register(HotkeyBinding(keyCode: KeyCode.ansiP, modifiers: leader),
                             id: "profile.cycle") { fires += 1 }
            tap.inject(down(KeyCode.ansiP, leader))
            t.expectEqual(fires, 1)

            manager.unregister(id: "profile.cycle")
            let disposition = tap.inject(down(KeyCode.ansiP, leader))
            t.expect(disposition == .passThrough, "unregistered chord must pass through")
            t.expectEqual(fires, 1, "no action after unregister")
            t.expect(manager.bindings["profile.cycle"] == nil, "bindings listing drops it")
        }

        t.test("non-matching modifiers pass through untouched") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            try manager.activate()
            var fires = 0
            manager.register(HotkeyBinding(keyCode: KeyCode.leftArrow, modifiers: leader),
                             id: "move.left") { fires += 1 }

            // Subset, superset, disjoint chords, and key-up: all pass through.
            let nonMatching: [KeyEvent] = [
                down(KeyCode.leftArrow, [.control]),                    // subset
                down(KeyCode.leftArrow, [.control, .option, .shift]),   // superset
                down(KeyCode.leftArrow, [.command]),                    // disjoint
                down(KeyCode.rightArrow, leader),                       // other key
                KeyEvent(keyCode: KeyCode.leftArrow, modifiers: leader, isKeyDown: false),
            ]
            for event in nonMatching {
                t.expect(tap.inject(event) == .passThrough,
                         "\(event) must pass through")
            }
            t.expectEqual(fires, 0, "no action for any non-matching event")
        }
    }

    t.suite("HotkeyManager tap lifecycle") { t in
        t.test("no tap before permission granted; activate() creates and enables") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            var fires = 0
            manager.register(HotkeyBinding(keyCode: KeyCode.ansiN, modifiers: leader),
                             id: "display.next") { fires += 1 }

            t.expectEqual(tap.createCount, 0, "no tap creation at init/register time")
            t.expect(!manager.isActive)
            tap.inject(down(KeyCode.ansiN, leader))
            t.expectEqual(fires, 0, "events before activation reach no action")

            // Simulates AccessibilityPermissionManager.onGrantedTransition.
            try manager.activate()
            t.expectEqual(tap.createCount, 1)
            t.expect(manager.isActive, "activate() creates AND enables the tap")
            tap.inject(down(KeyCode.ansiN, leader))
            t.expectEqual(fires, 1, "hotkeys live immediately after the grant, no relaunch")
        }

        t.test("second activate() is a no-op creation-wise") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            try manager.activate()
            try manager.activate() // e.g. revoke → re-grant transition
            t.expectEqual(tap.createCount, 1, "tap is created exactly once")
            t.expect(manager.isActive)
        }

        t.test("handleTapDisabledByTimeout re-enables a disabled tap") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            var fires = 0
            manager.register(HotkeyBinding(keyCode: KeyCode.ansiG, modifiers: leader),
                             id: "grid.select") { fires += 1 }
            try manager.activate()

            tap.simulateOSDisable() // kCGEventTapDisabledByTimeout
            t.expect(!manager.isActive)
            tap.inject(down(KeyCode.ansiG, leader))
            t.expectEqual(fires, 0, "disabled tap sees nothing")

            manager.handleTapDisabledByTimeout()
            t.expect(manager.isActive, "timeout recovery re-enables")
            tap.inject(down(KeyCode.ansiG, leader))
            t.expectEqual(fires, 1)
        }

        t.test("handleTapDisabledByTimeout before activation stays inert") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            manager.handleTapDisabledByTimeout()
            t.expectEqual(tap.createCount, 0)
            t.expect(!manager.isActive, "must not enable a tap that was never created")
        }
    }

    t.suite("SystemShortcutBridge (Fn+Ctrl+Arrow spike, logic level)") { t in
        t.test("takeover consumes Fn+Ctrl+Arrow and reports the direction") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            let bridge = SystemShortcutBridge(hotkeys: manager)
            try manager.activate()
            var directions: [SystemShortcutBridge.Direction] = []
            bridge.enableTakeover { directions.append($0) }
            t.expect(bridge.isTakeoverEnabled)

            let disposition = tap.inject(down(KeyCode.leftArrow, [.fn, .control]))
            t.expect(disposition == .consume,
                     "matching OS chord is consumed (real-world reliability: manual checklist)")
            t.expectEqual(directions, [.left])

            tap.inject(down(KeyCode.downArrow, [.fn, .control]))
            t.expectEqual(directions, [.left, .down])
        }

        t.test("without physical fn the chord passes through (fn-tracking contract)") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            let bridge = SystemShortcutBridge(hotkeys: manager)
            try manager.activate()
            var fires = 0
            bridge.enableTakeover { _ in fires += 1 }

            t.expect(tap.inject(down(KeyCode.leftArrow, [.control])) == .passThrough,
                     "Ctrl+Left without fn is not the OS tiling chord")
            t.expectEqual(fires, 0)
        }

        t.test("disableTakeover releases the chord") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            let bridge = SystemShortcutBridge(hotkeys: manager)
            try manager.activate()
            var fires = 0
            bridge.enableTakeover { _ in fires += 1 }
            bridge.disableTakeover()
            t.expect(!bridge.isTakeoverEnabled)

            t.expect(tap.inject(down(KeyCode.rightArrow, [.fn, .control])) == .passThrough)
            t.expectEqual(fires, 0)
        }
    }

    t.suite("Default bindings & descriptions") { t in
        t.test("default scheme covers all 20 actions with no duplicate chords") {
            let bindings = HotkeyBinding.defaultBindings
            t.expectEqual(bindings.count, 20)
            let expectedIDs = ["move.left", "move.right", "move.up", "move.down",
                               "grid.select",
                               "quadrant.1", "quadrant.2", "quadrant.3", "quadrant.4",
                               "third.left", "third.center", "third.right",
                               "profile.cycle", "display.next",
                               "sixth.1", "sixth.2", "sixth.3", "sixth.4", "sixth.5", "sixth.6"]
            for id in expectedIDs {
                t.expect(bindings[id] != nil, "missing default binding for \(id)")
            }
            let uniqueChords = Set(bindings.values)
            t.expectEqual(uniqueChords.count, bindings.count,
                          "two actions must never share a chord")
            // The takeover chords must not collide with the defaults either.
            for direction in SystemShortcutBridge.Direction.allCases {
                t.expect(!uniqueChords.contains(SystemShortcutBridge.binding(for: direction)),
                         "takeover chord \(direction) collides with a default binding")
            }
        }

        t.test("all defaults fire and consume when registered wholesale") {
            let tap = FakeEventTap()
            let manager = HotkeyManager(tap: tap)
            try manager.activate()
            var fired: Set<String> = []
            for (id, binding) in HotkeyBinding.defaultBindings {
                manager.register(binding, id: id) { fired.insert(id) }
            }
            for (id, binding) in HotkeyBinding.defaultBindings {
                let disposition = tap.inject(down(binding.keyCode, binding.modifiers))
                t.expect(disposition == .consume, "\(id) not consumed")
            }
            t.expectEqual(fired.count, HotkeyBinding.defaultBindings.count,
                          "every default binding fires its own action")
        }

        t.test("binding descriptions are human-readable for the shortcuts panel") {
            t.expectEqual(HotkeyBinding.defaultBindings["move.left"]!.description, "⌃⌥←")
            t.expectEqual(HotkeyBinding.defaultBindings["third.right"]!.description, "⌃⌥\\")
            t.expectEqual(HotkeyBinding.defaultBindings["sixth.5"]!.description, "⌃⌥⇧5")
            t.expectEqual(SystemShortcutBridge.binding(for: .up).description, "fn⌃↑")
        }
    }
}
