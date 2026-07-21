import Foundation

/// AI-generated weekly recovery digest parsed from the `recovery_insights` API response.
struct RecoveryInsight: Codable, Identifiable {
    let id: UUID
    let headline: String
    let summary: String
    let painAnalysis: PainAnalysis
    let adherenceAnalysis: AdherenceAnalysis
    let keyWins: [String]
    let focusAreas: [String]
    let recommendations: [Recommendation]
    let generatedDate: Date

    struct PainAnalysis: Codable {
        let trendDirection: String     // "improving" | "stable" | "worsening"
        let trendDescription: String
        let averagePain: Double
        let regionBreakdown: [RegionPainSummary]?
    }

    struct RegionPainSummary: Codable {
        let region: String
        let trend: String              // "improving" | "stable" | "worsening"
        let averagePain: Double
    }

    struct AdherenceAnalysis: Codable {
        let score: Int                 // 0-100
        let sessionsCompleted: Int
        let sessionsExpected: Int
        let description: String
    }

    struct Recommendation: Codable {
        let icon: String               // SF Symbol name
        let title: String
        let description: String
    }
}
