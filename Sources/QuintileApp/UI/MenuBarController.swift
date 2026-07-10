import AppKit
import QuintileCore

/// U8: the NSStatusItem surface — permission-state icon, live menu (rebuilt
/// on every open via NSMenuDelegate), and the transient text indicator used
/// by the profile-cycle and boundary/failure signals.
final class MenuBarController: NSObject, NSMenuDelegate {

    // MARK: - Wiring (set by AppCoordinator)

    /// Called first on every menu open — the coordinator refreshes the
    /// permission state here so the menu is always live.
    var onMenuOpen: (() -> Void)?
    /// One header line per connected display, e.g.
    /// "Built-in Display — active: standard (5×2)".
    var displaySummaries: (() -> [String])?
    var onCycleProfile: (() -> Void)?
    var onGridSelect: (() -> Void)?
    var onShortcuts: (() -> Void)?
    /// One-glance keyboard map (post-grant coach / re-open anytime).
    var onQuickStart: (() -> Void)?
    var onPreferences: (() -> Void)?
    var onGrantAccessibility: (() -> Void)?
    /// Clean uninstall: quit, remove cask/app, reset Accessibility.
    var onUninstall: (() -> Void)?

    // MARK: - State

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var permissionState: PermissionState = .notDetermined
    private var transientRevert: DispatchWorkItem?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        applyBaseTitle()
    }

    // MARK: - Permission-state icon

    /// Title glyph doubles as the permission badge: "⊞" when granted, "⊞!"
    /// when not (grayed look is left to the exclamation badge + tooltip —
    /// template rendering keeps the glyph legible in any menu bar).
    func update(permissionState: PermissionState) {
        self.permissionState = permissionState
        applyBaseTitle()
    }

    private var baseTitle: String {
        permissionState == .granted ? "⊞" : "⊞!"
    }

    private func applyBaseTitle() {
        guard transientRevert == nil else { return } // don't stomp a transient
        statusItem.button?.title = baseTitle
        statusItem.button?.toolTip = tooltip(for: permissionState)
    }

    private func tooltip(for state: PermissionState) -> String {
        switch state {
        case .granted:
            return "Quintile"
        case .notDetermined:
            return "Quintile — Accessibility permission needed to move windows. Open the menu to grant."
        case .denied:
            return "Quintile — Accessibility permission was declined. Grant it in System Settings to enable hotkeys."
        case .revoked:
            return "Quintile — Accessibility permission was withdrawn. Re-enable it in System Settings to restore hotkeys."
        }
    }

    // MARK: - Transient indicator (cycle feedback, boundary/failure signals)

    /// Shows `title` in the status item for `duration`, then reverts to the
    /// permission-state glyph. A newer transient replaces a pending one.
    func showTransient(title: String, duration: TimeInterval) {
        transientRevert?.cancel()
        let revert = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transientRevert = nil
            self.applyBaseTitle()
        }
        transientRevert = revert
        statusItem.button?.title = title
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: revert)
    }

    // MARK: - Menu (rebuilt live on open)

    func menuNeedsUpdate(_ menu: NSMenu) {
        onMenuOpen?()
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()

        let summaries = displaySummaries?() ?? []
        for summary in summaries {
            menu.addItem(disabledItem(summary)) // header line per display
        }
        if !summaries.isEmpty { menu.addItem(.separator()) }

        menu.addItem(actionItem("Cycle Active Profile", #selector(cycleTapped),
                                key: "p", modifiers: [.control, .option]))
        menu.addItem(actionItem("Grid Select", #selector(gridSelectTapped),
                                key: "g", modifiers: [.control, .option]))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quick Start…", #selector(quickStartTapped)))
        menu.addItem(actionItem("Shortcuts…", #selector(shortcutsTapped)))
        menu.addItem(actionItem("Preferences…", #selector(preferencesTapped), key: ","))
        if permissionState != .granted {
            menu.addItem(actionItem("Grant Accessibility…", #selector(grantTapped)))
        }
        menu.addItem(.separator())
        menu.addItem(actionItem("Uninstall Quintile…", #selector(uninstallTapped)))
        let quit = NSMenuItem(title: "Quit Quintile",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, _ selector: Selector,
                            key: String = "",
                            modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    // MARK: - Menu actions

    @objc private func cycleTapped() { onCycleProfile?() }
    @objc private func gridSelectTapped() { onGridSelect?() }
    @objc private func quickStartTapped() { onQuickStart?() }
    @objc private func shortcutsTapped() { onShortcuts?() }
    @objc private func preferencesTapped() { onPreferences?() }
    @objc private func grantTapped() { onGrantAccessibility?() }
    @objc private func uninstallTapped() { onUninstall?() }
}
