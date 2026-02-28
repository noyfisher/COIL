import Foundation
import SwiftUI

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
    private var analysisTask: Task<Void, Never>?

    init(userProfile: UserProfile, selectedRegions: [BodyRegion]) {
        self.userProfile = userProfile
        self.selectedRegions = selectedRegions
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
        let completed = assessments.compactMap { $0 }
        guard !completed.isEmpty else { return }

        isAnalyzing = true
        analysisError = nil
        showAnalyzingScreen = true

        analysisTask = Task { @MainActor in
            do {
                let validated = try await InjuryAnalyzer.analyze(
                    assessments: completed,
                    profile: userProfile
                )
                guard !Task.isCancelled else { return }
                self.analysisResult = validated.result
                self.validationWarnings = validated.validation.warnings
                self.redFlagAlerts = validated.redFlagAlerts
                self.isAnalyzing = false
            } catch {
                guard !Task.isCancelled else { return }
                self.analysisError = error.localizedDescription
                self.isAnalyzing = false
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

    var totalRegions: Int {
        return selectedRegions.count
    }

    var selectedRegionNames: [String] {
        return selectedRegions.map { $0.name }
    }
}
