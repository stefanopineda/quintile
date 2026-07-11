import AppKit
import QuintileCore

/// Permission onboarding, progressive first-win coach, and the full keyboard
/// map (menu bar → Quick Start…). Modes flip via `update(state:coach:)` and
/// `showQuickStart()`.
final class OnboardingWindowController: NSObject {

    enum Surface: Equatable {
        case permission
        case coach
        case coachDone
        case reference
    }

    var onRequestPermission: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onCheckAgain: (() -> Void)?
    var onSkipCoach: (() -> Void)?
    var onDismissCoachDone: (() -> Void)?
    /// Called when the window is shown/hidden so the app can adjust poll rate.
    var onVisibilityChange: ((Bool) -> Void)?

    private let window: NSWindow
    private let iconLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let cheatSheetLabel = NSTextField(labelWithString: "")
    private let footerLabel = NSTextField(wrappingLabelWithString: "")
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private var stack: NSStackView!
    private var state: PermissionState = .notDetermined
    private var coach: CoachProgress = .neverSeen
    private var forceReference = false
    private var coachFeedback: String?
    /// True after the user used Grant / Open Settings / Check again this session
    /// while still untrusted — drives stale-TCC copy.
    private var userAttemptedEnablement = false
    private(set) var currentSurface: Surface = .permission

