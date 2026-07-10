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

        t.test("one follow-up refresh after the prompt stays notDetermined (grace window, not an instant denial)") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)

            manager.checkOnLaunch() // prompting check itself is not a denial signal
            t.expectEqual(manager.state, .notDetermined)

            manager.refresh() // still untrusted right after the prompt — user hasn't had time to act
            t.expectEqual(manager.state, .notDetermined, "a single follow-up check must not read as a decline")
            t.expectEqual(fake.promptCallCount, 1, "grace-window checks never re-prompt")
        }

        t.test("denied only once the grace window of consecutive untrusted refreshes is exhausted") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)

            manager.checkOnLaunch()
            for _ in 0..<(AccessibilityPermissionManager.deniedGraceChecks - 1) {
                manager.refresh()
                t.expectEqual(manager.state, .notDetermined, "still inside the grace window")
            }
            manager.refresh() // grace window exhausted with no grant → definitive denial
            t.expectEqual(manager.state, .denied)
            t.expectEqual(fake.promptCallCount, 1, "denial detection never re-prompts")
        }

        t.test("granting inside the grace window still transitions cleanly to granted") {
            let fake = FakeTrustChecker()
            let manager = AccessibilityPermissionManager(trustChecker: fake)
            var grantedFires = 0
            manager.onGrantedTransition { grantedFires += 1 }

            manager.checkOnLaunch()
            manager.refresh() // one untrusted follow-up, still inside the grace window

            fake.trusted = true // user finishes granting in System Settings
            manager.refresh()
            t.expectEqual(manager.state, .granted)
            t.expectEqual(grantedFires, 1)
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
