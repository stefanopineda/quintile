import Foundation
import QuintileCore

func onboardingProgressTests(_ t: TestHarness) {
    t.suite("OnboardingProgressStore") { t in
        t.test("default is neverSeen") {
            let store = OnboardingProgressStore(initial: .neverSeen)
            t.expectEqual(store.coach, .neverSeen)
        }

        t.test("markWaitingIfNeeded only from neverSeen") {
            let store = OnboardingProgressStore(initial: .neverSeen)
            store.markWaitingIfNeeded()
            t.expectEqual(store.coach, .waitingForTry)
            store.markWaitingIfNeeded()
            t.expectEqual(store.coach, .waitingForTry)
        }

        t.test("completed persists across disk reload") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("quintile-onboarding-test-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            let a = try! OnboardingProgressStore(directory: dir)
            t.expectEqual(a.coach, .neverSeen)
            a.markWaitingIfNeeded()
            a.markCompleted()
            t.expectEqual(a.coach, .completed)

            let b = try! OnboardingProgressStore(directory: dir)
            t.expectEqual(b.coach, .completed)
        }

        t.test("skip does not overwrite completed") {
            let store = OnboardingProgressStore(initial: .completed)
            store.markSkipped()
            t.expectEqual(store.coach, .completed)
        }

        t.test("skip from waiting") {
            let store = OnboardingProgressStore(initial: .waitingForTry)
            store.markSkipped()
            t.expectEqual(store.coach, .skipped)
        }

        t.test("suppressForDemo marks completed") {
            let store = OnboardingProgressStore(initial: .neverSeen)
            store.suppressForDemo()
            t.expectEqual(store.coach, .completed)
        }

        t.test("third-win recognition helper matches only thirds") {
            t.expect(FirstWinDetector.isThirdPreset(.thirdLeft))
            t.expect(FirstWinDetector.isThirdPreset(.thirdCenter))
            t.expect(FirstWinDetector.isThirdPreset(.thirdRight))
            t.expect(!FirstWinDetector.isThirdPreset(.quadrant1))
            t.expect(!FirstWinDetector.isThirdPreset(.sixth1))
        }

        t.test("first win only on performed third") {
            t.expect(FirstWinDetector.shouldCompleteCoach(
                preset: .thirdLeft, outcome: .performed))
            t.expect(!FirstWinDetector.shouldCompleteCoach(
                preset: .thirdLeft, outcome: .noFocusedWindow))
            t.expect(!FirstWinDetector.shouldCompleteCoach(
                preset: .quadrant1, outcome: .performed))
        }
    }
}
