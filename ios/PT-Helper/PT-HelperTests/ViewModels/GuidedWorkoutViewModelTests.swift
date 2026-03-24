import XCTest
@testable import PT_Helper

// MARK: - GuidedWorkoutViewModel Tests

@MainActor
final class GuidedWorkoutViewModelTests: XCTestCase {

    override func tearDown() {
        // Clean up any workout checkpoints saved to UserDefaults during tests
        UserDefaults.standard.removeObject(forKey: "GuidedWorkoutCheckpoint")
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeExercise(
        name: String = "Wall Sits",
        sets: Int = 3,
        restSeconds: Int = 30
    ) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: name, targetArea: "Knee",
            description: "Test exercise", sets: sets, reps: "10",
            restSeconds: restSeconds, difficulty: .beginner,
            demonstrationIcon: "figure.cooldown",
            tips: [], contraindications: []
        )
    }

    private func makePlan(exercises: [RehabExercise]? = nil) -> RehabPlan {
        let defaultExercises = [
            makeExercise(name: "Wall Sits", sets: 2, restSeconds: 30),
            makeExercise(name: "Quad Sets", sets: 3, restSeconds: 20),
            makeExercise(name: "Calf Raises", sets: 2, restSeconds: 15)
        ]
        return RehabPlan(
            id: UUID(), planName: "Test Plan",
            conditions: ["Knee Pain"],
            exercises: exercises ?? defaultExercises,
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 6, createdDate: Date(), notes: nil
        )
    }

    // MARK: - Initial State

    func testInitialState() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        XCTAssertEqual(vm.currentExerciseIndex, 0)
        XCTAssertEqual(vm.currentSet, 1)
        XCTAssertEqual(vm.phase, .exercise)
        XCTAssertFalse(vm.isPaused)
        XCTAssertTrue(vm.completedExercises.isEmpty)
        XCTAssertTrue(vm.skippedExercises.isEmpty)
    }

    func testCurrentExercise_returnsFirstExercise() {
        let plan = makePlan()
        let vm = GuidedWorkoutViewModel(plan: plan)

        XCTAssertEqual(vm.currentExercise?.name, "Wall Sits")
    }

    func testTotalExercises() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        XCTAssertEqual(vm.totalExercises, 3)
    }

    func testProgress_atStart() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        XCTAssertEqual(vm.progress, 0)
    }

    func testExerciseProgress_atStart() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        XCTAssertEqual(vm.exerciseProgress, "1 of 3")
    }

    // MARK: - Set Completion

    func testCompleteSet_incrementsSet() {
        let exercises = [makeExercise(name: "Test", sets: 3, restSeconds: 30)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        XCTAssertEqual(vm.currentSet, 1)
        vm.completeSet()

        // After completing set 1 of 3, should advance to set 2 (after rest)
        XCTAssertEqual(vm.currentSet, 2)
        XCTAssertEqual(vm.phase, .rest)
    }

    func testCompleteSet_allSetsComplete_addsToCompleted() {
        // Use a single-set exercise so completion is straightforward
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        // Complete the only set of first exercise → rest phase before next
        vm.completeSet()
        XCTAssertEqual(vm.phase, .rest)
        XCTAssertTrue(vm.completedExercises.contains("Ex1"))
    }

    func testCompleteSet_lastExerciseLastSet_completesWorkout() {
        let exercises = [makeExercise(name: "Only Exercise", sets: 1, restSeconds: 10)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        vm.completeSet()

        XCTAssertEqual(vm.phase, .complete)
        XCTAssertTrue(vm.completedExercises.contains("Only Exercise"))
    }

    // MARK: - Skip Exercise

    func testSkipExercise_recordsSkipped() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        vm.skipExercise()

        XCTAssertTrue(vm.skippedExercises.contains("Wall Sits"))
        XCTAssertEqual(vm.currentExerciseIndex, 1)
        XCTAssertEqual(vm.currentExercise?.name, "Quad Sets")
    }

    func testSkipExercise_lastExercise_completesWorkout() {
        let exercises = [makeExercise(name: "Only Exercise")]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        vm.skipExercise()

        XCTAssertEqual(vm.phase, .complete)
        XCTAssertTrue(vm.skippedExercises.contains("Only Exercise"))
    }

    func testSkipExercise_resetsSetCounter() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        // Advance to set 2
        vm.completeSet()
        vm.skipRest()

        // Now skip to next exercise
        vm.skipExercise()

        XCTAssertEqual(vm.currentSet, 1)
        XCTAssertEqual(vm.phase, .exercise)
    }

    // MARK: - Skip Rest

    func testSkipRest_movesToNextExercise() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 30),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 30)
        ]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        // Complete sole set → rest before next exercise
        vm.completeSet()
        XCTAssertEqual(vm.phase, .rest)

        // Skip rest → should move to next exercise
        vm.skipRest()
        XCTAssertEqual(vm.currentExerciseIndex, 1)
        XCTAssertEqual(vm.phase, .exercise)
        XCTAssertEqual(vm.currentExercise?.name, "Ex2")
    }

    func testSkipRest_duringExercisePhase_doesNothing() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        // In exercise phase
        XCTAssertEqual(vm.phase, .exercise)
        let indexBefore = vm.currentExerciseIndex
        vm.skipRest()

        // Should not advance (skipRest only works during .rest)
        XCTAssertEqual(vm.currentExerciseIndex, indexBefore)
    }

    // MARK: - Pause/Resume

    func testTogglePause_togglesState() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        XCTAssertFalse(vm.isPaused)

        vm.togglePause()
        XCTAssertTrue(vm.isPaused)

        vm.togglePause()
        XCTAssertFalse(vm.isPaused)
    }

    // MARK: - Build Session

    func testBuildSession_capturesData() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        // Complete some exercises
        vm.completeSet()
        vm.skipRest()
        vm.completeSet()
        vm.skipRest()
        vm.skipExercise()  // skip exercise 2

        let session = vm.buildSession(
            painLevel: 4.0,
            regionPainLevels: ["right_knee": 3.0],
            notes: "Felt good"
        )

        XCTAssertEqual(session.painLevel, 4.0)
        XCTAssertTrue(session.isCompleted)
        XCTAssertEqual(session.notes, "Felt good")
        XCTAssertEqual(session.regionPainLevels?["right_knee"], 3.0)
        XCTAssertNotNil(session.planId)
    }

    func testBuildSession_emptyNotes_nilsOut() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        let session = vm.buildSession(painLevel: 5.0, regionPainLevels: nil, notes: "   ")

        XCTAssertNil(session.notes)
    }

    func testBuildSession_emptyRegionPainLevels_nilsOut() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        let session = vm.buildSession(painLevel: 5.0, regionPainLevels: [:], notes: nil)

        XCTAssertNil(session.regionPainLevels)
    }

    // MARK: - Computed Properties

    func testFormattedElapsedTime_format() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        // Initial time should be "00:00" format
        let formatted = vm.formattedElapsedTime
        XCTAssertTrue(formatted.contains(":"))
        XCTAssertEqual(formatted.count, 5) // "MM:SS" format
    }

    func testFormattedTimeRemaining_format() {
        let vm = GuidedWorkoutViewModel(plan: makePlan())

        let formatted = vm.formattedTimeRemaining
        XCTAssertTrue(formatted.contains(":"))
        XCTAssertEqual(formatted.count, 5)
    }

    // MARK: - Empty Plan

    func testEmptyPlan_currentExerciseIsNil() {
        let plan = makePlan(exercises: [])
        let vm = GuidedWorkoutViewModel(plan: plan)

        XCTAssertNil(vm.currentExercise)
        XCTAssertEqual(vm.totalExercises, 0)
        XCTAssertEqual(vm.progress, 0)
    }

    func testEmptyPlan_completeSet_doesNothing() {
        let plan = makePlan(exercises: [])
        let vm = GuidedWorkoutViewModel(plan: plan)

        // Should not crash
        vm.completeSet()

        XCTAssertEqual(vm.phase, .exercise)
    }

    // MARK: - Full Workout Flow

    func testFullWorkout_twoExercises() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        // Exercise 1 — complete sole set
        XCTAssertEqual(vm.currentExercise?.name, "Ex1")
        vm.completeSet()
        XCTAssertEqual(vm.phase, .rest)
        XCTAssertTrue(vm.completedExercises.contains("Ex1"))

        // Skip rest
        vm.skipRest()
        XCTAssertEqual(vm.phase, .exercise)
        XCTAssertEqual(vm.currentExercise?.name, "Ex2")

        // Exercise 2 — complete sole set (last exercise)
        vm.completeSet()
        XCTAssertEqual(vm.phase, .complete)
        XCTAssertTrue(vm.completedExercises.contains("Ex2"))
        XCTAssertEqual(vm.completedExercises.count, 2)
        XCTAssertTrue(vm.skippedExercises.isEmpty)
    }
}
