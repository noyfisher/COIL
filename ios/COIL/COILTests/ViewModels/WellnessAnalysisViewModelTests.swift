import XCTest
@testable import COIL

@MainActor
final class WellnessAnalysisViewModelTests: XCTestCase {
    private var mockAPI: MockClaudeAPIService!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
    }

    private func makeVM(goalCount: Int = 2) -> WellnessAnalysisViewModel {
        let goals = (0..<goalCount).map { i in
            TestFixtures.makeGoalSelection(category: GoalCategory.allCases[i])
        }
        return WellnessAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedGoals: goals,
            apiService: mockAPI
        )
    }

    // MARK: - Init State

    func testInit_assessmentsPreAllocated_matchGoalCount() {
        let vm = makeVM(goalCount: 3)
        XCTAssertEqual(vm.assessments.count, 3)
        XCTAssertTrue(vm.assessments.allSatisfy { $0 == nil })
    }

    func testInit_currentGoalIndex_isZero() {
        let vm = makeVM()
        XCTAssertEqual(vm.currentGoalIndex, 0)
    }

    // MARK: - Save / Navigate

    func testSaveCurrentAssessment_storesAtCurrentIndex() {
        let vm = makeVM()
        let assessment = TestFixtures.makeWellnessAssessment(goalCategory: .improvePosture)
        vm.saveCurrentAssessment(assessment)
        XCTAssertNotNil(vm.assessments[0])
        XCTAssertEqual(vm.assessments[0]?.goalCategory, .improvePosture)
    }

    func testSaveAndAdvance_advancesIndex() {
        let vm = makeVM(goalCount: 3)
        let assessment = TestFixtures.makeWellnessAssessment()
        vm.saveAndAdvance(assessment)
        XCTAssertEqual(vm.currentGoalIndex, 1)
        XCTAssertNotNil(vm.assessments[0])
    }

    func testSaveAndAdvance_atLastGoal_doesNotExceedBounds() {
        let vm = makeVM(goalCount: 2)
        vm.currentGoalIndex = 1 // already at last
        let assessment = TestFixtures.makeWellnessAssessment()
        vm.saveAndAdvance(assessment)
        XCTAssertEqual(vm.currentGoalIndex, 1, "Should not advance past last goal")
    }

    func testSaveAndGoBack_decrementsIndex() {
        let vm = makeVM(goalCount: 3)
        vm.currentGoalIndex = 2
        let assessment = TestFixtures.makeWellnessAssessment()
        vm.saveAndGoBack(assessment)
        XCTAssertEqual(vm.currentGoalIndex, 1)
    }

    func testSaveAndGoBack_atFirstGoal_staysAtZero() {
        let vm = makeVM()
        let assessment = TestFixtures.makeWellnessAssessment()
        vm.saveAndGoBack(assessment)
        XCTAssertEqual(vm.currentGoalIndex, 0)
    }

    // MARK: - Cancel / Reset

    func testCancelAnalysis_resetsFlags() {
        let vm = makeVM()
        vm.isAnalyzing = true
        vm.analysisError = "some error"
        vm.showAnalyzingScreen = true

        vm.cancelAnalysis()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    func testResetAnalysisState_clearsAllState() {
        let vm = makeVM()
        vm.isAnalyzing = true
        vm.analysisError = "error"
        vm.showAnalyzingScreen = true

        vm.resetAnalysisState()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    // MARK: - Computed Properties

    func testIsLastGoal_singleGoal_true() {
        let vm = makeVM(goalCount: 1)
        XCTAssertTrue(vm.isLastGoal)
    }

    func testIsLastGoal_multipleGoals_falseAtStart_trueAtEnd() {
        let vm = makeVM(goalCount: 3)
        XCTAssertFalse(vm.isLastGoal)
        vm.currentGoalIndex = 2
        XCTAssertTrue(vm.isLastGoal)
    }

    func testIsFirstGoal_atStart_true() {
        let vm = makeVM()
        XCTAssertTrue(vm.isFirstGoal)
        vm.currentGoalIndex = 1
        XCTAssertFalse(vm.isFirstGoal)
    }

    func testHasMultipleGoals_reflectsGoalCount() {
        let singleVM = makeVM(goalCount: 1)
        XCTAssertFalse(singleVM.hasMultipleGoals)

        let multiVM = makeVM(goalCount: 3)
        XCTAssertTrue(multiVM.hasMultipleGoals)
    }

    func testCurrentGoal_returnsCorrectGoalForIndex() {
        let vm = makeVM(goalCount: 3)
        XCTAssertEqual(vm.currentGoal?.category, GoalCategory.allCases[0])
        vm.currentGoalIndex = 2
        XCTAssertEqual(vm.currentGoal?.category, GoalCategory.allCases[2])
    }

    func testSelectedGoalNames_returnsDisplayNames() {
        let goals = [
            TestFixtures.makeGoalSelection(category: .improvePosture),
            TestFixtures.makeGoalSelection(category: .manageStress)
        ]
        let vm = WellnessAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedGoals: goals,
            apiService: mockAPI
        )
        XCTAssertEqual(vm.selectedGoalNames, ["Improve Posture", "Manage Stress"])
    }

    // MARK: - currentAssessment

    func testCurrentAssessment_returnsNilBeforeSave() {
        let vm = makeVM()
        XCTAssertNil(vm.currentAssessment)
    }

    func testCurrentAssessment_returnsSavedAssessment() {
        let vm = makeVM()
        let assessment = TestFixtures.makeWellnessAssessment(motivationLevel: 9)
        vm.saveCurrentAssessment(assessment)
        XCTAssertEqual(vm.currentAssessment?.motivationLevel, 9)
    }

    // MARK: - Out-of-Bounds Guards

    func testSaveCurrentAssessment_indexOutOfBounds_isNoOp() {
        let vm = makeVM(goalCount: 2)
        vm.currentGoalIndex = 5 // exceeds bounds
        vm.saveCurrentAssessment(TestFixtures.makeWellnessAssessment())
        XCTAssertTrue(vm.assessments.allSatisfy { $0 == nil },
                      "Out-of-bounds save must not mutate assessments")
    }

    // MARK: - saveAndAnalyze

    func testSaveAndAnalyze_savesAndTriggersAnalyzingScreen() {
        let vm = makeVM(goalCount: 1)
        let assessment = TestFixtures.makeWellnessAssessment()
        vm.saveAndAnalyze(assessment)
        XCTAssertNotNil(vm.assessments[0])
        XCTAssertTrue(vm.showAnalyzingScreen)
    }

    // MARK: - WS8-01: Offline fail-fast

    func testStartAnalysis_offline_failsFastWithoutAPICall() async {
        _ = NetworkMonitor.shared
        await Task.yield()
        NetworkMonitor.shared.isConnected = false
        defer { NetworkMonitor.shared.isConnected = true }

        let vm = makeVM(goalCount: 1)
        let assessment = TestFixtures.makeWellnessAssessment()
        vm.saveAndAnalyze(assessment)

        XCTAssertEqual(vm.analysisError, "You're offline. Connect to the internet to run your wellness assessment, then tap Try Again.")
        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertTrue(vm.showAnalyzingScreen)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0)
    }
}
