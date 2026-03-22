import Foundation
import SwiftUI

@MainActor
class InjuryAnalysisViewModel: ObservableObject {
    @Published var assessments: [PainAssessment?]
    @Published var currentRegionIndex: Int = 0
    @Published var analysisResult: AnalysisResult?
    @Published var validationWarnings: [ValidationWarning] = []
    @Published var redFlagAlerts: [ValidationWarning] = []
    @Published var isAnalyzing: Bool = false
    @Published var analysisError: String? = nil
    @Published var showAnalyzingScreen: Bool = false

    let userProfile: UserProfile
    let selectedRegions: [BodyRegion]
    private let apiService: ClaudeAPIServiceProtocol
    private var analysisTask: Task<Void, Never>?

    init(userProfile: UserProfile, selectedRegions: [BodyRegion], apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) {
        self.userProfile = userProfile
        self.selectedRegions = selectedRegions
        self.apiService = apiService
        // Pre-allocate one slot per region (nil = not yet filled)
        self.assessments = Array(repeating: nil, count: selectedRegions.count)
    }

    /// Save (or overwrite) the assessment for the current region.
    func saveCurrentAssessment(_ assessment: PainAssessment) {
        guard currentRegionIndex < selectedRegions.count else { return }
        assessments[currentRegionIndex] = assessment
    }

    /// Save and advance to the next region.
    func saveAndAdvance(_ assessment: PainAssessment) {
        saveCurrentAssessment(assessment)
        if currentRegionIndex < selectedRegions.count - 1 {
            currentRegionIndex += 1
        }
    }

    /// Save current and go back.
    func saveAndGoBack(_ assessment: PainAssessment) {
        saveCurrentAssessment(assessment)
        if currentRegionIndex > 0 {
            currentRegionIndex -= 1
        }
    }

    /// Save the last region and trigger async AI analysis.
    func saveAndAnalyze(_ assessment: PainAssessment) {
        saveCurrentAssessment(assessment)
        startAnalysis()
    }

    /// Apply the given assessment's pain data to all regions, then trigger analysis.
    func applyToAllRegionsAndAnalyze(_ template: PainAssessment) {
        for (index, region) in selectedRegions.enumerated() {
            assessments[index] = PainAssessment(
                id: UUID(),
                selectedRegion: region,
                painTypes: template.painTypes,
                customPainDescription: template.customPainDescription,
                painIntensity: template.painIntensity,
                painDurations: template.painDurations,
                painFrequencies: template.painFrequencies,
                painOnsets: template.painOnsets,
                aggravatingFactors: template.aggravatingFactors,
                relievingFactors: template.relievingFactors,
                additionalNotes: template.additionalNotes,
                currentTreatment: template.currentTreatment
            )
        }
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
    }

    /// Reset all analysis state (used when navigating back to body map).
    func resetAnalysisState() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        analysisError = nil
        analysisResult = nil
        showAnalyzingScreen = false
    }

    private func startAnalysis() {
        guard !isAnalyzing else { return }
        let completed = assessments.compactMap { $0 }
        guard !completed.isEmpty else {
            AppLogger.rehab.error("startAnalysis called with no completed assessments")
            SessionLogger.shared.logError(
                NSError(domain: "InjuryAnalysis", code: -1, userInfo: [NSLocalizedDescriptionKey: "No completed assessments"]),
                context: "InjuryAnalysis.startAnalysis"
            )
            return
        }

        // Pre-flight validation logging
        let regionNames = completed.map { $0.selectedRegion.name }
        let missingFields = completed.enumerated().compactMap { (i, a) -> String? in
            var missing: [String] = []
            if a.painTypes.isEmpty { missing.append("painTypes") }
            if a.painDurations.isEmpty { missing.append("painDurations") }
            if a.painFrequencies.isEmpty { missing.append("painFrequencies") }
            if a.painOnsets.isEmpty { missing.append("painOnsets") }
            return missing.isEmpty ? nil : "region[\(i)](\(a.selectedRegion.name)): \(missing.joined(separator: ","))"
        }

        isAnalyzing = true
        analysisError = nil
        showAnalyzingScreen = true

        AppLogger.rehab.info("Starting analysis: \(completed.count) region(s) — \(regionNames.joined(separator: ", "))")
        SessionLogger.shared.log(.loadingStarted, category: .stateChange, message: "Analysis started",
                                  metadata: [
                                    "regionCount": "\(completed.count)",
                                    "regions": regionNames.joined(separator: ", "),
                                    "missingFields": missingFields.isEmpty ? "none" : missingFields.joined(separator: "; ")
                                  ])

        analysisTask = Task {
            do {
                let validated = try await InjuryAnalyzer.analyze(
                    assessments: completed,
                    profile: userProfile,
                    apiService: self.apiService
                )
                guard !Task.isCancelled else {
                    AppLogger.rehab.info("Analysis task was cancelled after completion")
                    return
                }
                self.analysisResult = validated.result
                self.validationWarnings = validated.validation.warnings
                self.redFlagAlerts = validated.redFlagAlerts
                self.isAnalyzing = false

                let conditionNames = validated.result.conditions.map { "\($0.commonName)(\(Int($0.confidence))%)" }
                AppLogger.rehab.info("Analysis completed: \(conditionNames.joined(separator: ", "))")
                SessionLogger.shared.log(.loadingFinished, category: .stateChange, message: "Analysis completed",
                                          metadata: [
                                            "conditionCount": "\(validated.result.conditions.count)",
                                            "conditions": conditionNames.joined(separator: ", "),
                                            "hasRedFlags": "\(!validated.redFlagAlerts.isEmpty)",
                                            "warningCount": "\(validated.validation.warnings.count)",
                                            "appliedFixes": validated.validation.appliedFixes.joined(separator: "; ")
                                          ])
            } catch is CancellationError {
                AppLogger.rehab.info("Analysis task cancelled by user")
                SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Analysis cancelled by user")
            } catch {
                guard !Task.isCancelled else {
                    AppLogger.rehab.info("Analysis task cancelled (error after cancel: \(error.localizedDescription))")
                    return
                }
                self.analysisError = error.localizedDescription
                self.isAnalyzing = false

                AppLogger.rehab.error("Analysis failed: \(error.localizedDescription)")
                SessionLogger.shared.logError(error, context: "InjuryAnalysis.startAnalysis")
            }
        }
    }

    /// The assessment saved for the current region (if any), used to restore form state.
    var currentAssessment: PainAssessment? {
        guard currentRegionIndex < assessments.count else { return nil }
        return assessments[currentRegionIndex]
    }

    var currentRegion: BodyRegion? {
        guard currentRegionIndex < selectedRegions.count else { return nil }
        return selectedRegions[currentRegionIndex]
    }

    var isLastRegion: Bool {
        return currentRegionIndex == selectedRegions.count - 1
    }

    var isFirstRegion: Bool {
        return currentRegionIndex == 0
    }

    var hasMultipleRegions: Bool {
        return selectedRegions.count > 1
    }

    var totalRegions: Int {
        return selectedRegions.count
    }

    var selectedRegionNames: [String] {
        return selectedRegions.map { $0.name }
    }
}