    var isVisible: Bool { window.isVisible }

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
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: window)
    }

    // MARK: - API

    func show() {
        sizeToFitContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onVisibilityChange?(true)
    }

    func hide() {
        window.orderOut(nil)
        onVisibilityChange?(false)
    }

    /// Live state-driven copy; safe whether or not the window is visible.
    func update(state: PermissionState, coach: CoachProgress) {
        let changed = state != self.state || coach != self.coach
        self.state = state
        self.coach = coach
        if state == .granted {
            // Real trust — clear stale-attempt framing.
            userAttemptedEnablement = false
            forceReference = false
            coachFeedback = nil
        }
        if changed || window.isVisible {
            render()
            if window.isVisible { sizeToFitContent() }
        }
    }

    /// Menu bar → Quick Start…: full keyboard map (reference).
    func showQuickStart() {
        forceReference = true
        coachFeedback = nil
        render()
        show()
    }

    /// Recovery line while waiting for a successful third (no focus / AX fail).
    func setCoachFeedback(_ message: String?) {
        coachFeedback = message
        if currentSurface == .coach {
            render()
            if window.isVisible { sizeToFitContent() }
        }
    }

    func markUserAttemptedEnablement() {
        userAttemptedEnablement = true
        if state != .granted {
            render()
            if window.isVisible { sizeToFitContent() }
        }
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

        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryAction)
        secondaryButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [secondaryButton, actionButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.alignment = .centerY

        stack = NSStackView(views: [
            iconLabel, titleLabel, bodyLabel, cheatSheetLabel, footerLabel, buttonRow,
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
        if forceReference {
            currentSurface = .reference
            renderReference(permissionGranted: state == .granted)
            return
        }

        if state != .granted {
            currentSurface = .permission
            renderPermission()
            return
        }

        switch coach {
        case .neverSeen, .waitingForTry:
            currentSurface = .coach
            renderCoach(done: false)
        case .completed:
            // Only show done surface if window is already open for coach completion;
            // otherwise coordinator may not show a window.
            currentSurface = .coachDone
            renderCoach(done: true)
        case .skipped:
            currentSurface = .reference
            renderReference(permissionGranted: true)
        }
    }

    private func renderPermission() {
        cheatSheetLabel.isHidden = true
        bodyLabel.isHidden = false
        footerLabel.isHidden = false
        iconLabel.isHidden = false
        secondaryButton.isHidden = false
        secondaryButton.title = "Check Again"
        actionButton.isHidden = false
        window.title = "Welcome to Quintile"

        let menuBarNote =
            "Quintile lives in the menu bar (look for ⊞! near the clock) — not the Dock."

        switch state {
        case .notDetermined:
            iconLabel.stringValue = "⊞"
            titleLabel.stringValue = "Quintile needs Accessibility permission"
            bodyLabel.stringValue = """
            \(menuBarNote)

            Quintile needs Accessibility permission to move and resize windows. \
            System Settings opens to the Accessibility list — turn Quintile ON. \
            Quintile never reads your screen; it only positions windows.
            """
            footerLabel.stringValue = "Only one permission. No Screen Recording, no network."
            actionButton.title = "Open System Settings"
            if userAttemptedEnablement {
                titleLabel.stringValue = "Still waiting for Accessibility"
                bodyLabel.stringValue = """
                \(menuBarNote)

                If Quintile is already listed as ON, turn it OFF, then ON again. \
                macOS sometimes keeps a stale grant after reinstall or update. \
                Then click Check Again.
                """
            }

        case .denied:
            iconLabel.stringValue = "⚠︎"
            titleLabel.stringValue = userAttemptedEnablement
                ? "Permission not active yet"
                : "Permission was declined"
            bodyLabel.stringValue = """
            \(menuBarNote)

            Hotkeys stay off until macOS trusts this copy of Quintile.

            Open System Settings → Privacy & Security → Accessibility. Find \
            Quintile and turn it ON. If it already looks ON, turn it OFF then \
            ON again so this binary is re-authorized. Then click Check Again.
            """
            footerLabel.stringValue = "No relaunch needed once the grant sticks."
            actionButton.title = "Open System Settings"

        case .revoked:
            iconLabel.stringValue = "⚠︎"
            titleLabel.stringValue = "Permission was withdrawn"
            bodyLabel.stringValue = """
            \(menuBarNote)

            Accessibility was turned off while Quintile was running, so hotkeys \
            stopped. Re-enable Quintile under System Settings → Privacy & \
            Security → Accessibility. If the toggle is already ON but hotkeys \
            stay dead, turn it OFF then ON again.
            """
            footerLabel.stringValue = "Then click Check Again — no relaunch needed."
            actionButton.title = "Open System Settings"

        case .granted:
            break
        }
    }

    private func renderCoach(done: Bool) {
        cheatSheetLabel.isHidden = true
        bodyLabel.isHidden = false
        footerLabel.isHidden = false
        iconLabel.isHidden = false
        secondaryButton.isHidden = false
        actionButton.isHidden = false
        window.title = "Quintile — first tile"

        if done {
            iconLabel.stringValue = "✓"
            titleLabel.stringValue = "Nice — that’s the idea"
            bodyLabel.stringValue = """
            You placed a window with Control+Option.

            More layouts anytime: menu bar ⊞ → Quick Start… (full map) or \
            Shortcuts…. Profiles and the grid picker can wait until you want them.
            """
            footerLabel.stringValue = "Hotkeys stay live in the background."
            secondaryButton.isHidden = true
            actionButton.title = "Done"
            return
        }

        iconLabel.stringValue = "⊞"
        titleLabel.stringValue = "Try your first tile"
        var body = """
        1. Click any window (Safari, Notes, Finder…).
        2. Hold Control and Option together.
        3. Press [  (left third of the screen).

        ] is center third, \\ is right third — same idea.
        """
        if let coachFeedback {
            body += "\n\n\(coachFeedback)"
        }
        bodyLabel.stringValue = body
        footerLabel.stringValue =
            "Quintile is the ⊞ icon in the menu bar. Full shortcut list: menu → Quick Start…"
        secondaryButton.title = "Skip for now"
        actionButton.title = "Open System Settings"
        // Primary while granted is less useful; repurpose as "I'll try" dismiss? Plan: skip + auto detect.
        // Hide Open Settings when granted — only Skip + wait for keys.
        actionButton.isHidden = true
    }

    private func renderReference(permissionGranted: Bool) {
        bodyLabel.isHidden = true
        cheatSheetLabel.isHidden = false
        footerLabel.isHidden = false
        iconLabel.isHidden = false
        secondaryButton.isHidden = true
        actionButton.isHidden = false

        iconLabel.stringValue = permissionGranted ? "✓" : "⊞"
        titleLabel.stringValue = "Hold Control+Option, then…"
        window.title = "Quintile Quick Start"

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
                "Full list anytime: menu bar ⊞ → Shortcuts…"
        } else {
            footerLabel.stringValue =
                "Hotkeys need Accessibility first (Open System Settings / Check Again)."
        }
        actionButton.title = "Got it"
    }

    @objc private func primaryAction() {
        switch currentSurface {
        case .permission:
            userAttemptedEnablement = true
            if state == .notDetermined {
                onRequestPermission?()
            } else {
                onOpenSettings?()
            }
        case .coach:
            break
        case .coachDone:
            onDismissCoachDone?()
            hide()
        case .reference:
            forceReference = false
            hide()
        }
    }

    @objc private func secondaryAction() {
        switch currentSurface {
        case .permission:
            userAttemptedEnablement = true
            onCheckAgain?()
        case .coach:
            onSkipCoach?()
            hide()
        case .coachDone, .reference:
            break
        }
    }

    @objc private func windowWillClose(_ note: Notification) {
        onVisibilityChange?(false)
        if currentSurface == .coach, coach == .waitingForTry || coach == .neverSeen {
            onSkipCoach?()
        }
        forceReference = false
    }
}
