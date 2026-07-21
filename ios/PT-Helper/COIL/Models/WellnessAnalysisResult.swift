import Foundation

struct WellnessAnalysisResult: Codable, Identifiable {
    let id: UUID
    let assessments: [WellnessAssessment]
    let recommendations: [WellnessRecommendation]
    let overallSummary: String
    let disclaimerText: String
    let generatedDate: Date
    let userProfileSnapshot: UserProfile
}

struct WellnessRecommendation: Codable, Identifiable {
    let id: UUID
    let goalCategory: String
    let title: String
    let currentStateAssessment: String
    let rootCauses: [String]
    let expectedTimeline: String
    let keyInsight: String
    let priorityLevel: String
    let relatedGoals: [String]
}
