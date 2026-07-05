import Foundation
import SwiftUI

@MainActor
class WellnessAnalysisViewModel: ObservableObject {
    @Published var assessments: [WellnessAssessment?]
    @Published var currentGoalIndex: Int = 0
    @Published var analysisResult: WellnessAnalysisResult?
    @Published var isAnalyzing: Bool = false
    @Published var analysisError: String? = nil
    @Published var showAnalyzingScreen: Bool = false

    // MARK: - Tier 1 validation surface
    /// Validation warnings from `WellnessAnalysisValidator`. Published so views can
    /// route on `worstSeverity` (same pattern as `InjuryAnalysisViewModel.redFlagAlerts`).
    @Published var validationWarnings: [ValidationWarning] = []
    @Published var emergencyMessages: [String]? = nil
    /// Convenience: highest severity across `validationWarnings`, or `.info` if none.
    var worstSeverity: ValidationSeverity {
        validationWarnings.map(\.severity).max() ?? .info
    }

    let userProfile: UserProfile
    let selectedGoals: [GoalSelection]
    private let apiService: ClaudeAPIServiceProtocol
    private var analysisTask: Task<Void, Never>?

    init(userProfile: UserProfile, selectedGoals: [GoalSelection], apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) {
        self.userProfile = userProfile
        self.selectedGoals = selectedGoals
        self.apiService = apiService
        // Pre-allocate one slot per goal (nil = not yet filled)
        self.assessments = Array(repeating: nil, count: selectedGoals.count)
    }

    /// Save (or overwrite) the assessment for the current goal.
    func saveCurrentAssessment(_ assessment: WellnessAssessment) {
        guard currentGoalIndex < selectedGoals.count else { return }
        assessments[currentGoalIndex] = assessment
    }

    /// Save and advance to the next goal.
    func saveAndAdvance(_ assessment: WellnessAssessment) {
        saveCurrentAssessment(assessment)
        if currentGoalIndex < selectedGoals.count - 1 {
            currentGoalIndex += 1
        }
    }

    /// Save current and go back.
    func saveAndGoBack(_ assessment: WellnessAssessment) {
        saveCurrentAssessment(assessment)
        if currentGoalIndex > 0 {
            currentGoalIndex -= 1
        }
    }

    /// Save the last goal and trigger async AI analysis.
    func saveAndAnalyze(_ assessment: WellnessAssessment) {
        saveCurrentAssessment(assessment)
        startAnalysis()
    }

    /// Retry analysis after an error.
    func retryAnalysis() {
        startAnalysis()
    }

    /// Cancel an in-flight analysis and go back to the assessment.
    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisError = nil
        showAnalyzingScreen = false
        emergencyMessages = nil
        validationWarnings = []
    }

    /// Reset all analysis state.
    func resetAnalysisState() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisError = nil
        analysisResult = nil
        showAnalyzingScreen = false
        emergencyMessages = nil
        validationWarnings = []
    }

    private func startAnalysis() {
        guard !isAnalyzing else { return }
        let completed = assessments.compactMap { $0 }
        guard !completed.isEmpty else {
            AppLogger.rehab.error("startAnalysis called with no completed wellness assessments")
            SessionLogger.shared.logError(
                NSError(domain: "WellnessAnalysis", code: -1, userInfo: [NSLocalizedDescriptionKey: "No completed assessments"]),
                context: "WellnessAnalysis.startAnalysis"
            )
            return
        }

        let goalNames = completed.map { $0.goalCategory.displayName }

        isAnalyzing = true
        analysisError = nil
        showAnalyzingScreen = true

        AnalyticsService.shared.log(.assessmentCompleted, parameters: ["goal_count": completed.count, "type": "wellness"])
        AppLogger.rehab.info("Starting wellness analysis: \(completed.count) goal(s) — \(goalNames.joined(separator: ", "))")
        SessionLogger.shared.log(.loadingStarted, category: .stateChange, message: "Wellness analysis started",
                                  metadata: [
                                    "goalCount": "\(completed.count)",
                                    "goals": goalNames.joined(separator: ", ")
                                  ])

        analysisTask = Task {
            do {
                let validated = try await WellnessAnalyzer.analyze(
                    assessments: completed,
                    profile: userProfile,
                    apiService: self.apiService
                )
                guard !Task.isCancelled else {
                    AppLogger.rehab.info("Wellness analysis task was cancelled after completion")
                    return
                }
                self.validationWarnings = validated.warnings
                if validated.worstSeverity == .emergency {
                    self.emergencyMessages = validated.warnings
                        .filter { $0.severity == .emergency }.map(\.message)
                } else {
                    self.analysisResult = validated.result
                }
                self.isAnalyzing = false

                AnalyticsService.shared.log(.analysisCompleted, parameters: [
                    "recommendation_count": validated.result.recommendations.count,
                    "type": "wellness",
                    "worst_severity": validated.worstSeverity.rawValue
                ])
                let recTitles = validated.result.recommendations.map { $0.title }
                AppLogger.rehab.info("Wellness analysis completed: \(recTitles.joined(separator: ", "))")
                SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Wellness analysis completed",
                                          metadata: [
                                            "recommendationCount": "\(validated.result.recommendations.count)",
                                            "recommendations": recTitles.joined(separator: ", ")
                                          ])
            } catch is CancellationError {
                AppLogger.rehab.info("Wellness analysis task cancelled by user")
                SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Wellness analysis cancelled by user")
            } catch {
                guard !Task.isCancelled else {
                    AppLogger.rehab.info("Wellness analysis task cancelled (error after cancel: \(error.localizedDescription))")
                    return
                }
                self.analysisError = error.localizedDescription
                self.isAnalyzing = false

                // Tier 1: ai_response_invalid breadcrumb (server Zod rejection).
                if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                    SessionLogger.shared.log(.errorOccurred, category: .api,
                        message: "Wellness analysis rejected by server schema (ai_response_invalid)",
                        metadata: ["error_kind": "ai_response_invalid"])
                }
                AnalyticsService.shared.log(.analysisFailed, parameters: ["error_type": String(describing: type(of: error)), "type": "wellness"])
                AppLogger.rehab.error("Wellness analysis failed: \(error.localizedDescription)")
                SessionLogger.shared.logError(error, context: "WellnessAnalysis.startAnalysis")
            }
        }
    }

    /// The assessment saved for the current goal (if any), used to restore form state.
    var currentAssessment: WellnessAssessment? {
        guard currentGoalIndex < assessments.count else { return nil }
        return assessments[currentGoalIndex]
    }

    var currentGoal: GoalSelection? {
        guard currentGoalIndex < selectedGoals.count else { return nil }
        return selectedGoals[currentGoalIndex]
    }

    var isLastGoal: Bool {
        return currentGoalIndex == selectedGoals.count - 1
    }

    var isFirstGoal: Bool {
        return currentGoalIndex == 0
    }

    var hasMultipleGoals: Bool {
        return selectedGoals.count > 1
    }

    var totalGoals: Int {
        return selectedGoals.count
    }

    var selectedGoalNames: [String] {
        return selectedGoals.map { $0.category.displayName }
    }
}
