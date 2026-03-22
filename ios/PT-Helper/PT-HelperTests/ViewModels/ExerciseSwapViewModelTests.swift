import XCTest
@testable import PT_Helper

@MainActor
final class ExerciseSwapViewModelTests: XCTestCase {

    private var mockAPI: MockClaudeAPIService!
    private var exercise: RehabExercise!
    private var plan: RehabPlan!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
        exercise = TestFixtures.makeExercise(name: "Wall Sits", targetArea: "Knee")
        plan = TestFixtures.makePlan(
            conditions: ["test knee pain"],
            exercises: [
                exercise,
                TestFixtures.makeExercise(name: "Quad Sets", targetArea: "Knee"),
                TestFixtures.makeExercise(name: "Calf Raises", targetArea: "Calf")
            ]
        )
    }

    // MARK: - SwapReason

    func testSwapReason_allCasesHaveDisplayNameAndIcon() {
        for reason in SwapReason.allCases {
            XCTAssertFalse(reason.displayName.isEmpty, "\(reason) missing displayName")
            XCTAssertFalse(reason.icon.isEmpty, "\(reason) missing icon")
        }
    }

    // MARK: - Fetch Substitutes

    func testFetchSubstitutes_success_parsesExercises() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = TestFixtures.makeSubstituteResponseJSON(count: 2)

        vm.selectedReason = .tooPainful
        await vm.fetchSubstitutes()

        XCTAssertEqual(vm.substitutes.count, 2)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.substitutes[0].name, "Substitute Exercise 1")
        XCTAssertEqual(vm.substitutes[0].targetArea, "Knee")
        XCTAssertEqual(vm.substitutes[0].difficulty, .beginner)
    }

    func testFetchSubstitutes_apiError_setsErrorMessage() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.errorToThrow = ClaudeAPIError.networkError(NSError(domain: "test", code: -1))

        vm.selectedReason = .tooDifficult
        await vm.fetchSubstitutes()

        XCTAssertTrue(vm.substitutes.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNotNil(vm.error)
    }

    func testFetchSubstitutes_invalidJSON_setsError() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = "this is not valid json at all"

        vm.selectedReason = .noEquipment
        await vm.fetchSubstitutes()

        XCTAssertTrue(vm.substitutes.isEmpty)
        XCTAssertNotNil(vm.error)
    }

    func testFetchSubstitutes_noReason_doesNothing() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        // selectedReason is nil
        await vm.fetchSubstitutes()

        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.substitutes.isEmpty)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0)
    }

    func testFetchSubstitutes_usesCorrectRequestType() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = TestFixtures.makeSubstituteResponseJSON()

        vm.selectedReason = .tooPainful
        await vm.fetchSubstitutes()

        XCTAssertEqual(mockAPI.lastRequestType, .exercise_substitute)
    }

    // MARK: - User Message Construction

    func testBuildUserMessage_includesExerciseDetails() {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        vm.selectedReason = .tooPainful

        let message = vm.buildUserMessage()

        XCTAssertTrue(message.contains("Wall Sits"), "Should include exercise name")
        XCTAssertTrue(message.contains("Knee"), "Should include target area")
        XCTAssertTrue(message.contains("Too Painful"), "Should include swap reason")
    }

    func testBuildUserMessage_includesOtherExercises() {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        vm.selectedReason = .noEquipment

        let message = vm.buildUserMessage()

        XCTAssertTrue(message.contains("Quad Sets"), "Should list other exercises")
        XCTAssertTrue(message.contains("Calf Raises"), "Should list other exercises")
        XCTAssertFalse(message.contains("Wall Sits, "), "Should NOT list the exercise being replaced in others")
    }

    func testBuildUserMessage_includesConditions() {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        vm.selectedReason = .other

        let message = vm.buildUserMessage()

        XCTAssertTrue(message.contains("test knee pain"), "Should include plan conditions")
    }

    // MARK: - Select Substitute

    func testSelectSubstitute_replacesExerciseInPlan() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = TestFixtures.makeSubstituteResponseJSON(count: 1)
        vm.selectedReason = .tooPainful
        await vm.fetchSubstitutes()

        let substitute = vm.substitutes[0]
        let mockSavedPlansVM = SavedPlansViewModel()
        let updatedPlan = vm.selectSubstitute(substitute, savedPlansVM: mockSavedPlansVM)

        // Find the exercise at the original index
        let replacedExercise = updatedPlan.exercises.first(where: { $0.id == substitute.id })
        XCTAssertNotNil(replacedExercise, "Substitute should be in the updated plan")
        XCTAssertEqual(replacedExercise?.name, "Substitute Exercise 1")
    }

    func testSelectSubstitute_preservesOtherExercises() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = TestFixtures.makeSubstituteResponseJSON(count: 1)
        vm.selectedReason = .tooPainful
        await vm.fetchSubstitutes()

        let substitute = vm.substitutes[0]
        let mockSavedPlansVM = SavedPlansViewModel()
        let updatedPlan = vm.selectSubstitute(substitute, savedPlansVM: mockSavedPlansVM)

        // Other exercises should be unchanged
        XCTAssertEqual(updatedPlan.exercises.count, 3)
        XCTAssertEqual(updatedPlan.exercises[1].name, "Quad Sets")
        XCTAssertEqual(updatedPlan.exercises[2].name, "Calf Raises")
    }

    func testSelectSubstitute_updatesLastModifiedDate() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = TestFixtures.makeSubstituteResponseJSON(count: 1)
        vm.selectedReason = .tooPainful
        await vm.fetchSubstitutes()

        let substitute = vm.substitutes[0]
        let mockSavedPlansVM = SavedPlansViewModel()
        let updatedPlan = vm.selectSubstitute(substitute, savedPlansVM: mockSavedPlansVM)

        XCTAssertNotNil(updatedPlan.lastModifiedDate)
        // Should be very recent (within last second)
        let elapsed = Date().timeIntervalSince(updatedPlan.lastModifiedDate!)
        XCTAssertLessThan(elapsed, 2.0)
    }

    // MARK: - WhyItHelps

    func testFetchSubstitutes_parsesWhyItHelps() async {
        let vm = ExerciseSwapViewModel(exercise: exercise, plan: plan, apiService: mockAPI)
        mockAPI.responseToReturn = TestFixtures.makeSubstituteResponseJSON(count: 1)

        vm.selectedReason = .tooPainful
        await vm.fetchSubstitutes()

        XCTAssertEqual(vm.substitutes.count, 1)
        let sub = vm.substitutes[0]
        let reason = vm.substituteReasons[sub.id]
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason!.contains("same muscles"))
    }
}
