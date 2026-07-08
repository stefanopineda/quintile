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
///   prompt was shown this launch (`checkOnLaunch()`) and a *later* `refresh()`
///   still reports untrusted. Prompt dismissal has no callback, so
///   still-not-granted-after-prompt is modeled as denial.
/// - `granted` → `revoked` when a check comes back untrusted after a grant.
/// - `denied`/`revoked` → `granted` when the user (re-)grants via the
///   System Settings deep link.
public final class AccessibilityPermissionManager {

    public private(set) var state: PermissionState = .notDetermined

    /// Deep link to System Settings → Privacy & Security → Accessibility.
    public static var accessibilitySettingsDeepLink: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    }

    private let trustChecker: AccessibilityTrustChecking
    private var hasPromptedThisLaunch = false
    /// True once the initial prompting check has returned, so the *next*
    /// untrusted result counts as a denial rather than "user still deciding".
    private var promptCheckCompleted = false
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
            for handler in grantedHandlers { handler() }
            return
        }

        switch state {
        case .granted:
            state = .revoked
        case .notDetermined where hasPromptedThisLaunch:
            // Only a check *after* the prompting one is a denial signal: the
            // prompting check itself always reports untrusted on a fresh
            // install because the user hasn't had a chance to respond yet.
            if promptCheckCompleted {
                state = .denied
            } else {
                promptCheckCompleted = true
            }
        case .notDetermined, .denied, .revoked:
            break // no transition
        }
    }
}
