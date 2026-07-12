import AppKit
import QuintileCore

/// U8: the app-shell integration layer. Composes the fully-tested core stack
/// — persistence, AX window control, permission lifecycle, hotkeys, the
/// grid-select state machine, and the one-shot actions — into the running
/// LSUIElement menu-bar agent. All policy lives (tested) in QuintileCore;
/// this class only wires and routes.
///
/// Action-id routing:
///
/// | Action id                 | Component                                     |
/// |---------------------------|-----------------------------------------------|
/// | move.left/right/up/down   | MoveWithinGridAction (+ boundary signal)      |
/// | quadrant.1–4              | TilingActions presets                         |
/// | third.left/center/right   | TilingActions presets                         |
/// | sixth.1–6                 | TilingActions presets                         |
/// | profile.cycle             | ProfileCycler + indicator + flash (no retile) |
/// | display.next              | SendToDisplayAction                           |
/// | grid.select               | GridSelectionStateMachine modal session       |
final class AppCoordinator: NSObject {

    // MARK: - Core stack

    private let store: GridProfileStore
    /// Non-nil when the default store threw and we fell back (see makeStore).
    private let storeFallbackError: Error?
    /// Non-nil when a corrupt profiles.json was set aside (see makeStore).
    private let storeQuarantinePath: String?

    private let windowController: AXWindowController
    private let permissionManager = AccessibilityPermissionManager()
    private let hotkeyManager = HotkeyManager(tap: CGEventTapProvider())
    private let tilingActions: TilingActions
    private let moveAction: MoveWithinGridAction
    private let sendToDisplayAction: SendToDisplayAction
    private let profileCycler: ProfileCycler
    private let loginItemManager = LoginItemManager(service: SMAppServiceLoginItem())
    private let onboardingProgress: OnboardingProgressStore

    private let stateMachine = GridSelectionStateMachine()
    private let overlay = GridOverlayController()
    private let menuBar = MenuBarController()
    private lazy var onboarding = makeOnboarding()
    private lazy var preferences = makePreferences()

    // MARK: - Session / polling state

    private struct SelectionSession {
        let window: AXWindowHandle
        let display: DisplayDescriptor
        let profile: GridProfile
    }

    private var session: SelectionSession?
    private var permissionTimer: Timer?
    private var lastKnownPermissionState: PermissionState = .notDetermined
    /// True while the onboarding window is visible — drives faster AX poll.
    private var onboardingVisible = false
    private var didShowDiscoverability = false

    // MARK: - Init

    override init() {
        let made = AppCoordinator.makeStore()
        store = made.store
        storeFallbackError = made.fallbackError
        storeQuarantinePath = made.quarantinePath
        onboardingProgress = (try? OnboardingProgressStore())
            ?? OnboardingProgressStore(initial: .neverSeen)

        let controller = AXWindowController(backend: LiveAXBackend())
        windowController = controller
        tilingActions = TilingActions(windowController: controller)
        moveAction = MoveWithinGridAction(windowController: controller, store: store)
        sendToDisplayAction = SendToDisplayAction(windowController: controller, store: store)
        profileCycler = ProfileCycler(store: store)
        super.init()
    }

