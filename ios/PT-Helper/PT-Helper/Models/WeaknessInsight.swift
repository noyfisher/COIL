import Foundation

/// Represents a detected pattern of under-worked or consistently skipped muscle groups
/// across recent workout sessions.
struct WeaknessInsight: Codable, Identifiable {
    var id: UUID = UUID()
    /// Human-readable muscle group name (e.g. "Hip Flexors", "Core", "Glutes")
    var muscleGroup: String
    /// The `targetArea` value from `RehabExercise` that maps to this group
    var targetAreaKey: String
    /// 0.0–1.0 — proportion of sessions where this muscle group was skipped
    var skipRate: Double
    /// Number of sessions analyzed to compute this insight
    var sessionsAnalyzed: Int
    /// Forward-looking injury risk linked to this blind spot
    var linkedRisk: String
    /// Short actionable recommendation for the user
    var recommendation: String
    /// Date this insight was generated
    var generatedDate: Date = Date()

    // MARK: - Computed

    var skipRatePercent: Int { Int(skipRate * 100) }

    var severityLabel: String {
        switch skipRate {
        case 0.7...: return "High"
        case 0.5..<0.7: return "Moderate"
        default: return "Low"
        }
    }

    var severityColor: String {
        switch skipRate {
        case 0.7...: return "danger"
        case 0.5..<0.7: return "warning"
        default: return "accent"
        }
    }

    var displayIcon: String {
        let lower = muscleGroup.lowercased()
        if lower.contains("hip") || lower.contains("glute") { return "figure.stand" }
        if lower.contains("core") || lower.contains("abdom") { return "figure.core.training" }
        if lower.contains("shoulder") || lower.contains("rotator") { return "figure.arms.open" }
        if lower.contains("hamstring") || lower.contains("calf") || lower.contains("quad") { return "figure.walk" }
        if lower.contains("back") || lower.contains("thoracic") { return "figure.flexibility" }
        if lower.contains("wrist") || lower.contains("forearm") { return "figure.boxing" }
        if lower.contains("neck") || lower.contains("cervical") { return "figure.seated.side" }
        return "figure.mixed.cardio"
    }
}
