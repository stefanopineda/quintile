import CoreGraphics // CGKeyCode

/// Fn+Ctrl+Arrow interception — SPIKE OUTCOME (U5, plan-required write-up)
/// =======================================================================
///
/// ## (a) Approach
/// macOS's built-in window tiling (macOS 15+) binds Fn+Ctrl+Arrow inside
/// WindowServer. Quintile's best-effort takeover installs its bindings
/// through the same session event tap `HotkeyManager` already owns —
/// `.cgSessionEventTap` at `.headInsertEventTap`, the earliest hook a
/// SIP-respecting, public-API-only process gets. When the tap callback sees
/// a key-down whose chord is physical-fn + control + an arrow, it returns
/// nil (consume), which is supposed to stop the event before any later
/// consumer — including, we hope, the built-in tiling handler.
/// `CGEventTapProvider` additionally tracks the *physical* fn key via
/// flagsChanged (key code 63), because arrow events carry `.maskSecondaryFn`
/// even without fn held, so the raw flag alone cannot distinguish
/// Fn+Ctrl+Arrow from Ctrl+Arrow.
///
/// ## (b) Constraint — verdict cannot be confirmed here
/// This spike CANNOT be verified in this development environment: the test
/// runner has no Accessibility grant, so `CGEvent.tapCreate` returns NULL
/// and no real tap ever exists; and synthetic `CGEvent.post` round-trips
/// would not prove ordering against WindowServer anyway. More fundamentally,
/// recent macOS releases (observed through macOS 26) dispatch Fn+Ctrl+Arrow
/// to the tiling machinery *inside* WindowServer early in event routing, and
/// whether a head-insert session tap's consume reliably wins that race is
/// unproven across the supported version range. Treat interception
/// reliability as UNKNOWN / PARTIALLY RELIABLE until the manual checklist
/// below has been run on each supported major version.
///
/// ## (c) Verdict → U8 preferences design
/// - SHIP the leader-key scheme (`HotkeyBinding.defaultBindings`, below) as
///   the default and only-out-of-the-box binding set. It is fully reliable
///   and needs nothing but the Accessibility grant.
/// - EXPOSE the takeover as an opt-in preference: "Take over macOS tiling
///   shortcuts (Experimental)" — off by default, "Experimental" badge, with
///   help text noting the OS handler may still fire on some macOS versions.
/// - DOCUMENT the guided-setup alternative in onboarding/help: the user
///   disables the built-in shortcuts themselves in System Settings >
///   Keyboard (macOS exposes toggles for its tiling shortcuts; on recent
///   releases under Desktop & Dock > Windows, the "Tile by dragging…" and
///   keyboard-shortcut options). Once the OS bindings are off, Quintile's
///   tap merely needs to *observe and act on* Fn+Ctrl+Arrow — no consume
///   race against WindowServer — which IS reliable. This is the recommended
///   path for users who want the native gesture.
///
/// ## (d) Manual verification checklist (run on a live, trusted machine)
/// 1. Build the app bundle, launch it, and grant Accessibility in System
///    Settings > Privacy & Security > Accessibility. Confirm via logs that
///    `HotkeyManager.activate()` created the tap after the grant.
/// 2. Sanity-check the leader scheme: Ctrl+Option+Left moves the focused
///    window within the grid; no OS behavior fires.
/// 3. Enable takeover (`SystemShortcutBridge.enableTakeover`). With the OS
///    tiling shortcuts still ON in System Settings, press Fn+Ctrl+Left in
///    Finder: EXPECT Quintile's action only. FAIL if the window half-tiles
///    natively (OS handler won), or both fire.
/// 4. Repeat step 3 for Right/Up/Down, in a full-screen-capable app and in a
///    Stage Manager session.
/// 5. Verify plain Ctrl+Left (no fn) and Fn+Left (no ctrl) are NOT consumed
///    (fn-tracking correctness — spaces switching etc. keep working).
/// 6. Hold the machine busy (e.g. compile) and hammer keys to provoke
///    `kCGEventTapDisabledByTimeout`; confirm hotkeys keep working
///    (auto re-enable in `CGEventTapProvider.process`).
/// 7. Disable the OS tiling shortcuts in System Settings > Keyboard, disable
///    takeover consume-mode expectations, and re-run step 3: EXPECT
///    Quintile's action fires and nothing else happens (the reliable
///    guided-setup path).
/// 8. Record pass/fail per macOS major version in the PR description and
///    update section (b)/(c) above if interception proves reliable.
public final class SystemShortcutBridge {

    /// The four directions the macOS tiling gesture covers.
    public enum Direction: String, CaseIterable {
        case left, right, up, down

        var keyCode: CGKeyCode {
            switch self {
            case .left: return KeyCode.leftArrow
            case .right: return KeyCode.rightArrow
            case .up: return KeyCode.upArrow
            case .down: return KeyCode.downArrow
            }
        }
    }

