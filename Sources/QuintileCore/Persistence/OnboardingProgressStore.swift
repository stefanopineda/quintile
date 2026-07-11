import Foundation

/// First-run teaching progress, orthogonal to Accessibility trust.
public enum CoachProgress: String, Codable, Equatable, Sendable {
    /// Fresh install — offer coach after first grant.
    case neverSeen
    /// Grant happened; waiting for a successful third-tile (or skip).
    case waitingForTry
    /// User completed a third preset successfully.
    case completed
    /// User dismissed coach without a first win.
    case skipped
}

/// Lightweight flag store under Application Support — isolated from
/// `profiles.json` so store quarantine cannot reset teaching progress.
public final class OnboardingProgressStore {
    public static let fileName = "onboarding-progress.json"

    private let fileURL: URL
    private var progress: CoachProgress

    public init(directory: URL = OnboardingProgressStore.defaultDirectory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent(Self.fileName, isDirectory: false)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            progress = decoded.coach
        } else {
            progress = .neverSeen
        }
    }

    /// In-memory store for tests (no disk).
    public init(initial: CoachProgress) {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quintile-onboarding-\(UUID().uuidString).json")
        progress = initial
    }

    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Quintile", isDirectory: true)
    }

    public var coach: CoachProgress { progress }

    public func setCoach(_ value: CoachProgress) {
        progress = value
        persist()
    }

    /// Move neverSeen → waitingForTry once when first grant happens.
    public func markWaitingIfNeeded() {
        if progress == .neverSeen {
            setCoach(.waitingForTry)
        }
    }

    public func markCompleted() {
        setCoach(.completed)
    }

    public func markSkipped() {
        if progress != .completed {
            setCoach(.skipped)
        }
    }

    /// Demo / automated tour: never block on interactive coach.
    public func suppressForDemo() {
        setCoach(.completed)
    }

    private struct Payload: Codable {
        var coach: CoachProgress
    }

    private func persist() {
        let payload = Payload(coach: progress)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
