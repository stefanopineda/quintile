import CoreGraphics
import Foundation
import QuintileCore

// MARK: - Fakes

private final class FakeTrustChecker: AccessibilityTrustChecking {
    var trusted = false
    func isProcessTrusted(promptUser: Bool) -> Bool { trusted }
}

private final class FakeLoginItemService: LoginItemRegistering {
    private(set) var registered = false
    private(set) var registerCalls = 0
    var errorToThrow: Error?

    var isRegistered: Bool { registered }

    func register() throws {
        registerCalls += 1
        if let errorToThrow { throw errorToThrow }
        registered = true
    }

    func unregister() throws { registered = false }
}

private struct StubError: Error {}

private final class FakeEventTap: EventTapProviding {
    private var handler: ((KeyEvent) -> EventDisposition)?
    private var enabled = false

    var isActive: Bool { handler != nil && enabled }

    func createTap(handler: @escaping (KeyEvent) -> EventDisposition) throws {
        self.handler = handler
    }

    func enable() {
        guard handler != nil else { return }
        enabled = true
    }

    func disable() { enabled = false }

    func destroyTap() {
        handler = nil
        enabled = false
    }

    @discardableResult
    func inject(_ event: KeyEvent) -> EventDisposition {
        guard let handler, enabled else { return .passThrough }
        return handler(event)
    }
}

/// Manager with a SYNCHRONOUS action executor: production defers action
/// bodies to the main queue, but these tests assert on side effects
/// immediately after inject.
private func makeManager(tap: FakeEventTap) -> HotkeyManager {
    let manager = HotkeyManager(tap: tap)
    manager.actionExecutor = { $0() }
    return manager
}

/// Counting backend: proves the profile-cycle path performs zero window
/// writes. It mirrors the app wiring (an AXWindowController exists over it)
/// while `ProfileCycler` — by construction — never receives either.
private final class CountingAXBackend: AXBackend {
    private(set) var setFrameCount = 0

    func focusedWindow() throws -> AXWindowHandle? { nil }
    func windows() throws -> [AXWindowHandle] { [] }
    func frame(of window: AXWindowHandle) throws -> CGRect { .zero }
    func setFrame(_ frame: CGRect, of window: AXWindowHandle) throws { setFrameCount += 1 }
    func displays() -> [DisplayDescriptor] { [] }
}

// MARK: - Helpers

private func makeTempStore() throws -> GridProfileStore {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("quintile-u8-tests-\(UUID().uuidString)", isDirectory: true)
    return try GridProfileStore(directory: dir)
}

private func identity(serial: UInt32) -> DisplayIdentity {
    DisplayIdentity(info: DisplayInfo(
        vendorNumber: 1, modelNumber: 2, serialNumber: serial,
        localizedName: "Fake Display \(serial)",
        pixelSize: CGSize(width: 3840, height: 2160)))
}

// MARK: - U8 app-integration scenarios (pure logic — no AppKit windows)

