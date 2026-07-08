import Foundation
import ServiceManagement

/// Seam over login-item registration (U8) so `LoginItemManager` is pure logic
/// and tests can verify the permission-gated flow without touching
/// `SMAppService` (which requires a bundled, signed .app to do anything real).
public protocol LoginItemRegistering {
    /// Whether the app is currently registered to launch at login.
    var isRegistered: Bool { get }
    func register() throws
    func unregister() throws
}

/// Real implementation over `SMAppService.mainApp`.
///
/// NOTE: `SMAppService.mainApp` only works from a bundled `.app` (it registers
/// the main application bundle as a login item). Invoked from a bare
/// executable — e.g. `swift run` during development — `register()` throws;
/// `LoginItemManager` reports and swallows that, so development runs are
/// unaffected.
public struct SMAppServiceLoginItem: LoginItemRegistering {
    public init() {}

    public var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

/// Registers Quintile as a login item — gated strictly on confirmed
/// Accessibility permission (U8, plan "Permission & login-item flow").
///
/// `registerAfterPermissionGranted()` is designed to be called ONLY from
/// `AccessibilityPermissionManager.onGrantedTransition` — never speculatively
/// at launch, never while `notDetermined`/`denied`/`revoked`. Constructing
/// this manager performs no registration whatsoever.
public final class LoginItemManager {

    private let service: LoginItemRegistering

    /// The most recent registration failure, if any. Registration is
    /// best-effort: a failure (unbundled dev build, MDM policy, …) is
    /// reported here and to stderr but never crashes or alerts — login-item
    /// enrollment is a convenience, not a requirement for tiling to work.
    public private(set) var lastError: Error?

    public init(service: LoginItemRegistering) {
        self.service = service
    }

    /// Idempotent registration hook for the granted transition. No-op when
    /// already registered, so re-grant after a revocation (the granted
    /// handler fires again) never double-registers.
    public func registerAfterPermissionGranted() {
        guard !service.isRegistered else { return }
        do {
            try service.register()
            lastError = nil
        } catch {
            lastError = error
            FileHandle.standardError.write(
                Data("Quintile: login-item registration failed: \(error)\n".utf8))
        }
    }
}
