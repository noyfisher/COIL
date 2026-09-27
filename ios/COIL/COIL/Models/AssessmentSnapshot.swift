import Foundation

/// A snapshot of the user's pain levels at a specific point in their plan.
struct AssessmentSnapshot: Codable, Identifiable {
    let id: UUID
    let planId: UUID
    let assessmentType: AssessmentType
    let date: Date
    let regionPainLevels: [String: Double]
    let overallPain: Double

    enum AssessmentType: String, Codable {
        case initial
        case midpoint
        case completion
    }
}