func appIntegrationTests(_ t: TestHarness) {

    t.suite("LoginItemManager permission gating") { t in
        t.test("never registers speculatively: not while notDetermined or denied") {
            let checker = FakeTrustChecker()
            var now = Date(timeIntervalSince1970: 2_000_000)
            let permissions = AccessibilityPermissionManager(
                trustChecker: checker, now: { now })
            let service = FakeLoginItemService()
            let manager = LoginItemManager(service: service)
            // The one sanctioned wiring point (see LoginItemManager docs).
            permissions.onGrantedTransition { manager.registerAfterPermissionGranted() }

            t.expectEqual(service.registerCalls, 0, "construction must register nothing")

            permissions.checkOnLaunch() // prompt shown, untrusted → notDetermined
            t.expectEqual(permissions.state, .notDetermined)
            t.expectEqual(service.registerCalls, 0, "no registration while notDetermined")

            permissions.refresh() // starts wall-clock grace
            now = now.addingTimeInterval(AccessibilityPermissionManager.deniedGraceDuration)
            permissions.refresh() // grace exhausted → denied
            t.expectEqual(permissions.state, .denied)
            t.expectEqual(service.registerCalls, 0, "no registration while denied")
        }

        t.test("granted transition registers exactly once; repeat checks don't re-register") {
            let checker = FakeTrustChecker()
            let permissions = AccessibilityPermissionManager(trustChecker: checker)
            let service = FakeLoginItemService()
            let manager = LoginItemManager(service: service)
            permissions.onGrantedTransition { manager.registerAfterPermissionGranted() }

            permissions.checkOnLaunch()
            checker.trusted = true
            permissions.refresh()
            t.expectEqual(permissions.state, .granted)
            t.expectEqual(service.registerCalls, 1, "grant transition registers once")

            permissions.refresh() // still granted: no new transition
            t.expectEqual(service.registerCalls, 1)
        }

        t.test("re-grant after revoke does not double-register (isRegistered guard)") {
            let checker = FakeTrustChecker()
            let permissions = AccessibilityPermissionManager(trustChecker: checker)
            let service = FakeLoginItemService()
            let manager = LoginItemManager(service: service)
            permissions.onGrantedTransition { manager.registerAfterPermissionGranted() }

            checker.trusted = true
            permissions.checkOnLaunch() // → granted, registers
            checker.trusted = false
            permissions.refresh() // → revoked
            checker.trusted = true
            permissions.refresh() // → granted again: handler fires again…
            t.expectEqual(permissions.state, .granted)
            t.expectEqual(service.registerCalls, 1,
                          "…but the already-registered guard prevents a second register()")
            t.expect(service.isRegistered)
        }

        t.test("register() throwing is reported, never crashes") {
            let service = FakeLoginItemService()
            service.errorToThrow = StubError()
            let manager = LoginItemManager(service: service)

            manager.registerAfterPermissionGranted() // must not crash
            t.expectEqual(service.registerCalls, 1)
            t.expect(!service.isRegistered, "failed registration leaves it unregistered")
            t.expect(manager.lastError != nil, "failure surfaced on lastError")
        }

        t.test("unregisterIfNeeded is a no-op when not registered") {
            let service = FakeLoginItemService()
            let manager = LoginItemManager(service: service)
            manager.unregisterIfNeeded()
            t.expect(!service.isRegistered)
            t.expect(manager.lastError == nil)
        }

        t.test("unregisterIfNeeded clears a registered login item") {
            let service = FakeLoginItemService()
            let manager = LoginItemManager(service: service)
            manager.registerAfterPermissionGranted()
            t.expect(service.isRegistered)
            manager.unregisterIfNeeded()
            t.expect(!service.isRegistered)
            t.expect(manager.lastError == nil)
        }
    }

    t.suite("UninstallScript clean uninstall") { t in
        t.test("shell source runs brew cask uninstall and tccutil reset") {
            let source = UninstallScript.shellSource()
            t.expect(source.contains("brew uninstall --cask --force --zap"),
                     "must force-uninstall + zap so orphan receipts cannot block reinstall")
            t.expect(source.contains(UninstallScript.caskName),
                     "must target the quintile cask")
            t.expect(source.contains("tccutil reset Accessibility"),
                     "must reset Accessibility")
            t.expect(source.contains(UninstallScript.bundleIdentifier),
                     "must reset the Quintile bundle id")
            t.expect(source.contains("/Applications/Quintile.app"),
                     "must remove leftover app bundle")
            t.expect(source.contains("pgrep -x"),
                     "must wait for process exit before deleting")
            t.expect(!source.contains("Application Support"),
                     "must not delete user profiles")
        }

        t.test("writeTemporaryScript produces an executable shell file") {
            let url = try UninstallScript.writeTemporaryScript()
            defer { try? FileManager.default.removeItem(at: url) }
            t.expect(FileManager.default.fileExists(atPath: url.path))
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let perms = attrs[.posixPermissions] as? NSNumber
            t.expect(perms != nil, "posix permissions set")
            // Owner-executable bit (0o100).
            t.expect((perms!.intValue & 0o100) != 0, "script must be executable")
            let body = try String(contentsOf: url, encoding: .utf8)
            t.expect(body.hasPrefix("#!/bin/bash"))
            t.expect(body.contains("tccutil reset Accessibility"))
        }
    }

    t.suite("HotkeyManager modal interceptor") { t in
        let leader: KeyModifiers = [.control, .option]
        let bound = HotkeyBinding(keyCode: KeyCode.leftArrow, modifiers: leader)

        t.test("interceptor runs BEFORE binding dispatch: bound chord consumed, action silent") {
            let tap = FakeEventTap()
            let manager = makeManager(tap: tap)
            try manager.activate()
            var fires = 0
            manager.register(bound, id: "move.left") { fires += 1 }

            var intercepted: [KeyEvent] = []
            manager.modalInterceptor = { event in
                intercepted.append(event)
                return .consume
            }

            let disposition = tap.inject(down(KeyCode.leftArrow, leader))
            t.expect(disposition == .consume, "interceptor consume wins")
            t.expectEqual(fires, 0, "bound action must NOT fire while intercepted")
            t.expectEqual(intercepted.count, 1)
        }

        t.test("interceptor sees key-ups too (modal sessions swallow full keystrokes)") {
            let tap = FakeEventTap()
            let manager = makeManager(tap: tap)
            try manager.activate()
            var sawKeyUp = false
            manager.modalInterceptor = { event in
                if !event.isKeyDown { sawKeyUp = true }
                return .consume
            }
            let keyUp = KeyEvent(keyCode: KeyCode.leftArrow, modifiers: leader, isKeyDown: false)
            t.expect(tap.inject(keyUp) == .consume)
            t.expect(sawKeyUp, "interceptor is offered events ahead of the key-down filter")
        }

        t.test("interceptor passThrough falls through to binding dispatch") {
            let tap = FakeEventTap()
            let manager = makeManager(tap: tap)
            try manager.activate()
            var fires = 0
            manager.register(bound, id: "move.left") { fires += 1 }
            manager.modalInterceptor = { _ in .passThrough }

            let disposition = tap.inject(down(KeyCode.leftArrow, leader))
            t.expect(disposition == .consume, "binding still consumes after fall-through")
            t.expectEqual(fires, 1, "unrelated (passed-through) keys reach bindings")
        }

        t.test("clearing the interceptor restores normal dispatch") {
            let tap = FakeEventTap()
            let manager = makeManager(tap: tap)
            try manager.activate()
            var fires = 0
            manager.register(bound, id: "move.left") { fires += 1 }

            manager.modalInterceptor = { _ in .consume }
            tap.inject(down(KeyCode.leftArrow, leader))
            t.expectEqual(fires, 0)

            manager.modalInterceptor = nil
            let disposition = tap.inject(down(KeyCode.leftArrow, leader))
            t.expect(disposition == .consume)
            t.expectEqual(fires, 1, "normal dispatch restored after session ends")
        }
    }

    t.suite("Profile cycling (U8 scenarios)") { t in
        t.test("cycling display A leaves display B's active slot untouched") {
            let store = try makeTempStore()
            let a = identity(serial: 100)
            let b = identity(serial: 200)
            store.config(for: a)
            store.config(for: b)

            let cycler = ProfileCycler(store: store)
            let result = cycler.cycle(for: a)

            t.expectEqual(result.slot, .secondary)
            t.expectEqual(store.config(for: a).activeSlot, .secondary)
            t.expectEqual(store.config(for: b).activeSlot, .standard,
                          "cycle is strictly per-display")
        }

        t.test("three cycles walk standard → secondary → tertiary → standard") {
            let store = try makeTempStore()
            let a = identity(serial: 300)
            let cycler = ProfileCycler(store: store)

            t.expectEqual(cycler.cycle(for: a).slot, .secondary)
            t.expectEqual(cycler.cycle(for: a).slot, .tertiary)
            t.expectEqual(cycler.cycle(for: a).slot, .standard)
            t.expectEqual(store.config(for: a).activeSlot, .standard)
        }

        t.test("cycle result carries the newly active profile for the indicator/flash") {
            let store = try makeTempStore()
            let a = identity(serial: 400)
            // Customize secondary so the result provably reads the store.
            store.updateProfile(GridProfile(name: "secondary", rows: 3, cols: 4),
                                slot: .secondary, for: a)

            let result = ProfileCycler(store: store).cycle(for: a)
            t.expectEqual(result.slot, .secondary)
            t.expectEqual(result.profile, GridProfile(name: "secondary", rows: 3, cols: 4))
        }
    }

    t.suite("Profile cycle never retiles") { t in
        t.test("full cycle round-trip performs zero backend writes") {
            let store = try makeTempStore()
            let backend = CountingAXBackend()
            _ = AXWindowController(backend: backend) // mirrors app wiring; unused by cycler
            let a = identity(serial: 500)
            let cycler = ProfileCycler(store: store)

            cycler.cycle(for: a)
            cycler.cycle(for: a)
            cycler.cycle(for: a) // back to standard

            t.expectEqual(backend.setFrameCount, 0,
                          "cycling is pointer-only: no setFrame ever (plan/test requirement)")
            t.expectEqual(store.config(for: a).activeSlot, .standard)
        }
    }
}
