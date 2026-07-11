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
/// Denial grace is **wall-clock ~30s** after the launch prompt path completes,
/// not a fixed poll count — so faster polling while onboarding is visible
/// cannot reintroduce the v0.1.4 false-decline bug.
public final class AccessibilityPermissionManager {

    public private(set) var state: PermissionState = .notDetermined

    /// Deep link to System Settings → Privacy & Security → Accessibility.
    public static var accessibilitySettingsDeepLink: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    }

    /// Wall-clock grace after the launch prompt path before concluding `.denied`.
    /// Enough time to open System Settings, find Accessibility, and toggle.
    public static let deniedGraceDuration: TimeInterval = 30

    /// Legacy name kept for tests that expressed grace as N consecutive refreshes
    /// at the historical 3s poll (~30s). Prefer `deniedGraceDuration` for new code.
    public static let deniedGraceChecks = 10

    private let trustChecker: AccessibilityTrustChecking
    private let now: () -> Date
    private var hasPromptedThisLaunch = false
    /// Set when the first post-prompt untrusted check runs (or the prompt check
    /// itself completes untrusted). Grace countdown starts here.
    private var graceDeadline: Date?
    private var grantedHandlers: [() -> Void] = []

    public init(
        trustChecker: AccessibilityTrustChecking = SystemAccessibilityTrustChecker(),
        now: @escaping () -> Date = Date.init
    ) {
        self.trustChecker = trustChecker
        self.now = now
    }

    /// Registers a handler fired exactly once per not-granted → `granted`
    /// transition. Re-granting after a revocation fires handlers again;
    /// repeated checks while already granted do not.
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
            graceDeadline = nil
            for handler in grantedHandlers { handler() }
            return
        }

        switch state {
        case .granted:
            state = .revoked
        case .notDetermined where hasPromptedThisLaunch:
            // Start wall-clock grace on the first untrusted observation after
            // the prompt path (the prompt check itself usually returns false
            // before the user can act).
            if graceDeadline == nil {
                graceDeadline = now().addingTimeInterval(Self.deniedGraceDuration)
            }
            if let deadline = graceDeadline, now() >= deadline {
                state = .denied
            }
        case .notDetermined, .denied, .revoked:
            break
        }
    }
}
