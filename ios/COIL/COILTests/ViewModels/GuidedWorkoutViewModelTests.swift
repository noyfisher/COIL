import XCTest
@testable import COIL

// MARK: - GuidedWorkoutViewModel Tests

@MainActor
final class GuidedWorkoutViewModelTests: XCTestCase {

    override func tearDown() {
        // Clean up any workout checkpoints + completion counters saved to
        // UserDefaults during tests
        GuidedWorkoutViewModel.clearAllLocalWorkoutState()
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

    // MARK: - Inter-Set Rest (F7 regression)

    func testCompleteSet_interSetRest_skipRest_staysOnSameExercise() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 3, restSeconds: 30),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 30)
        ]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        vm.completeSet()
        XCTAssertEqual(vm.phase, .rest)
        XCTAssertEqual(vm.restKind, .interSet)
        XCTAssertEqual(vm.currentSet, 2)

        vm.skipRest()

        // Must return to the SAME exercise for set 2, not advance
        XCTAssertEqual(vm.phase, .exercise)
        XCTAssertEqual(vm.currentExerciseIndex, 0)
        XCTAssertEqual(vm.currentExercise?.name, "Ex1")
        XCTAssertEqual(vm.currentSet, 2)
        XCTAssertTrue(vm.completedExercises.isEmpty)
    }

    func testThreeSetExercise_fullProgression_appendsToCompleted() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 3, restSeconds: 30),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 30)
        ]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        // Set 1 → inter-set rest → set 2
        vm.completeSet()
        XCTAssertEqual(vm.restKind, .interSet)
        vm.skipRest()
        XCTAssertEqual(vm.currentSet, 2)
        XCTAssertEqual(vm.currentExerciseIndex, 0)

        // Set 2 → inter-set rest → set 3
        vm.completeSet()
        XCTAssertEqual(vm.restKind, .interSet)
        vm.skipRest()
        XCTAssertEqual(vm.currentSet, 3)
        XCTAssertEqual(vm.currentExerciseIndex, 0)
        XCTAssertTrue(vm.completedExercises.isEmpty)

        // Set 3 (final) → exercise completed, inter-exercise rest
        vm.completeSet()
        XCTAssertEqual(vm.completedExercises, ["Ex1"])
        XCTAssertEqual(vm.phase, .rest)
        XCTAssertEqual(vm.restKind, .interExercise)

        // Rest ends → next exercise, set counter reset
        vm.skipRest()
        XCTAssertEqual(vm.currentExerciseIndex, 1)
        XCTAssertEqual(vm.currentExercise?.name, "Ex2")
        XCTAssertEqual(vm.currentSet, 1)
        XCTAssertEqual(vm.phase, .exercise)

        // Final exercise, sole set → workout complete
        vm.completeSet()
        XCTAssertEqual(vm.phase, .complete)
        XCTAssertEqual(vm.completedExercises, ["Ex1", "Ex2"])
        XCTAssertTrue(vm.skippedExercises.isEmpty)
    }

    func testRestKind_afterFinalSet_isInterExercise() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))

        vm.completeSet()

        XCTAssertEqual(vm.phase, .rest)
        XCTAssertEqual(vm.restKind, .interExercise)
    }

    func testCheckpoint_duringInterSetRest_restoresToSameExerciseAndSet() {
        let exercises = [makeExercise(name: "Ex1", sets: 3, restSeconds: 30)]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        // Complete set 1 → inter-set rest; checkpoint was saved with currentSet = 2
        vm.completeSet()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint after completeSet")
            return
        }
        XCTAssertEqual(checkpoint.currentExerciseIndex, 0)
        XCTAssertEqual(checkpoint.currentSet, 2)

        let restored = GuidedWorkoutViewModel(plan: plan)
        restored.restoreFromCheckpoint(checkpoint)

        XCTAssertEqual(restored.currentExerciseIndex, 0)
        XCTAssertEqual(restored.currentSet, 2)
        XCTAssertEqual(restored.phase, .exercise)
        XCTAssertTrue(restored.completedExercises.isEmpty)
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

    // MARK: - WS5-01: Checkpoint save-point semantics

    func testCheckpoint_afterFinalSetOfExercise_pointsToNextExercise() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.completeSet()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint after completeSet")
            return
        }
        XCTAssertEqual(checkpoint.currentExerciseIndex, 1)
        XCTAssertEqual(checkpoint.currentSet, 1)
        XCTAssertEqual(checkpoint.completedExercises, ["Ex1"])
    }

    func testCheckpoint_resumeAfterFinalSet_doesNotDoubleCount() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)
        vm.completeSet()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint after completeSet")
            return
        }

        let restored = GuidedWorkoutViewModel(plan: plan)
        restored.restoreFromCheckpoint(checkpoint)

        XCTAssertEqual(restored.currentExercise?.name, "Ex2")
        XCTAssertEqual(restored.completedExercises, ["Ex1"])
        XCTAssertEqual(GuidedWorkoutViewModel.completionCount(for: "Ex1"), 1)

        restored.completeSet()
        XCTAssertEqual(restored.completedExercises, ["Ex1", "Ex2"])
    }

    func testCheckpoint_afterInterExerciseRestEnds_pointsToNextExercise() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.completeSet()
        vm.skipRest()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint after rest ends")
            return
        }
        XCTAssertEqual(checkpoint.currentExerciseIndex, 1)
        XCTAssertEqual(checkpoint.currentSet, 1)
    }

    func testCheckpoint_afterSkip_pointsToNextExercise() {
        let exercises = [
            makeExercise(name: "Wall Sits", sets: 2, restSeconds: 30),
            makeExercise(name: "Quad Sets", sets: 3, restSeconds: 20),
            makeExercise(name: "Calf Raises", sets: 2, restSeconds: 15)
        ]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.skipExercise()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint after skip")
            return
        }
        XCTAssertEqual(checkpoint.currentExerciseIndex, 1)
        XCTAssertEqual(checkpoint.currentSet, 1)
        XCTAssertEqual(checkpoint.skippedExercises, ["Wall Sits"])

        let restored = GuidedWorkoutViewModel(plan: plan)
        restored.restoreFromCheckpoint(checkpoint)
        XCTAssertEqual(restored.currentExercise?.name, "Quad Sets")
    }

    func testCheckpoint_lastExercise_clearedOnCompletion() {
        let exercises = [makeExercise(name: "Ex1", sets: 1, restSeconds: 10)]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.completeSet()

        XCTAssertNil(GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString))
    }

    // MARK: - WS5-02: Wall-clock rest countdown

    func testRestTimer_reconcile_afterTimeJump_derivesFromWallClock() {
        let exercises = [makeExercise(name: "Ex1", sets: 2, restSeconds: 60)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))
        let base = Date()
        vm.now = { base }

        vm.completeSet() // inter-set rest, 60s

        vm.now = { base.addingTimeInterval(40) }
        vm.reconcileRestFromWallClock()

        XCTAssertEqual(vm.timeRemaining, 20)
    }

    func testRestTimer_reconcile_pastExpiry_endsRest() {
        let exercises = [makeExercise(name: "Ex1", sets: 2, restSeconds: 60)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))
        let base = Date()
        vm.now = { base }

        vm.completeSet() // inter-set rest, 60s

        vm.now = { base.addingTimeInterval(61) }
        vm.reconcileRestFromWallClock()

        XCTAssertEqual(vm.phase, .exercise)
        XCTAssertEqual(vm.currentSet, 2)
    }

    func testAdjustRestTime_reAnchorsEndDate() {
        let exercises = [makeExercise(name: "Ex1", sets: 2, restSeconds: 60)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))
        let base = Date()
        vm.now = { base }
        vm.completeSet()

        vm.adjustRestTime(by: 15)
        XCTAssertEqual(vm.timeRemaining, 75)

        vm.reconcileRestFromWallClock()
        XCTAssertEqual(vm.timeRemaining, 75)

        vm.adjustRestTime(by: -1000)
        XCTAssertEqual(vm.timeRemaining, 5)
    }

    func testPauseDuringRest_resumePreservesRemaining() {
        let exercises = [makeExercise(name: "Ex1", sets: 2, restSeconds: 60)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))
        var base = Date()
        vm.now = { base }
        vm.completeSet() // 60s rest

        vm.togglePause()
        base = base.addingTimeInterval(30)
        vm.togglePause()
        vm.reconcileRestFromWallClock()

        XCTAssertEqual(vm.timeRemaining, 60)
    }

    // MARK: - WS5-03: Scene phase handling

    func testHandleAppBackgrounded_duringInterExerciseRest_savesAdvancedCheckpoint() {
        let exercises = [
            makeExercise(name: "Ex1", sets: 1, restSeconds: 10),
            makeExercise(name: "Ex2", sets: 1, restSeconds: 10)
        ]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.completeSet() // now in inter-exercise rest
        vm.handleAppBackgrounded()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint")
            return
        }
        XCTAssertEqual(checkpoint.currentExerciseIndex, 1)
        XCTAssertEqual(checkpoint.currentSet, 1)
    }

    func testHandleAppBackgrounded_midExercise_savesLiveState() {
        let plan = makePlan()
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.handleAppBackgrounded()

        guard let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString) else {
            XCTFail("Expected checkpoint")
            return
        }
        XCTAssertEqual(checkpoint.currentExerciseIndex, 0)
        XCTAssertEqual(checkpoint.currentSet, 1)
    }

    func testHandleAppBackgrounded_afterComplete_savesNothing() {
        let exercises = [makeExercise(name: "Ex1", sets: 1, restSeconds: 10)]
        let plan = makePlan(exercises: exercises)
        let vm = GuidedWorkoutViewModel(plan: plan)

        vm.completeSet() // single-exercise plan completes
        vm.handleAppBackgrounded()

        XCTAssertNil(GuidedWorkoutViewModel.savedCheckpoint(forPlanId: plan.id.uuidString))
    }

    func testHandleAppForegrounded_duringRest_reconciles() {
        let exercises = [makeExercise(name: "Ex1", sets: 2, restSeconds: 60)]
        let vm = GuidedWorkoutViewModel(plan: makePlan(exercises: exercises))
        let base = Date()
        vm.now = { base }
        vm.completeSet()

        vm.now = { base.addingTimeInterval(40) }
        vm.handleAppForegrounded()

        XCTAssertEqual(vm.timeRemaining, 20)
    }
}
