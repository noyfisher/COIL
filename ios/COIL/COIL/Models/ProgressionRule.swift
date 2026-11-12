import Foundation

/// Provides progressive overload calculations for rehab plan exercises.
/// Adjusts sets, reps, and difficulty based on the current week within a plan.
enum ProgressionRule {

    /// Adjusted set count based on plan week
    static func adjustedSets(base: Int, week: Int, totalWeeks: Int) -> Int {
        guard totalWeeks > 2 else { return base }

        let progress = Double(week) / Double(totalWeeks)

        switch progress {
        case ..<0.3:
            // Weeks 1-2 range: base values (adaptation phase)
            return base
        case 0.3..<0.6:
            // Mid-plan: +1 set
            return base + 1
        case 0.6..<0.9:
            // Peak: +1 set (maintain)
            return base + 1
        default:
            // Final week: taper back to base
            return base
        }
    }

    /// Adjusted rep string based on plan week (handles "10", "10-12", "30 sec" formats)
    static func adjustedReps(base: String, week: Int, totalWeeks: Int) -> String {
        guard totalWeeks > 2 else { return base }

        let progress = Double(week) / Double(totalWeeks)

        // Try to parse as a simple number
        if let baseNum = Int(base) {
            let adjusted: Int
            switch progress {
            case ..<0.3:
                adjusted = baseNum
            case 0.3..<0.6:
                adjusted = baseNum + 2
            case 0.6..<0.9:
                adjusted = baseNum + 3
            default:
                adjusted = baseNum // taper
            }
            return "\(adjusted)"
        }

        // Handle range format like "10-12"
        let rangeParts = base.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if rangeParts.count == 2 {
            let increment: Int
            switch progress {
            case ..<0.3: increment = 0
            case 0.3..<0.6: increment = 2
            case 0.6..<0.9: increment = 3
            default: increment = 0
            }
            return "\(rangeParts[0] + increment)-\(rangeParts[1] + increment)"
        }

        // Can't parse — return as-is (e.g., "30 sec hold")
        return base
    }

    /// Suggested difficulty progression
    static func adjustedDifficulty(base: RehabExercise.Difficulty, week: Int, totalWeeks: Int) -> RehabExercise.Difficulty {
        guard totalWeeks > 4 else { return base }

        let progress = Double(week) / Double(totalWeeks)

        switch (base, progress) {
        case (.beginner, 0.6...):
            return .intermediate
        case (.intermediate, 0.75...):
            return .advanced
        default:
            return base
        }
    }

    /// Human-readable description of what changed
    static func progressionNote(week: Int, totalWeeks: Int) -> String? {
        guard totalWeeks > 2 else { return nil }

        let progress = Double(week) / Double(totalWeeks)

        switch progress {
        case ..<0.3:
            return "Adaptation phase — focus on form"
        case 0.3..<0.6:
            return "Building phase — volume increasing"
        case 0.6..<0.9:
            return "Peak phase — maintain intensity"
        default:
            return "Taper phase — preparing for re-assessment"
        }
    }
}
