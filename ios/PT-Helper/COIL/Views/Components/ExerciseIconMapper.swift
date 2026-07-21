import Foundation

/// Maps exercise categories to the most descriptive SF Symbol available.
/// Falls back to the exercise's existing `demonstrationIcon` if no category is set.
enum ExerciseIconMapper {

    static func icon(for exercise: RehabExercise) -> String {
        if let category = exercise.exerciseCategory?.lowercased() {
            switch category {
            case "stretch", "flexibility":
                return "figure.flexibility"
            case "strength", "strengthening":
                return "figure.strengthtraining.traditional"
            case "balance", "proprioception":
                return "figure.stand"
            case "cardio", "endurance":
                return "figure.run"
            case "mobility", "range_of_motion":
                return "figure.cooldown"
            case "core", "stabilization":
                return "figure.core.training"
            case "yoga", "mindfulness":
                return "figure.yoga"
            case "aquatic", "pool":
                return "figure.pool.swim"
            case "stair", "step":
                return "figure.stairs"
            case "walking", "gait":
                return "figure.walk"
            case "cycling":
                return "figure.outdoor.cycle"
            case "seated":
                return "figure.seated.side"
            case "lying", "supine", "prone":
                return "figure.roll"
            case "standing":
                return "figure.stand"
            case "resistance_band", "band":
                return "figure.mixed.cardio"
            default:
                break
            }
        }

        // Fall back to the AI-provided demonstrationIcon
        return exercise.demonstrationIcon
    }
}
