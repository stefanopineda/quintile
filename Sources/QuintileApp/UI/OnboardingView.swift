import AppKit
import QuintileCore

/// Permission onboarding + the one-glance keyboard map shown after grant
/// (and again from menu bar → Quick Start…). Permission states flip live via
/// `update(state:)`; the cheat sheet is the granted state's body so every
/// first-run user who can use hotkeys sees it without a multi-step wizard.
final class OnboardingWindowController: NSObject {

    var onRequestPermission: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let window: NSWindow
    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let cheatSheetLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private var stack: NSStackView!
    private var state: PermissionState = .notDetermined
    /// When true, render the cheat sheet even if permission is not granted
    /// (menu → Quick Start… while still blocked).
    private var forceCheatSheet = false

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
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
        sizeToFitContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Live state-driven copy; safe to call whether or not the window is
    /// visible. A real permission transition drops a Quick Start override so
    /// grant/deny flips update the open window; polling with the same state
    /// leaves an open cheat sheet alone.
    func update(state: PermissionState) {
        let changed = state != self.state
        self.state = state
        if changed {
            forceCheatSheet = false
            render()
            if window.isVisible { sizeToFitContent() }
        } else if state == .granted, window.isVisible, !forceCheatSheet {
            // Ensure the open post-grant window stays on the cheat sheet if
            // something re-pushed `.granted` after a partial render.
            render()
            sizeToFitContent()
        }
    }

    /// Menu bar → Quick Start…: always show the keyboard map.
    func showQuickStart() {
        forceCheatSheet = true
        render()
        show()
    }

    // MARK: - Content

    private func buildContent() {
        iconLabel.font = NSFont.systemFont(ofSize: 40)
        iconLabel.alignment = .center

        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleLabel.alignment = .center

        bodyLabel.font = NSFont.systemFont(ofSize: 13)
        bodyLabel.alignment = .center
        bodyLabel.preferredMaxLayoutWidth = 400

        cheatSheetLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cheatSheetLabel.alignment = .left
        cheatSheetLabel.lineBreakMode = .byWordWrapping
        // Prefer natural monospaced metrics so columns stay aligned.
        cheatSheetLabel.maximumNumberOfLines = 0
        cheatSheetLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        footerLabel.font = NSFont.systemFont(ofSize: 11)
        footerLabel.alignment = .center
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.preferredMaxLayoutWidth = 400

        actionButton.target = self
        actionButton.action = #selector(primaryAction)
        actionButton.bezelStyle = .rounded
        actionButton.keyEquivalent = "\r"

        stack = NSStackView(views: [
            iconLabel, titleLabel, bodyLabel, cheatSheetLabel, footerLabel, actionButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 480),
            cheatSheetLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 424),
        ])
        window.contentView = content
    }

    private func sizeToFitContent() {
        guard let content = window.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        let width = max(480, fitting.width)
        let height = max(200, fitting.height)
        window.setContentSize(NSSize(width: width, height: height))
    }

    private func render() {
        let showCheat = forceCheatSheet || state == .granted

        if showCheat {
            renderCheatSheet(permissionGranted: state == .granted)
            return
        }

        cheatSheetLabel.isHidden = true
        footerLabel.isHidden = true
        bodyLabel.isHidden = false
        iconLabel.isHidden = false

        switch state {
        case .notDetermined:
            iconLabel.stringValue = "⊞"
            titleLabel.stringValue = "Quintile needs Accessibility permission"
            bodyLabel.stringValue = """
            Quintile needs Accessibility permission to move and resize windows. \
            System Settings will open straight to the Accessibility toggle — \
            Quintile never reads your screen contents, it only positions windows.
            """
            actionButton.title = "Grant Access"
            window.title = "Welcome to Quintile"

        case .denied:
            iconLabel.stringValue = "⚠︎"
            titleLabel.stringValue = "Permission was declined"
            bodyLabel.stringValue = """
            Permission was declined, so Quintile's hotkeys are inactive. Enable \
            Quintile under System Settings → Privacy & Security → Accessibility. \
            Quintile picks up the grant automatically — no relaunch needed.
            """
            actionButton.title = "Open System Settings"
            window.title = "Welcome to Quintile"

        case .revoked:
            iconLabel.stringValue = "⚠︎"
            titleLabel.stringValue = "Permission was withdrawn"
            bodyLabel.stringValue = """
            Accessibility permission was withdrawn while Quintile was running, \
            so hotkeys stopped working. Re-enable Quintile under System Settings → \
            Privacy & Security → Accessibility to restore them instantly.
            """
            actionButton.title = "Open System Settings"
            window.title = "Welcome to Quintile"

        case .granted:
            // Handled by showCheat path above.
            break
        }
    }

    private func renderCheatSheet(permissionGranted: Bool) {
        bodyLabel.isHidden = true
        cheatSheetLabel.isHidden = false
        footerLabel.isHidden = false
        iconLabel.isHidden = false

        iconLabel.stringValue = permissionGranted ? "✓" : "⊞"
        titleLabel.stringValue = "Hold ⌃⌥, then…"
        window.title = "Quintile Quick Start"

        // Monospaced columns — letter/chord left, meaning right.
        cheatSheetLabel.stringValue = """
        G            Grid — two keys place a window
        1  2  3  4   Quarters (top-left → bottom-right)
        [  ]  \\      Thirds (left · center · right)
        ⇧1 … ⇧6      Sixths (thirds × top/bottom)
        ←  ↑  ↓  →   Nudge one cell
        P            Cycle grid profile
        N            Next display

        In the grid: two keys · ⇧+arrows extend · ⏎ place · esc cancel
        """

        if permissionGranted {
            footerLabel.stringValue =
                "Hotkeys are live. Full list anytime: menu bar ⊞ → Shortcuts…"
        } else {
            footerLabel.stringValue =
                "Hotkeys need Accessibility first (Grant Access / System Settings)."
        }
        actionButton.title = "Got it"
    }

    @objc private func primaryAction() {
        if forceCheatSheet {
            forceCheatSheet = false
            window.orderOut(nil)
            return
        }
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
