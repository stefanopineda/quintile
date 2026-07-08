// Quintile — LSUIElement menu-bar agent entry point (U8).
//
// The bundle's Info.plist sets LSUIElement; `.accessory` here is
// belt-and-braces so a bare `swift run` build behaves the same way
// (no Dock icon, no app menu).

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
