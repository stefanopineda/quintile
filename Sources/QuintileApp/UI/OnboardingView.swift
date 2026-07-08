import AppKit
import QuintileCore

/// U8: programmatic AppKit onboarding window rendering U1's permission
/// states with distinct copy per state (plan requirement). Shown at launch
/// while not granted, reachable any time from the menu ("Grant
/// Accessibility…"). The coordinator pushes state changes via `update(state:)`
/// (it already owns the permission polling loop), so the copy flips live the
/// moment a grant/deny/revoke is detected.
final class OnboardingWindowController: NSObject {

    var onRequestPermission: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let window: NSWindow
    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private var state: PermissionState = .notDetermined

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable], // non-resizable by omission of .resizable
            backing: .buffered,
            defer: false)
        window.title = "Welcome to Quintile"
        window.isReleasedWhenClosed = false
        super.init()
        buildContent()
        render()
    }

    // MARK: - API

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Live state-driven copy; safe to call whether or not the window is
    /// visible.
    func update(state: PermissionState) {
        guard state != self.state else { return }
        self.state = state
        render()
    }

    // MARK: - Content

    private func buildContent() {
        iconLabel.font = NSFont.systemFont(ofSize: 44)
        iconLabel.alignment = .center

        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.alignment = .center

        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.alignment = .center
        bodyLabel.preferredMaxLayoutWidth = 380

        actionButton.target = self
        actionButton.action = #selector(primaryAction)
        actionButton.bezelStyle = .rounded
        actionButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [iconLabel, titleLabel, bodyLabel, actionButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 28, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 460),
        ])
        window.contentView = content
    }

    private func render() {
        switch state {
        case .notDetermined:
            iconLabel.stringValue = "⊞"
            titleLabel.stringValue = "Quintile needs Accessibility permission"
            bodyLabel.stringValue = """
            Quintile needs Accessibility permission to move and resize windows. \
            macOS will ask for your approval — Quintile never reads your screen \
            contents, it only positions windows.
            """
            actionButton.title = "Grant Access"

        case .denied:
            iconLabel.stringValue = "⚠︎"
            titleLabel.stringValue = "Permission was declined"
            bodyLabel.stringValue = """
            Permission was declined, so Quintile's hotkeys are inactive. Enable \
            Quintile under System Settings → Privacy & Security → Accessibility. \
            Quintile picks up the grant automatically — no relaunch needed.
            """
            actionButton.title = "Open System Settings"

        case .revoked:
            iconLabel.stringValue = "⚠︎"
            titleLabel.stringValue = "Permission was withdrawn"
            bodyLabel.stringValue = """
            Accessibility permission was withdrawn while Quintile was running, \
            so hotkeys stopped working. Re-enable Quintile under System Settings → \
            Privacy & Security → Accessibility to restore them instantly.
            """
            actionButton.title = "Open System Settings"

        case .granted:
            iconLabel.stringValue = "✓"
            titleLabel.stringValue = "You're all set"
            bodyLabel.stringValue = """
            Accessibility is granted and Quintile's hotkeys are live. \
            Try ⌃⌥G for grid select, or open Preferences from the menu bar \
            to shape your grids.
            """
            actionButton.title = "Close"
        }
    }

    @objc private func primaryAction() {
        switch state {
        case .notDetermined:
            onRequestPermission?()
        case .denied, .revoked:
            onOpenSettings?()
        case .granted:
            window.orderOut(nil)
        }
    }
}
