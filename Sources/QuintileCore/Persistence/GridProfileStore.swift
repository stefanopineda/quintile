import Foundation

/// Per-display grid configuration: the three profile slots plus which slot is
/// currently active.
public struct DisplayGridConfig: Codable, Equatable, Sendable {
    public var standard: GridProfile
    public var secondary: GridProfile
    public var tertiary: GridProfile
    public var activeSlot: ProfileSlot

    public init(standard: GridProfile, secondary: GridProfile, tertiary: GridProfile,
                activeSlot: ProfileSlot) {
        self.standard = standard
        self.secondary = secondary
        self.tertiary = tertiary
        self.activeSlot = activeSlot
    }

    /// First-connect defaults: all three slots at their built-in profiles,
    /// with `standard` (5×2) active.
    public static var firstRunDefault: DisplayGridConfig {
        DisplayGridConfig(standard: .defaultProfile(for: .standard),
                          secondary: .defaultProfile(for: .secondary),
                          tertiary: .defaultProfile(for: .tertiary),
                          activeSlot: .standard)
    }

    public subscript(slot: ProfileSlot) -> GridProfile {
        get {
            switch slot {
            case .standard: return standard
            case .secondary: return secondary
            case .tertiary: return tertiary
            }
        }
        set {
            switch slot {
            case .standard: standard = newValue
            case .secondary: secondary = newValue
            case .tertiary: tertiary = newValue
            }
        }
    }

    public var activeProfile: GridProfile { self[activeSlot] }
}

/// JSON-file-backed store mapping display identity keys to per-display grid
/// configuration.
///
/// - Unknown identities are auto-assigned the first-run defaults and persisted
///   *immediately* on first access (plan requirement: a new display is usable
///   before any explicit user action).
/// - Entries for disconnected displays are never purged; orphaned configs are
///   kept indefinitely.
/// - Writes are atomic (`.atomic` data write) so a crash mid-save can't leave
///   a truncated file.
/// - Threading: designed for single-threaded use (call from the main actor /
///   one queue). No internal locking is performed.
public final class GridProfileStore {
    /// Default storage directory: `~/Library/Application Support/Quintile`.
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quintile", isDirectory: true)
    }

    /// The on-disk JSON file (`<directory>/profiles.json`).
    public let fileURL: URL

    /// The most recent persistence failure, if any. Mutating APIs are
    /// deliberately non-throwing (a tiling action shouldn't crash over a disk
    /// hiccup); callers that care can inspect this after a mutation.
    public private(set) var lastPersistError: Error?

    private var configs: [String: DisplayGridConfig]

    /// A versioned envelope so the format can evolve without ambiguity.
    private struct Envelope: Codable {
        var version: Int
        var displays: [String: DisplayGridConfig]
    }

    private static let formatVersion = 1

    /// - Parameter directory: storage directory, created if missing.
    ///   Defaults to `~/Library/Application Support/Quintile`; tests inject a
    ///   temp directory. Throws if the directory can't be created or an
    ///   existing store file can't be decoded.
    public init(directory: URL = GridProfileStore.defaultDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("profiles.json", isDirectory: false)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.configs = try JSONDecoder().decode(Envelope.self, from: data).displays
        } else {
            self.configs = [:]
        }
    }

    /// All persisted identity keys (including orphans for displays that are
    /// no longer connected).
    public var knownIdentityKeys: [String] { Array(configs.keys) }

    /// Returns the config for `identity`, auto-assigning and *persisting* the
    /// first-run defaults before returning when the identity is unknown.
    @discardableResult
    public func config(for identity: DisplayIdentity) -> DisplayGridConfig {
        if let existing = configs[identity.key] { return existing }
        let assigned = DisplayGridConfig.firstRunDefault
        configs[identity.key] = assigned
        persist()
        return assigned
    }

    /// Replaces the profile in `slot` for `identity` and persists.
    /// Auto-assigns defaults first if the identity is unknown.
    public func updateProfile(_ profile: GridProfile, slot: ProfileSlot, for identity: DisplayIdentity) {
        var config = configs[identity.key] ?? .firstRunDefault
        config[slot] = profile
        configs[identity.key] = config
        persist()
    }

    /// Advances the active slot (standard → secondary → tertiary → standard),
    /// persists, and returns the new slot. Auto-assigns defaults first if the
    /// identity is unknown.
    @discardableResult
    public func cycleActiveSlot(for identity: DisplayIdentity) -> ProfileSlot {
        var config = configs[identity.key] ?? .firstRunDefault
        config.activeSlot = config.activeSlot.next
        configs[identity.key] = config
        persist()
        return config.activeSlot
    }

    /// The currently active profile for `identity` (auto-assigning defaults
    /// on first access).
    public func activeProfile(for identity: DisplayIdentity) -> GridProfile {
        config(for: identity).activeProfile
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Envelope(version: Self.formatVersion, displays: configs))
            try data.write(to: fileURL, options: .atomic)
            lastPersistError = nil
        } catch {
            lastPersistError = error
            FileHandle.standardError.write(Data("Quintile: failed to persist \(fileURL.path): \(error)\n".utf8))
        }
    }
}
