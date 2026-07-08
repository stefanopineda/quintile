import Foundation
import QuintileCore

/// Fake trust checker: tests flip `trusted` to simulate the user granting or
/// revoking permission in System Settings, and count prompting calls.
private final class FakeTrustChecker: AccessibilityTrustChecking {
    var trusted = false
    private(set) var promptCallCount = 0
    private(set) var totalCallCount = 0

    func isProcessTrusted(promptUser: Bool) -> Bool {
        totalCallCount += 1
        if promptUser { promptCallCount += 1 }
        return trusted
    }
}

/// U1 test scenarios: permission state machine over a fake trust checker.
func permissionTests(_ t: TestHarness) {
    t.suite("AccessibilityPermissionManager") { t in
        t.test("fresh install starts notDetermined and prompts exactly once per cold launch") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            t.expectEqual(manager.state, .notDetermined)
            t.expectEqual(fake.promptCallCount, 0, "no prompt before checkOnLaunch")

            manager.checkOnLaunch()
            t.expectEqual(fake.promptCallCount, 1, "first checkOnLaunch prompts")

            manager.checkOnLaunch()
            manager.checkOnLaunch()
            manager.refresh()
            manager.refresh()
            t.expectEqual(fake.promptCallCount, 1, "subsequent checks never re-prompt")
            t.expect(fake.totalCallCount > 1, "subsequent checks still check, just without prompting")
        }

        t.test("notDetermined → granted on next refresh; granted handlers fire exactly once") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            var grantedFires = 0
            manager.onGrantedTransition { grantedFires += 1 }

            manager.checkOnLaunch()
            t.expectEqual(manager.state, .notDetermined)
            t.expectEqual(grantedFires, 0)

            fake.trusted = true // user grants in System Settings
            manager.refresh()
            t.expectEqual(manager.state, .granted)
            t.expectEqual(grantedFires, 1, "handler fires once on the grant transition")
        }

        t.test("prompt dismissal becomes denied once a later refresh still reports untrusted") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)

            manager.checkOnLaunch() // prompting check itself is not a denial signal
            t.expectEqual(manager.state, .notDetermined)

            manager.refresh() // still untrusted after the prompt → definitive denial
            t.expectEqual(manager.state, .denied)
            t.expectEqual(fake.promptCallCount, 1, "denial detection never re-prompts")
        }

        t.test("granted → revoked when trust is withdrawn, distinct from notDetermined") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            fake.trusted = true
            manager.checkOnLaunch()
            t.expectEqual(manager.state, .granted)

            fake.trusted = false // user revokes in System Settings while running
            manager.refresh()
            t.expectEqual(manager.state, .revoked)
            t.expect(manager.state != .notDetermined, "revoked must not read as a fresh install")

            manager.refresh()
            t.expectEqual(manager.state, .revoked, "revoked is stable across further checks")
        }

        t.test("re-grant after revoke returns to granted and fires handlers again") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            var grantedFires = 0
            manager.onGrantedTransition { grantedFires += 1 }

            fake.trusted = true
            manager.checkOnLaunch()
            t.expectEqual(grantedFires, 1)

            fake.trusted = false
            manager.refresh()
            t.expectEqual(manager.state, .revoked)
            t.expectEqual(grantedFires, 1, "revocation does not fire granted handlers")

            fake.trusted = true // user re-grants via the deep link
            manager.refresh()
            t.expectEqual(manager.state, .granted)
            t.expectEqual(grantedFires, 2, "re-grant fires handlers again")
        }

        t.test("repeated refresh while granted: no prompts, stable state, no handler re-fire") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            var grantedFires = 0
            manager.onGrantedTransition { grantedFires += 1 }

            fake.trusted = true
            manager.checkOnLaunch()
            let promptsAfterLaunch = fake.promptCallCount

            for _ in 0..<5 {
                manager.refresh()
                manager.checkOnLaunch()
            }
            t.expectEqual(manager.state, .granted)
            t.expectEqual(fake.promptCallCount, promptsAfterLaunch, "no prompt while granted")
            t.expectEqual(grantedFires, 1, "handlers do not re-fire while granted")
        }

        t.test("multiple handlers each fire per grant transition") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            var aFires = 0
            var bFires = 0
            manager.onGrantedTransition { aFires += 1 } // e.g. U8 LoginItemManager
            manager.onGrantedTransition { bFires += 1 } // e.g. U5 HotkeyManager

            fake.trusted = true
            manager.refresh()
            t.expectEqual(aFires, 1)
            t.expectEqual(bFires, 1)
        }

        t.test("System Settings deep link is the exact Privacy_Accessibility URL") {
            t.expectEqual(
                AccessibilityPermissionManager.accessibilitySettingsDeepLink.absoluteString,
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        }
    }
}
