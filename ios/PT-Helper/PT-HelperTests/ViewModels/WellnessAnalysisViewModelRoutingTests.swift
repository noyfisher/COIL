import XCTest
@testable import PT_Helper

/// Tests for the wellness emergency red-flag routing added in the compliance
/// remediation (PR-2, WP-2.1 / WP-2.2). The view model sets EITHER `analysisResult`
/// OR `emergencyMessages`, never both, so the detail view's two `onChange`s cannot race.
@MainActor
final class WellnessAnalysisViewModelRoutingTests: XCTestCase {
    private var mockAPI: MockClaudeAPIService!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
    }

    private func makeVM(goals: [GoalSelection]) -> WellnessAnalysisViewModel {
        WellnessAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedGoals: goals,
            apiService: mockAPI
        )
    }

    // MARK: - WP-2.1 — Benign routing

    func testStartAnalysis_BenignGoals_SetsResultNotEmergency() async throws {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()
        let vm = makeVM(goals: [TestFixtures.makeGoalSelection(category: .improvePosture)])

        vm.saveAndAnalyze(TestFixtures.makeWellnessAssessment(goalCategory: .improvePosture))
        await vm.analysisTask?.value

        XCTAssertNotNil(vm.analysisResult, "Benign goals should produce a normal analysis result")
        XCTAssertNil(vm.emergencyMessages, "Benign goals must not trigger the emergency path")
        XCTAssertFalse(vm.isAnalyzing)
    }

    // MARK: - WP-2.2 — Emergency pre-screen (no API call for 911-pattern free text)

    /// Builds a wellness assessment whose free-text `specificContext` carries a
    /// region-agnostic emergency pattern (stroke: sudden weakness / numbness / one side).
    /// Region-scoped patterns (e.g. cardiac, which needs a "chest" region) cannot fire
    /// from the wellness free-text entry point — see `MedicalRedFlagDetector.check(symptomStrings:)`.
    private func makeEmergencyAssessment() -> WellnessAssessment {
        WellnessAssessment(
            id: UUID(),
            goalCategory: .improvePosture,
            customGoalText: nil,
            impactLevel: .moderate,
            motivationLevel: 7,
            duration: .fewMonths,
            timeOfDay: [.morning],
            dailyActivitiesAffected: [],
            currentHabits: [],
            priorAttempts: [.stretching],
            commitmentLevel: .fifteenMin,
            specificContext: "sudden weakness and numbness on one side of my body",
            additionalNotes: nil
        )
    }

    func testStartAnalysis_EmergencyFreeText_MakesNoAPICallAndSetsEmergencyMessages() {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()
        let vm = makeVM(goals: [TestFixtures.makeGoalSelection(category: .improvePosture)])

        vm.saveAndAnalyze(makeEmergencyAssessment())

        XCTAssertEqual(mockAPI.sendMessageCallCount, 0, "911-pattern free text must never leave the device")
        XCTAssertNotNil(vm.emergencyMessages, "Emergency messages should be set for routing")
        XCTAssertFalse(vm.emergencyMessages?.isEmpty ?? true)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.isAnalyzing)
    }

    // MARK: - WP-2.2 — redFlagScreeningStrings coverage

    func testRedFlagScreeningStrings_IncludesAllFreeTextFields() {
        let assessment = WellnessAssessment(
            id: UUID(),
            goalCategory: .custom,
            customGoalText: "CUSTOM_GOAL",
            impactLevel: .moderate,
            motivationLevel: 7,
            duration: .fewMonths,
            timeOfDay: [.morning],
            dailyActivitiesAffected: ["ACTIVITY_ONE", "ACTIVITY_TWO"],
            currentHabits: ["HABIT_ONE"],
            priorAttempts: [.stretching],
            commitmentLevel: .fifteenMin,
            specificContext: "SPECIFIC_CONTEXT",
            additionalNotes: "ADDITIONAL_NOTES"
        )

        let strings = assessment.redFlagScreeningStrings

        XCTAssertTrue(strings.contains("ACTIVITY_ONE"))
        XCTAssertTrue(strings.contains("ACTIVITY_TWO"))
        XCTAssertTrue(strings.contains("HABIT_ONE"))
        XCTAssertTrue(strings.contains("CUSTOM_GOAL"))
        XCTAssertTrue(strings.contains("SPECIFIC_CONTEXT"))
        XCTAssertTrue(strings.contains("ADDITIONAL_NOTES"))
    }

    func testRedFlagScreeningStrings_OmitsEmptyOptionalFields() {
        let assessment = WellnessAssessment(
            id: UUID(),
            goalCategory: .improvePosture,
            customGoalText: nil,
            impactLevel: .moderate,
            motivationLevel: 7,
            duration: .fewMonths,
            timeOfDay: [.morning],
            dailyActivitiesAffected: ["ONLY_ACTIVITY"],
            currentHabits: [],
            priorAttempts: [.stretching],
            commitmentLevel: .fifteenMin,
            specificContext: nil,
            additionalNotes: nil
        )

        XCTAssertEqual(assessment.redFlagScreeningStrings, ["ONLY_ACTIVITY"])
    }
}
