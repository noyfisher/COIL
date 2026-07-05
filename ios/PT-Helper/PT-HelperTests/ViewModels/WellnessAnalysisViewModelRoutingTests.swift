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
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNotNil(vm.analysisResult, "Benign goals should produce a normal analysis result")
        XCTAssertNil(vm.emergencyMessages, "Benign goals must not trigger the emergency path")
        XCTAssertFalse(vm.isAnalyzing)
    }
}