    /// The OS chord: physical fn + control + arrow.
    public static func binding(for direction: Direction) -> HotkeyBinding {
        HotkeyBinding(keyCode: direction.keyCode, modifiers: [.fn, .control])
    }

    static func registrationID(for direction: Direction) -> String {
        "system-takeover.\(direction.rawValue)"
    }

    private let hotkeys: HotkeyManager
    public private(set) var isTakeoverEnabled = false

    public init(hotkeys: HotkeyManager) {
        self.hotkeys = hotkeys
    }

    /// Registers Fn+Ctrl+Arrow for all four directions through the shared
    /// tap; matching key-downs are consumed (best-effort — see spike notes).
    public func enableTakeover(_ action: @escaping (Direction) -> Void) {
        for direction in Direction.allCases {
            hotkeys.register(
                Self.binding(for: direction),
                id: Self.registrationID(for: direction)
            ) { action(direction) }
        }
        isTakeoverEnabled = true
    }

    /// Removes the takeover registrations; the OS chord passes through again.
    public func disableTakeover() {
        for direction in Direction.allCases {
            hotkeys.unregister(id: Self.registrationID(for: direction))
        }
        isTakeoverEnabled = false
    }
}

// MARK: - Default leader-key scheme

/// Quintile's shipped bindings (U8 loads these as the defaults; users may
/// rebind). Leader chord is Ctrl+Option — chosen because it is nearly
/// unclaimed by macOS and by common apps, unlike Cmd-based chords.
///
/// | Action id        | Chord                | Meaning                        |
/// |------------------|----------------------|--------------------------------|
/// | move.left/right/ | ⌃⌥ + Arrow           | Move window within grid        |
/// |   up/down        |                      |                                |
/// | grid.select      | ⌃⌥G                  | Grid-select overlay (U6)       |
/// | quadrant.1…4     | ⌃⌥1…4                | Quadrants (TL, TR, BL, BR)     |
/// | third.left       | ⌃⌥[                  | Left third                     |
/// | third.center     | ⌃⌥]                  | Center third                   |
/// | third.right      | ⌃⌥\                  | Right third                    |
/// | profile.cycle    | ⌃⌥P                  | Cycle grid profile             |
/// | display.next     | ⌃⌥N                  | Send window to next display    |
/// | sixth.1…6        | ⌃⌥⇧1…6               | Sixths                         |
extension HotkeyBinding {
    public static let defaultBindings: [String: HotkeyBinding] = {
        let leader: KeyModifiers = [.control, .option]
        let leaderShift: KeyModifiers = [.control, .option, .shift]
        return [
            "move.left": HotkeyBinding(keyCode: KeyCode.leftArrow, modifiers: leader),
            "move.right": HotkeyBinding(keyCode: KeyCode.rightArrow, modifiers: leader),
            "move.up": HotkeyBinding(keyCode: KeyCode.upArrow, modifiers: leader),
            "move.down": HotkeyBinding(keyCode: KeyCode.downArrow, modifiers: leader),
            "grid.select": HotkeyBinding(keyCode: KeyCode.ansiG, modifiers: leader),
            "quadrant.1": HotkeyBinding(keyCode: KeyCode.ansiOne, modifiers: leader),
            "quadrant.2": HotkeyBinding(keyCode: KeyCode.ansiTwo, modifiers: leader),
            "quadrant.3": HotkeyBinding(keyCode: KeyCode.ansiThree, modifiers: leader),
            "quadrant.4": HotkeyBinding(keyCode: KeyCode.ansiFour, modifiers: leader),
            "third.left": HotkeyBinding(keyCode: KeyCode.leftBracket, modifiers: leader),
            "third.center": HotkeyBinding(keyCode: KeyCode.rightBracket, modifiers: leader),
            "third.right": HotkeyBinding(keyCode: KeyCode.backslash, modifiers: leader),
            "profile.cycle": HotkeyBinding(keyCode: KeyCode.ansiP, modifiers: leader),
            "display.next": HotkeyBinding(keyCode: KeyCode.ansiN, modifiers: leader),
            "sixth.1": HotkeyBinding(keyCode: KeyCode.ansiOne, modifiers: leaderShift),
            "sixth.2": HotkeyBinding(keyCode: KeyCode.ansiTwo, modifiers: leaderShift),
            "sixth.3": HotkeyBinding(keyCode: KeyCode.ansiThree, modifiers: leaderShift),
            "sixth.4": HotkeyBinding(keyCode: KeyCode.ansiFour, modifiers: leaderShift),
            "sixth.5": HotkeyBinding(keyCode: KeyCode.ansiFive, modifiers: leaderShift),
            "sixth.6": HotkeyBinding(keyCode: KeyCode.ansiSix, modifiers: leaderShift),
        ]
    }()
}
