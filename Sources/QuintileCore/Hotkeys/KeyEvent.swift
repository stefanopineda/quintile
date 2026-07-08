import CoreGraphics // CGKeyCode only — no event-tap machinery in this file.

/// Pure keyboard-event model (U5). Everything in this file is plain value
/// types so hotkey dispatch is unit-testable without a real `CGEventTap`.

/// Modifier keys as an OptionSet. `fn` is first-class because the
/// Fn+Ctrl+Arrow takeover spike (SystemShortcutBridge) needs to distinguish
/// physical-fn chords from plain arrow presses.
public struct KeyModifiers: OptionSet, Hashable, Codable, CustomStringConvertible {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = KeyModifiers(rawValue: 1 << 0)
    public static let option  = KeyModifiers(rawValue: 1 << 1)
    public static let shift   = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let fn      = KeyModifiers(rawValue: 1 << 4)

    /// Symbols in conventional macOS display order (fn ⌃ ⌥ ⇧ ⌘).
    public var description: String {
        var parts: [String] = []
        if contains(.fn) { parts.append("fn") }
        if contains(.control) { parts.append("⌃") }
        if contains(.option) { parts.append("⌥") }
        if contains(.shift) { parts.append("⇧") }
        if contains(.command) { parts.append("⌘") }
        return parts.joined()
    }
}

/// A single key press or release with its modifier chord.
public struct KeyEvent: Hashable {
    public var keyCode: CGKeyCode
    public var modifiers: KeyModifiers
    public var isKeyDown: Bool

    public init(keyCode: CGKeyCode, modifiers: KeyModifiers, isKeyDown: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isKeyDown = isKeyDown
    }
}

/// Hardware key codes used by Quintile's bindings (Carbon `kVK_*` values,
/// ANSI layout). Kept as a caseless namespace so callers write
/// `KeyCode.leftArrow` without an exhaustive enum.
public enum KeyCode {
    public static let ansiOne: CGKeyCode = 18
    public static let ansiTwo: CGKeyCode = 19
    public static let ansiThree: CGKeyCode = 20
    public static let ansiFour: CGKeyCode = 21
    public static let ansiFive: CGKeyCode = 23
    public static let ansiSix: CGKeyCode = 22
    public static let ansiG: CGKeyCode = 5
    public static let ansiP: CGKeyCode = 35
    public static let ansiN: CGKeyCode = 45
    public static let leftBracket: CGKeyCode = 33
    public static let rightBracket: CGKeyCode = 30
    public static let backslash: CGKeyCode = 42
    public static let leftArrow: CGKeyCode = 123
    public static let rightArrow: CGKeyCode = 124
    public static let downArrow: CGKeyCode = 125
    public static let upArrow: CGKeyCode = 126
    /// Physical fn key (`kVK_Function`) — seen only on `flagsChanged`.
    public static let function: CGKeyCode = 63
}

/// A registrable shortcut: exact modifier chord + key. Codable so U8's
/// preferences can persist user-customized bindings; `description` feeds the
/// shortcuts reference panel.
public struct HotkeyBinding: Hashable, Codable, CustomStringConvertible {
    public var keyCode: CGKeyCode
    public var modifiers: KeyModifiers

    public init(keyCode: CGKeyCode, modifiers: KeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Human-readable form, e.g. "⌃⌥→" or "fn⌃←".
    public var description: String {
        "\(modifiers)\(HotkeyBinding.keyName(for: keyCode))"
    }

    private static let keyNames: [CGKeyCode: String] = [
        KeyCode.ansiOne: "1", KeyCode.ansiTwo: "2", KeyCode.ansiThree: "3",
        KeyCode.ansiFour: "4", KeyCode.ansiFive: "5", KeyCode.ansiSix: "6",
        KeyCode.ansiG: "G", KeyCode.ansiP: "P", KeyCode.ansiN: "N",
        KeyCode.leftBracket: "[", KeyCode.rightBracket: "]", KeyCode.backslash: "\\",
        KeyCode.leftArrow: "←", KeyCode.rightArrow: "→",
        KeyCode.downArrow: "↓", KeyCode.upArrow: "↑",
    ]

    static func keyName(for keyCode: CGKeyCode) -> String {
        keyNames[keyCode] ?? "key(\(keyCode))"
    }
}
