import Foundation

// MARK: - Tier 3 PR D: Outcome Feedback

/// User's after-the-fact assessment of how accurate the AI analysis turned
/// out to be. Collected ≥7 days after a plan starts so the user has had
/// real-world experience with the recommendations.
///
/// Used downstream by Tier 3B (confidence recalibration) — once we've
/// collected enough samples we can compare the AI's stated confidence
/// against the user-rated accuracy and tune the calibration cap.
public enum OutcomeFeedback: String, Codable, CaseIterable, Identifiable, Sendable {
    case accurate
    case partiallyAccurate = "partially_accurate"
    case inaccurate
    case notApplicable = "not_applicable"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .accurate:           return "Pretty accurate"
        case .partiallyAccurate:  return "Partially accurate"
        case .inaccurate:         return "Not accurate"
        case .notApplicable:      return "Hard to say"
        }
    }

    /// SF Symbol name suitable for the prompt UI.
    public var icon: String {
        switch self {
        case .accurate:           return "hand.thumbsup.fill"
        case .partiallyAccurate:  return "hand.thumbsup"
        case .inaccurate:         return "hand.thumbsdown.fill"
        case .notApplicable:      return "questionmark.circle"
        }
    }
}

/// One record for one rating. Persisted to Firestore at
/// `users/{uid}/analysisOutcomes/{analysisId}` (latest rating wins on
/// conflict — analysisId is the doc id).
public struct AnalysisOutcomeRecord: Codable, Equatable, Sendable {
    public let analysisId: UUID
    public let feedback: OutcomeFeedback
    public let recordedAt: Date
    public let planId: UUID?
    /// How many days the user had been on the plan when they rated. Helps
    /// distinguish "rated after 7 days" from "rated after 60 days" during
    /// recalibration.
    public let planAgeDays: Int?

    public init(
        analysisId: UUID,
        feedback: OutcomeFeedback,
        recordedAt: Date = Date(),
        planId: UUID? = nil,
        planAgeDays: Int? = nil
    ) {
        self.analysisId = analysisId
        self.feedback = feedback
        self.recordedAt = recordedAt
        self.planId = planId
        self.planAgeDays = planAgeDays
    }
}
