/// Pure helpers for first-run coach completion (thirds only).
public enum FirstWinDetector {
    public static func isThirdPreset(_ preset: PresetAction) -> Bool {
        switch preset {
        case .thirdLeft, .thirdCenter, .thirdRight: return true
        default: return false
        }
    }

    public static func shouldCompleteCoach(preset: PresetAction, outcome: ActionOutcome) -> Bool {
        isThirdPreset(preset) && outcome == .performed
    }
}