    /// Store creation policy (documented decision): if the default
    /// Application Support store cannot be created/decoded, the existing
    /// profiles.json (if any) is quarantined — renamed alongside itself, so
    /// user data is never deleted — and the default-directory store is
    /// retried on the now-fresh directory (edits keep persisting across
    /// relaunches). Only if that retry also fails does Quintile fall back to
    /// a temp-directory store for the session (tiling and cycling work;
    /// edits simply do not survive relaunch); the user is told once via an
    /// alert in `start()`. Only if even the temp-dir store fails do we alert
    /// and quit gracefully.
    private static func makeStore()
        -> (store: GridProfileStore, fallbackError: Error?, quarantinePath: String?) {
        do {
            return (try GridProfileStore(), nil, nil)
        } catch {
            var quarantinePath: String?
            let fileURL = GridProfileStore.defaultDirectory
                .appendingPathComponent("profiles.json", isDirectory: false)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let backupURL = fileURL.deletingLastPathComponent()
                    .appendingPathComponent(
                        "profiles-\(formatter.string(from: Date())).corrupt.json",
                        isDirectory: false)
                if (try? FileManager.default.moveItem(at: fileURL, to: backupURL)) != nil {
                    quarantinePath = backupURL.path
                    if let retried = try? GridProfileStore() {
                        return (retried, nil, quarantinePath)
                    }
                }
            }
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("Quintile-fallback-\(ProcessInfo.processInfo.processIdentifier)")
            if let fallback = try? GridProfileStore(directory: tempDir) {
                return (fallback, error, quarantinePath)
            }
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Quintile can't start"
            alert.informativeText = "The grid profile store could not be created: \(error.localizedDescription)"
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            exit(1)
        }
    }

    // MARK: - Startup

    func start() {
        wireMenuBar()
        registerHotkeyActions()

        let demoMode = ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["QUINTILE_DEMO"] == "1"
        if demoMode {
            onboardingProgress.suppressForDemo()
        }
        // Homebrew postflight passes --first-run so a reinstall always offers
        // the coach again when the user has not completed a first tile
        // (never forces after completed — only re-surfaces waiting/neverSeen).
        let forceFirstRun = ProcessInfo.processInfo.arguments.contains("--first-run")

        // Permission flow: the granted transition — and ONLY it — activates
        // the event tap and registers the login item. Never speculatively.
        permissionManager.onGrantedTransition { [weak self] in
            guard let self else { return }
            do {
                try self.hotkeyManager.activate()
            } catch {
                FileHandle.standardError.write(
                    Data("Quintile: event tap activation failed: \(error)\n".utf8))
            }
            self.loginItemManager.registerAfterPermissionGranted()
            self.onboardingProgress.markWaitingIfNeeded()
            self.syncPermissionState()
            if self.onboardingProgress.coach == .waitingForTry
                || self.onboardingProgress.coach == .neverSeen {
                self.showOnboarding()
            }
        }

        // Mid-session interruptions for the grid-select overlay.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(otherAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        permissionManager.checkOnLaunch()
        syncPermissionState()
        showDiscoverabilityIfNeeded()

        // First-run surfaces (must cover "Accessibility already ON from a prior
        // install" — onGrantedTransition may have fired above, but cold start
        // with neverSeen + already-granted used to skip the coach entirely when
        // only `.waitingForTry` was checked).
        if forceFirstRun,
           onboardingProgress.coach == .skipped {
            // Reinstall: user asked for first-run again via brew postflight.
            onboardingProgress.setCoach(.neverSeen)
        }
        presentFirstRunIfNeeded(openSettingsIfUndetermined: true)

        if !demoMode, let storeFallbackError {
            let backupNote = storeQuarantinePath.map {
                " The unreadable profile file was set aside at \($0)."
            } ?? ""
            let alert = NSAlert()
            alert.messageText = "Profile storage unavailable"
            alert.informativeText = """
            Quintile could not open its profile store \
            (\(storeFallbackError.localizedDescription)). \
            Grids work normally this session, but edits won't survive a relaunch.\
            \(backupNote)
            """
            alert.runModal()
        } else if !demoMode, let storeQuarantinePath {
            let alert = NSAlert()
            alert.messageText = "Grid profiles were reset"
            alert.informativeText = """
            Quintile could not read its saved grid profiles, so it started \
            fresh with the defaults. The unreadable file was set aside at \
            \(storeQuarantinePath).
            """
            alert.runModal()
        }
    }

    /// Spotlight / `open -a` while already running: re-surface stuck UI.
    func handleReopen() {
        refreshPermission()
        presentFirstRunIfNeeded(openSettingsIfUndetermined: false)
        // completed / skipped + granted → menu bar only (no window)
    }

    /// Show permission UI, or the first-win coach, whenever the user still
    /// has not finished (or skipped) first-run teaching.
    private func presentFirstRunIfNeeded(openSettingsIfUndetermined: Bool) {
        let state = permissionManager.state
        let coach = onboardingProgress.coach

        if state != .granted {
            showOnboarding()
            if openSettingsIfUndetermined, state == .notDetermined {
                NSWorkspace.shared.open(
                    AccessibilityPermissionManager.accessibilitySettingsDeepLink)
            }
            return
        }

        switch coach {
        case .neverSeen, .waitingForTry:
            onboardingProgress.markWaitingIfNeeded()
            showOnboarding()
        case .completed, .skipped:
            break
        }
    }

    // MARK: - Permission polling & UI sync

    /// Central permission-state sync: menu-bar icon, onboarding modes, hotkey
    /// deactivate on revoke, and adaptive poll while not granted.
    private func syncPermissionState() {
        let state = permissionManager.state
        let previous = lastKnownPermissionState

        if state != previous {
            if state == .revoked {
                hotkeyManager.deactivate()
                // Auto-show once per revoke transition.
                showOnboarding()
            }
            lastKnownPermissionState = state
        }

        menuBar.update(permissionState: state)
        onboarding.update(state: state, coach: onboardingProgress.coach)
        restartPermissionTimerIfNeeded(state: state)
    }

    private func restartPermissionTimerIfNeeded(state: PermissionState) {
        if state == .granted {
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }
        let interval: TimeInterval = onboardingVisible ? 0.75 : 3.0
        // Rebuild timer when interval changes or timer is missing.
        if let timer = permissionTimer, abs(timer.timeInterval - interval) < 0.01 {
            return
        }
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.permissionManager.refresh()
            self.syncPermissionState()
        }
    }

    private func refreshPermission() {
        permissionManager.refresh()
        syncPermissionState()
    }

    private func showDiscoverabilityIfNeeded() {
        guard !didShowDiscoverability else { return }
        didShowDiscoverability = true
        let glyph = permissionManager.state == .granted ? "⊞" : "⊞!"
        menuBar.showTransient(title: "\(glyph) menu bar", duration: 4.0)
    }

    // MARK: - Hotkey wiring

    private func registerHotkeyActions() {
        let presets: [String: PresetAction] = [
            "quadrant.1": .quadrant1, "quadrant.2": .quadrant2,
            "quadrant.3": .quadrant3, "quadrant.4": .quadrant4,
            "third.left": .thirdLeft, "third.center": .thirdCenter,
            "third.right": .thirdRight,
            "sixth.1": .sixth1, "sixth.2": .sixth2, "sixth.3": .sixth3,
            "sixth.4": .sixth4, "sixth.5": .sixth5, "sixth.6": .sixth6,
        ]
        let moves: [String: MoveDirection] = [
            "move.left": .left, "move.right": .right,
            "move.up": .up, "move.down": .down,
        ]

        for (id, binding) in HotkeyBinding.defaultBindings {
            hotkeyManager.register(binding, id: id) { [weak self] in
                guard let self else { return }
                self.refreshPermission()
                if let preset = presets[id] {
                    self.performPreset(preset)
                } else if let direction = moves[id] {
                    self.performMove(direction)
                } else {
                    switch id {
                    case "profile.cycle": self.cycleProfile()
                    case "display.next": self.sendToNextDisplay()
                    case "grid.select": self.beginGridSelect()
                    default: break
                    }
                }
            }
        }
    }

    private func performPreset(_ preset: PresetAction) {
        let outcome = tilingActions.perform(preset)
        switch outcome {
        case .failed:
            failureSignal()
            if onboardingProgress.coach == .waitingForTry {
                onboarding.setCoachFeedback(
                    "That app blocked the resize — try Finder, Notes, or Safari.")
            }
        case .noFocusedWindow:
            if onboardingProgress.coach == .waitingForTry {
                onboarding.setCoachFeedback(
                    "Click a window first, then hold Control+Option and press [.")
            }
        case .performed:
            if FirstWinDetector.shouldCompleteCoach(preset: preset, outcome: outcome),
               onboardingProgress.coach == .waitingForTry
                || onboardingProgress.coach == .neverSeen {
                onboardingProgress.markCompleted()
                onboarding.update(state: permissionManager.state, coach: .completed)
                onboarding.show()
            }
        case .onlyOneDisplay:
            break
        }
    }

    private func performMove(_ direction: MoveDirection) {
        switch moveAction.move(direction) {
        case .boundaryReached: boundarySignal()
        case .failed: failureSignal()
        case .moved(let occupantErrors):
            // The mover landed, but occupant relocations may have failed
            // (partial-failure semantics of MoveWithinGridAction). Surface
            // that like any other failed AX write instead of dropping it.
            if !occupantErrors.isEmpty {
                FileHandle.standardError.write(
                    Data("Quintile: occupant relocation failed: \(occupantErrors)\n".utf8))
                failureSignal()
            }
        case .noFocusedWindow: break
        }
    }

    private func sendToNextDisplay() {
        switch sendToDisplayAction.send() {
        case .onlyOneDisplay: boundarySignal()
        case .failed: failureSignal()
        case .performed, .noFocusedWindow: break
        }
    }

    // MARK: - Feedback signals

    /// Boundary-reached signal (plan: "brief menu-bar flash or subtle sound,
    /// distinct from the profile-cycle indicator"): ⛔︎ for ~0.4 s + a soft
    /// system sound. The cycle indicator, by contrast, is text ("5×2
    /// standard") for 0.8 s plus a grid flash.
    private func boundarySignal() {
        menuBar.showTransient(title: "⛔︎", duration: 0.4)
        NSSound(named: "Tink")?.play()
    }

    /// Alert-free typed-error feedback for failed AX writes.
    private func failureSignal() {
        menuBar.showTransient(title: "⚠︎", duration: 0.6)
    }

    /// One-time (per launch) surfacing of profile-persist failures after a
    /// profile-mutating operation (cycle, preferences edits). Documented
    /// choice: a stderr log plus a menu-bar warning flash — consistent with
    /// the app's alert-free typed-error feedback pattern; an NSAlert on every
    /// stepper keystroke would be hostile. Guarded so it fires at most once
    /// per launch, not on every mutation.
    private var warnedPersistError = false
    private func surfacePersistErrorIfNeeded() {
        guard !warnedPersistError, let error = store.lastPersistError else { return }
        warnedPersistError = true
        FileHandle.standardError.write(
            Data("Quintile: profile changes are not being saved: \(error)\n".utf8))
        menuBar.showTransient(title: "⚠︎ not saved", duration: 1.5)
    }

    // MARK: - Profile cycle (pointer-only — NEVER retiles)

    /// Target display: the focused window's display; fallback to the display
    /// under the mouse pointer, else the main display. Cycling changes ONLY
    /// the active-profile pointer (`ProfileCycler` has no window access by
    /// construction); feedback is the menu-bar transient indicator plus a
    /// grid flash on the affected display.
    private func cycleProfile() {
        guard let display = displayOfFocusedWindow() ?? displayUnderMouse() ?? mainDisplay() else {
            return
        }
        let result = profileCycler.cycle(for: display.identity)
        menuBar.showTransient(
            title: "\(result.profile.cols)×\(result.profile.rows) \(result.profile.name)",
            duration: 0.8)
        // After the indicator, so a persist-failure warning (if any) wins the
        // status-item slot. Cycle persists the active-slot pointer.
        surfacePersistErrorIfNeeded()
        if session == nil { // don't clobber a live grid-select overlay
            overlay.flash(profile: result.profile, on: display, duration: 0.5)
        }
    }

    // MARK: - Grid-select modal session

    private func beginGridSelect() {
        do {
            guard let window = try windowController.focusedWindow(),
                  let display = try windowController.display(containing: window) else {
                if session != nil { process(stateMachine.escape()) }
                process(stateMachine.beginFailedNoWindow())
                return
            }
            let profile = store.activeProfile(for: display.identity)
            let frame = try windowController.frame(of: window)
            let span = GridMath.frameToNearestSpan(profile: profile,
                                                   displayBounds: display.usableBounds,
                                                   frame: frame)
            // Retain the handle for the whole session; re-entrant leader
            // press just restarts on the (possibly new) focused window.
            session = SelectionSession(window: window, display: display, profile: profile)
            hotkeyManager.modalInterceptor = { [weak self] event in
                self?.handleModalKey(event) ?? .passThrough
            }
            process(stateMachine.begin(profile: profile, initialSpan: span))
        } catch {
            if session != nil { process(stateMachine.escape()) }
            failureSignal()
        }
    }

    /// Modal key routing while a session is active. Session keys — arrows
    /// (±shift), Return, Escape, and cell keys of the session profile — are
    /// consumed (key-ups included, so the focused app never sees half a
    /// keystroke); everything else passes through to normal binding dispatch
    /// (plan: only session keys are consumed).
    private func handleModalKey(_ event: KeyEvent) -> EventDisposition {
        guard let session else { return .passThrough }

        switch event.keyCode {
        case KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow:
            guard event.isKeyDown else { return .consume }
            let direction: MoveDirection
            switch event.keyCode {
            case KeyCode.leftArrow: direction = .left
            case KeyCode.rightArrow: direction = .right
            case KeyCode.upArrow: direction = .up
            default: direction = .down
            }
            process(event.modifiers.contains(.shift)
                    ? stateMachine.shiftArrow(direction)
                    : stateMachine.arrow(direction))
            return .consume

        case Self.returnKeyCode, Self.keypadEnterKeyCode:
            guard event.isKeyDown else { return .consume }
            process(stateMachine.enter())
            return .consume

        case Self.escapeKeyCode:
            guard event.isKeyDown else { return .consume }
            process(stateMachine.escape())
            return .consume

        default:
            // Cell keys: bare character keys addressing a cell of the session
            // profile. Chords carrying ⌘/⌃/⌥ pass through so real shortcuts
            // (including a repeated ⌃⌥G leader restart) keep working.
            guard event.modifiers.isDisjoint(with: [.command, .control, .option]),
                  let character = Self.cellKeyCharacters[event.keyCode],
                  let cell = GridSelectionStateMachine.cell(forKey: character,
                                                            profile: session.profile) else {
                return .passThrough
            }
            guard event.isKeyDown else { return .consume }
            process(stateMachine.cellKey(col: cell.col, row: cell.row))
            return .consume
        }
    }

    /// Executes state-machine effects in order.
    private func process(_ effects: [GridSelectionStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .showOverlay(let profile):
                guard let session else { break }
                let selection = stateMachine.currentSelection
                    ?? CellSpan(startCol: 0, startRow: 0)
                overlay.show(profile: profile, on: session.display, selection: selection)

            case .updateSelection(let span):
                overlay.update(selection: span)

            case .confirm(let span):
                confirmPlacement(span)

            case .dismissOverlay(let reason):
                overlay.hide(announcing: announcement(for: reason))
                endSession()

            case .noWindowToPlace:
                if let display = displayUnderMouse() ?? mainDisplay() {
                    overlay.showNoWindowHUD(on: display)
                }
            }
        }
    }

    private func confirmPlacement(_ span: CellSpan) {
        guard let session else { return }
        let frame = GridMath.cellSpanToFrame(profile: session.profile,
                                             displayBounds: session.display.usableBounds,
                                             span: span)
        // Confirm arrives via the modal interceptor, i.e. inside the event
        // tap callback. The AX write can block on a hung target app, and a
        // slow tap callback stalls ALL system keyboard input — so hop to the
        // main queue and let the callback return immediately. The session's
        // window handle is captured here; the dismissOverlay effect that
        // follows may clear `session` before the write runs.
        let window = session.window
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do {
                try self.windowController.setFrame(frame, of: window)
            } catch AXWindowError.invalidWindow {
                // Target closed between begin and confirm — the moral
                // equivalent of interrupted(.targetWindowClosed): the
                // dismissOverlay effect closes the session cleanly, no error
                // feedback.
            } catch {
                self.failureSignal() // alert-free typed-error feedback (menu-bar flash)
            }
        }
    }

    private func endSession() {
        session = nil
        hotkeyManager.modalInterceptor = nil
    }

    private func announcement(for reason: GridSelectionStateMachine.DismissReason) -> String {
        switch reason {
        case .confirmed: return "Placed window"
        case .cancelled: return "Cancelled"
        case .interrupted: return "Grid selection interrupted"
        }
    }

    // MARK: - Interruptions

    @objc private func otherAppActivated(_ note: Notification) {
        guard session != nil else { return }
        process(stateMachine.interrupted(.appDeactivated))
    }

    @objc private func screenParametersChanged(_ note: Notification) {
        guard session != nil else { return }
        process(stateMachine.interrupted(.displayConfigurationChanged))
    }

    // MARK: - Display resolution helpers

    private func displayOfFocusedWindow() -> DisplayDescriptor? {
        guard let window = try? windowController.focusedWindow() else { return nil }
        return (try? windowController.display(containing: window)) ?? nil
    }

    private func displayUnderMouse() -> DisplayDescriptor? {
        let displays = windowController.displays()
        guard !displays.isEmpty else { return nil }
        // NSEvent.mouseLocation is Cocoa bottom-left global; DisplayDescriptor
        // bounds are Quartz top-left global (conversion via the shared
        // QuartzCocoa helper).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let quartzPoint = QuartzCocoa.quartzPoint(fromCocoa: NSEvent.mouseLocation,
                                                  primaryHeight: primaryHeight)
        return displays.first { $0.quartzBounds.contains(quartzPoint) }
    }

    private func mainDisplay() -> DisplayDescriptor? {
        let displays = windowController.displays()
        return displays.first { $0.id == CGMainDisplayID() } ?? displays.first
    }

    // MARK: - Menu bar & windows

    private func wireMenuBar() {
        menuBar.onMenuOpen = { [weak self] in self?.refreshPermission() }
        menuBar.displaySummaries = { [weak self] in self?.displaySummaries() ?? [] }
        menuBar.onCycleProfile = { [weak self] in self?.cycleProfile() }
        menuBar.onGridSelect = { [weak self] in self?.beginGridSelect() }
        menuBar.onShortcuts = { [weak self] in self?.showPreferences(tab: .shortcuts) }
        menuBar.onQuickStart = { [weak self] in self?.onboarding.showQuickStart() }
        menuBar.onPreferences = { [weak self] in self?.showPreferences(tab: .standard) }
        menuBar.onGrantAccessibility = { [weak self] in self?.showOnboarding() }
        menuBar.onUninstall = { [weak self] in self?.confirmAndUninstall() }
    }

    // MARK: - Clean uninstall

    /// Menu-bar "Uninstall Quintile…": confirm, unregister login item, spawn
    /// the post-quit helper (brew cask + app removal + Accessibility reset),
    /// then terminate. Profiles under Application Support are kept.
    private func confirmAndUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Quintile?"
        alert.informativeText = """
            This will:
            • Quit Quintile
            • Remove the app (Homebrew cask when installed that way)
            • Reset Accessibility permission for Quintile

            Your grid profiles in Application Support are left alone so a \
            reinstall can pick them up again.
            """
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        // Destructive first button styling on supported macOS.
        if #available(macOS 11.0, *) {
            alert.buttons.first?.hasDestructiveAction = true
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        performUninstall()
    }

    private func performUninstall() {
        // Stop relaunching at login before the bundle is deleted.
        loginItemManager.unregisterIfNeeded()

        do {
            let scriptURL = try UninstallScript.writeTemporaryScript()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            // Detach so the helper outlives this process.
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Couldn't start uninstall"
            alert.informativeText = """
                Quintile couldn't launch the uninstall helper: \
                \(error.localizedDescription)

                You can still remove it manually:
                brew uninstall --cask quintile
                tccutil reset Accessibility \(UninstallScript.bundleIdentifier)
                """
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        NSApp.terminate(nil)
    }

    private func displaySummaries() -> [String] {
        windowController.displays().map { display in
            let config = store.config(for: display.identity)
            let profile = config.activeProfile
            let name = display.info.localizedName.isEmpty
                ? "Display" : display.info.localizedName
            return "\(name) — active: \(config.activeSlot.rawValue) (\(profile.cols)×\(profile.rows))"
        }
    }

    private func makeOnboarding() -> OnboardingWindowController {
        let controller = OnboardingWindowController()
        controller.onRequestPermission = { [weak self] in
            guard let self else { return }
            self.onboarding.markUserAttemptedEnablement()
            self.permissionManager.checkOnLaunch()
            self.syncPermissionState()
            NSWorkspace.shared.open(AccessibilityPermissionManager.accessibilitySettingsDeepLink)
        }
        controller.onOpenSettings = { [weak self] in
            self?.onboarding.markUserAttemptedEnablement()
            NSWorkspace.shared.open(AccessibilityPermissionManager.accessibilitySettingsDeepLink)
        }
        controller.onCheckAgain = { [weak self] in
            guard let self else { return }
            self.onboarding.markUserAttemptedEnablement()
            self.refreshPermission()
            if self.permissionManager.state == .granted {
                self.onboardingProgress.markWaitingIfNeeded()
                self.syncPermissionState()
                self.showOnboarding()
            }
        }
        controller.onSkipCoach = { [weak self] in
            self?.onboardingProgress.markSkipped()
            self?.syncPermissionState()
        }
        controller.onDismissCoachDone = { [weak self] in
            self?.syncPermissionState()
        }
        controller.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.onboardingVisible = visible
            self.restartPermissionTimerIfNeeded(state: self.permissionManager.state)
        }
        return controller
    }

    private func showOnboarding() {
        onboarding.update(state: permissionManager.state, coach: onboardingProgress.coach)
        onboarding.show()
    }

    private func makePreferences() -> PreferencesWindowController {
        let controller = PreferencesWindowController(
            store: store,
            connectedDisplays: { [weak self] in self?.windowController.displays() ?? [] },
            shortcutRows: { [weak self] in
                guard let self else { return [] }
                return self.hotkeyManager.bindings
                    .sorted { $0.key < $1.key }
                    .map { (action: ActionNames.displayName(for: $0.key),
                            chord: $0.value.description) }
            })
        controller.onProfilePersisted = { [weak self] in
            self?.surfacePersistErrorIfNeeded()
        }
        return controller
    }

    private func showPreferences(tab: PreferencesWindowController.Tab) {
        preferences.show(tab: tab)
    }

    // MARK: - Key code tables (ANSI layout)

    static let returnKeyCode: CGKeyCode = 36
    static let keypadEnterKeyCode: CGKeyCode = 76
    static let escapeKeyCode: CGKeyCode = 53

    /// ANSI key code → the character used by
    /// `GridSelectionStateMachine.cellKeyLayout` (digit row + QWERTY rows).
    static let cellKeyCharacters: [CGKeyCode: Character] = [
        // 1234567890
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        // QWERTYUIOP
        12: "Q", 13: "W", 14: "E", 15: "R", 17: "T",
        16: "Y", 32: "U", 34: "I", 31: "O", 35: "P",
        // ASDFGHJKL;
        0: "A", 1: "S", 2: "D", 3: "F", 5: "G",
        4: "H", 38: "J", 40: "K", 37: "L", 41: ";",
        // ZXCVBNM,./
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        45: "N", 46: "M", 43: ",", 47: ".", 44: "/",
    ]
}

/// Human-readable names for the default action ids — feeds the menu bar and
/// the Shortcuts reference tab.
enum ActionNames {
    private static let names: [String: String] = [
        "move.left": "Move Window Left",
        "move.right": "Move Window Right",
        "move.up": "Move Window Up",
        "move.down": "Move Window Down",
        "grid.select": "Grid Select",
        "quadrant.1": "Quadrant — Top Left",
        "quadrant.2": "Quadrant — Top Right",
        "quadrant.3": "Quadrant — Bottom Left",
        "quadrant.4": "Quadrant — Bottom Right",
        "third.left": "Left Third",
        "third.center": "Center Third",
        "third.right": "Right Third",
        "profile.cycle": "Cycle Active Profile",
        "display.next": "Send to Next Display",
        "sixth.1": "Sixth — Left Top",
        "sixth.2": "Sixth — Left Bottom",
        "sixth.3": "Sixth — Center Top",
        "sixth.4": "Sixth — Center Bottom",
        "sixth.5": "Sixth — Right Top",
        "sixth.6": "Sixth — Right Bottom",
    ]

    static func displayName(for actionID: String) -> String {
        names[actionID] ?? actionID
    }
}
