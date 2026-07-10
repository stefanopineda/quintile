import Foundation
import ApplicationServices

/// Accessibility permission lifecycle state (U1).
///
/// `revoked` is deliberately distinct from `notDetermined`: it means permission
/// was granted at some point during this run and has since been withdrawn in
/// System Settings, so the UI can say "re-enable" rather than "enable".
public enum PermissionState: Equatable {
    case notDetermined
    case granted
    case denied
    case revoked
}

/// Seam over the AX trust check so `AccessibilityPermissionManager` stays pure
/// logic and tests can drive grant/deny/revoke without real permissions.
public protocol AccessibilityTrustChecking {
    /// Returns whether this process is trusted for Accessibility.
    /// `promptUser: true` asks macOS to show the system permission prompt if
    /// the process is not yet trusted.
    func isProcessTrusted(promptUser: Bool) -> Bool
}

/// Real implementation backed by `AXIsProcessTrustedWithOptions`.
public struct SystemAccessibilityTrustChecker: AccessibilityTrustChecking {
    public init() {}

    public func isProcessTrusted(promptUser: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptUser]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

/// Detects, requests, and monitors Accessibility permission.
///
/// Polling strategy: this manager owns no timer. macOS does not reliably
/// notify apps of AX grant changes, so the app layer owns a low-frequency
/// `Timer` (and a pre-hotkey-action check) that calls `refresh()`; tests drive
/// `refresh()` manually. This keeps the manager synchronous, deterministic,
/// and free of scheduler seams.
///
/// State machine (see the plan's "Permission & login-item flow" diagram):
/// - `notDetermined` → `granted` when a check comes back trusted.
/// - `notDetermined` → `denied` only after a definitive denial signal: the OS
///   prompt was shown this launch (`checkOnLaunch()`) and `deniedGraceChecks`
///   *consecutive later* `refresh()` calls still report untrusted. Prompt
///   dismissal has no callback and `AXIsProcessTrustedWithOptions` returns
///   immediately without waiting for the user, so a single follow-up check is
///   not a denial signal — it fires long before a human can plausibly have
///   opened System Settings, found Accessibility, and toggled the app. The
///   grace window absorbs that navigation time before concluding "declined".
/// - `granted` → `revoked` when a check comes back untrusted after a grant.
/// - `denied`/`revoked` → `granted` when the user (re-)grants via the
///   System Settings deep link.
public final class AccessibilityPermissionManager {

    public private(set) var state: PermissionState = .notDetermined

    /// Deep link to System Settings → Privacy & Security → Accessibility.
    public static var accessibilitySettingsDeepLink: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    }

    /// Consecutive untrusted `refresh()` calls required after the launch
    /// prompt before concluding the user actually declined, rather than
    /// simply not having gotten to System Settings yet. The app layer polls
    /// on a 3s cadence (`AppCoordinator`'s `permissionTimer`), so this is
    /// roughly a 30s grace window — enough to open System Settings and
    /// toggle the app, short enough to still surface a genuine decline.
    public static let deniedGraceChecks = 10

    private let trustChecker: AccessibilityTrustChecking
    private var hasPromptedThisLaunch = false
    /// True once the initial prompting check has returned, so subsequent
    /// untrusted results start counting toward the denial grace window.
    private var promptCheckCompleted = false
    /// Consecutive untrusted checks since `promptCheckCompleted` became true.
    private var untrustedChecksAfterPrompt = 0
    private var grantedHandlers: [() -> Void] = []

    public init(trustChecker: AccessibilityTrustChecking = SystemAccessibilityTrustChecker()) {
        self.trustChecker = trustChecker
    }

    /// Registers a handler fired exactly once per not-granted → `granted`
    /// transition. Re-granting after a revocation fires handlers again;
    /// repeated checks while already granted do not.
    ///
    /// This is the hook U8's LoginItemManager registration and U5's
    /// HotkeyManager event-tap creation attach to.
    public func onGrantedTransition(_ handler: @escaping () -> Void) {
        grantedHandlers.append(handler)
    }

    /// Launch-time check. Triggers the OS permission prompt at most once per
    /// cold launch (only while not yet granted); every subsequent call — and
    /// every `refresh()` — checks without prompting.
    public func checkOnLaunch() {
        if state != .granted && !hasPromptedThisLaunch {
            hasPromptedThisLaunch = true
            apply(trusted: trustChecker.isProcessTrusted(promptUser: true))
        } else {
            refresh()
        }
    }

    /// Non-prompting re-check, safe to call from a polling timer and before
    /// each hotkey-triggered action.
    public func refresh() {
        apply(trusted: trustChecker.isProcessTrusted(promptUser: false))
    }

    private func apply(trusted: Bool) {
        if trusted {
            guard state != .granted else { return }
            state = .granted
            untrustedChecksAfterPrompt = 0
            for handler in grantedHandlers { handler() }
            return
        }

        switch state {
        case .granted:
            state = .revoked
        case .notDetermined where hasPromptedThisLaunch:
            // The prompting check itself always reports untrusted on a fresh
            // install because the user hasn't had a chance to respond yet.
            // Checks after that only count as a denial once the grace window
            // of consecutive untrusted checks is exhausted, giving the user
            // time to actually navigate to System Settings and grant it.
            if promptCheckCompleted {
                untrustedChecksAfterPrompt += 1
                if untrustedChecksAfterPrompt >= Self.deniedGraceChecks {
                    state = .denied
                }
            } else {
                promptCheckCompleted = true
            }
        case .notDetermined, .denied, .revoked:
            break // no transition
        }
    }
}
