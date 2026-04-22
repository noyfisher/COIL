import XCTest
@testable import PT_Helper

final class AdaptiveProgressionAnalyzerTests: XCTestCase {

    // MARK: - Test Data

    private let planId = UUID()

    private func makePlan(exercises: [RehabExercise]? = nil) -> RehabPlan {
        let exs = exercises ?? [
            TestFixtures.makeExercise(name: "Wall Sits"),
            TestFixtures.makeExercise(name: "Quad Sets"),
            TestFixtures.makeExercise(name: "Calf Raises")
        ]
        return RehabPlan(
            id: planId,
            planName: "Test Plan",
            conditions: ["Knee Pain"],
            exercises: exs,
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 6,
            createdDate: Date(),
            notes: nil,
            startDate: Calendar.current.date(byAdding: .day, value: -14, to: Date())
        )
    }

    private func makeSession(
        daysAgo: Int,
        painLevel: Double,
        exercisesPerformed: [String] = ["Wall Sits", "Quad Sets", "Calf Raises"],
        forPlan: UUID? = nil
    ) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            duration: 1800,
            painLevel: painLevel,
            isCompleted: true,
            exercisesPerformed: exercisesPerformed,
            planId: forPlan ?? planId
        )
    }

    // MARK: - Insufficient Data

    func testAnalyze_lessThan3Sessions_returnsInsufficientData() {
        let plan = makePlan()
        let sessions = [
            makeSession(daysAgo: 4, painLevel: 5),
            makeSession(daysAgo: 2, painLevel: 4)
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .insufficientData)
        XCTAssertEqual(result.analysis.sessionCount, 2)
    }

    func testAnalyze_zeroSessions_returnsInsufficientData() {
        let plan = makePlan()
        let result = AdaptiveProgressionAnalyzer.analyze(sessions: [], plan: plan)
        XCTAssertEqual(result.action, .insufficientData)
        XCTAssertEqual(result.analysis.sessionCount, 0)
    }

    func testAnalyze_sessionsForDifferentPlan_returnsInsufficientData() {
        let plan = makePlan()
        let otherPlan = UUID()
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 5, forPlan: otherPlan),
            makeSession(daysAgo: 4, painLevel: 4, forPlan: otherPlan),
            makeSession(daysAgo: 2, painLevel: 3, forPlan: otherPlan)
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .insufficientData)
    }

    // MARK: - Pain Trend

    func testCalculatePainTrend_decreasingPain_returnsImproving() {
        let early = [makeSession(daysAgo: 10, painLevel: 7)]
        let recent = [makeSession(daysAgo: 1, painLevel: 3)]

        let (trend, magnitude) = AdaptiveProgressionAnalyzer.calculatePainTrend(
            early: early, recent: recent
        )
        XCTAssertEqual(trend, .improving)
        XCTAssertEqual(magnitude, 4.0, accuracy: 0.01)
    }

    func testCalculatePainTrend_increasingPain_returnsWorsening() {
        let early = [makeSession(daysAgo: 10, painLevel: 3)]
        let recent = [makeSession(daysAgo: 1, painLevel: 6)]

        let (trend, _) = AdaptiveProgressionAnalyzer.calculatePainTrend(
            early: early, recent: recent
        )
        XCTAssertEqual(trend, .worsening)
    }

    func testCalculatePainTrend_stablePain_returnsStable() {
        let early = [makeSession(daysAgo: 10, painLevel: 4)]
        let recent = [makeSession(daysAgo: 1, painLevel: 4.3)]

        let (trend, _) = AdaptiveProgressionAnalyzer.calculatePainTrend(
            early: early, recent: recent
        )
        XCTAssertEqual(trend, .stable)
    }

    // MARK: - Advance Recommendations

    func testAnalyze_improvingPainHighCompletion_returnsAdvance() {
        let plan = makePlan()
        // Pain going down: 7, 6, 5, 4, 3 over 5 sessions, all exercises completed
        let sessions = (0..<5).map { i in
            makeSession(daysAgo: 10 - i * 2, painLevel: Double(7 - i))
        }

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .advance)
    }

    func testAnalyze_stableLowPainHighCompletion_returnsAdvance() {
        let plan = makePlan()
        // Stable low pain, all exercises completed
        let sessions = [
            makeSession(daysAgo: 8, painLevel: 2),
            makeSession(daysAgo: 6, painLevel: 2.3),
            makeSession(daysAgo: 4, painLevel: 2.1),
            makeSession(daysAgo: 2, painLevel: 2.2)
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .advance)
    }

    // MARK: - Scale Back Recommendations

    func testAnalyze_highAveragePain_returnsScaleBack() {
        let plan = makePlan()
        // High pain that's stable (not improving)
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 7),
            makeSession(daysAgo: 4, painLevel: 7.5),
            makeSession(daysAgo: 2, painLevel: 7)
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .scaleBack)
        XCTAssertEqual(result.confidence, .high)
    }

    func testAnalyze_worseningPainLargeMagnitude_returnsScaleBack() {
        let plan = makePlan()
        // Pain going up significantly: 3, 4, 6
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 3),
            makeSession(daysAgo: 4, painLevel: 4),
            makeSession(daysAgo: 2, painLevel: 6)
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .scaleBack)
    }

    func testAnalyze_lowCompletionRate_returnsScaleBack() {
        let plan = makePlan()
        // Stable pain but only completing 1 of 3 exercises
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 4, exercisesPerformed: ["Wall Sits"]),
            makeSession(daysAgo: 4, painLevel: 4, exercisesPerformed: ["Quad Sets"]),
            makeSession(daysAgo: 2, painLevel: 4, exercisesPerformed: ["Wall Sits"])
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .scaleBack)
    }

    // MARK: - Maintain Recommendations

    func testAnalyze_worseningPainSmallMagnitude_returnsMaintain() {
        let plan = makePlan()
        // Pain slightly increasing: 4.0, 4.3, 4.8
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 4.0),
            makeSession(daysAgo: 4, painLevel: 4.3),
            makeSession(daysAgo: 2, painLevel: 4.8)
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .maintain)
    }

    func testAnalyze_mixedSignals_defaultsToMaintain() {
        let plan = makePlan()
        // Pain stable, moderate completion (2 of 3 exercises = 67%)
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets"]),
            makeSession(daysAgo: 4, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets"]),
            makeSession(daysAgo: 2, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets"])
        ]

        let result = AdaptiveProgressionAnalyzer.analyze(sessions: sessions, plan: plan)
        XCTAssertEqual(result.action, .maintain)
    }

    // MARK: - Apply Progression

    func testApplyProgression_advance_increasesSetsAndReps() {
        let plan = makePlan(exercises: [
            TestFixtures.makeExercise(name: "Wall Sits")  // sets: 3, reps: "10-12"
        ])

        let updated = AdaptiveProgressionAnalyzer.applyProgression(.advance, to: plan)
        let exercise = updated.exercises[0]
        XCTAssertEqual(exercise.sets, 4)
        XCTAssertEqual(exercise.reps, "12-14")
        XCTAssertEqual(exercise.difficulty, .intermediate)  // was beginner
    }

    func testApplyProgression_advance_capsAtMaxSets() {
        var exercise = TestFixtures.makeExercise(name: "Wall Sits")
        exercise.sets = 6  // already at cap
        let plan = makePlan(exercises: [exercise])

        let updated = AdaptiveProgressionAnalyzer.applyProgression(.advance, to: plan)
        XCTAssertEqual(updated.exercises[0].sets, 6, "Should not exceed 6 sets")
    }

    func testApplyProgression_scaleBack_decreasesSetsAndReps() {
        let plan = makePlan(exercises: [
            TestFixtures.makeExercise(name: "Wall Sits")  // sets: 3, reps: "10-12"
        ])

        let updated = AdaptiveProgressionAnalyzer.applyProgression(.scaleBack, to: plan)
        let exercise = updated.exercises[0]
        XCTAssertEqual(exercise.sets, 2)
        XCTAssertEqual(exercise.reps, "8-10")
        XCTAssertEqual(exercise.difficulty, .beginner, "Scale back should not change difficulty")
    }

    func testApplyProgression_scaleBack_floorsAtOneSet() {
        var exercise = TestFixtures.makeExercise(name: "Wall Sits")
        exercise.sets = 1  // already at floor
        let plan = makePlan(exercises: [exercise])

        let updated = AdaptiveProgressionAnalyzer.applyProgression(.scaleBack, to: plan)
        XCTAssertEqual(updated.exercises[0].sets, 1, "Should not go below 1 set")
    }

    func testApplyProgression_maintain_noChanges() {
        let plan = makePlan()
        let updated = AdaptiveProgressionAnalyzer.applyProgression(.maintain, to: plan)

        for (original, modified) in zip(plan.exercises, updated.exercises) {
            XCTAssertEqual(original.sets, modified.sets)
            XCTAssertEqual(original.reps, modified.reps)
            XCTAssertEqual(original.difficulty, modified.difficulty)
        }
    }

    // MARK: - Reps Adjustment

    func testAdjustReps_simpleNumber_incrementsCorrectly() {
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("10", increment: 2), "12")
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("10", increment: -2), "8")
    }

    func testAdjustReps_rangeFormat_incrementsBothEnds() {
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("10-12", increment: 2), "12-14")
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("10-12", increment: -2), "8-10")
    }

    func testAdjustReps_durationFormat_returnsUnchanged() {
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("30 sec", increment: 2), "30 sec")
    }

    func testAdjustReps_negativeIncrement_floorsAtOne() {
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("2", increment: -5), "1")
        XCTAssertEqual(AdaptiveProgressionAnalyzer.adjustReps("1-3", increment: -5), "1-1")
    }

    // MARK: - Post-Workout Insight

    func testPostWorkoutInsight_painDecreased_returnsPositiveMessage() {
        let plan = makePlan()
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 6),
            makeSession(daysAgo: 4, painLevel: 5),
            makeSession(daysAgo: 2, painLevel: 5)
        ]
        let latest = makeSession(daysAgo: 0, painLevel: 3)

        let insight = AdaptiveProgressionAnalyzer.postWorkoutInsight(
            sessions: sessions + [latest], plan: plan, latestSession: latest
        )
        XCTAssertNotNil(insight)
        XCTAssertTrue(insight!.contains("trending down"), "Should indicate improvement")
    }

    func testPostWorkoutInsight_painIncreased_returnsWarningMessage() {
        let plan = makePlan()
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 3),
            makeSession(daysAgo: 4, painLevel: 3),
            makeSession(daysAgo: 2, painLevel: 3)
        ]
        let latest = makeSession(daysAgo: 0, painLevel: 6)

        let insight = AdaptiveProgressionAnalyzer.postWorkoutInsight(
            sessions: sessions + [latest], plan: plan, latestSession: latest
        )
        XCTAssertNotNil(insight)
        XCTAssertTrue(insight!.contains("higher"), "Should warn about increased pain")
    }

    func testPostWorkoutInsight_singleSession_returnsNil() {
        let plan = makePlan()
        let latest = makeSession(daysAgo: 0, painLevel: 4)

        let insight = AdaptiveProgressionAnalyzer.postWorkoutInsight(
            sessions: [latest], plan: plan, latestSession: latest
        )
        XCTAssertNil(insight, "Need at least 2 sessions for insight")
    }

    // MARK: - Completion Rate

    func testCompletionRate_allExercisesPerformed_returns1() {
        let plan = makePlan()
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets", "Calf Raises"]),
            makeSession(daysAgo: 4, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets", "Calf Raises"]),
            makeSession(daysAgo: 2, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets", "Calf Raises"])
        ]

        let analysis = AdaptiveProgressionAnalyzer.makeAnalysis(
            planId: planId, sessions: sessions, plan: plan
        )
        XCTAssertEqual(analysis.completionRate, 1.0, accuracy: 0.01)
    }

    func testCompletionRate_halfExercisesPerformed_returns05() {
        let plan = makePlan()  // 3 exercises
        // Performing ~1.5 exercises on average (1, 2, 1, 2)
        let sessions = [
            makeSession(daysAgo: 8, painLevel: 4, exercisesPerformed: ["Wall Sits"]),
            makeSession(daysAgo: 6, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets"]),
            makeSession(daysAgo: 4, painLevel: 4, exercisesPerformed: ["Wall Sits"]),
            makeSession(daysAgo: 2, painLevel: 4, exercisesPerformed: ["Wall Sits", "Quad Sets"])
        ]

        let analysis = AdaptiveProgressionAnalyzer.makeAnalysis(
            planId: planId, sessions: sessions, plan: plan
        )
        XCTAssertEqual(analysis.completionRate, 0.5, accuracy: 0.01)
    }

    // MARK: - Days Between Sessions

    func testCalculateDaysBetween_regularGaps_returnsCorrectAverage() {
        // Sessions every 2 days
        let sessions = [
            makeSession(daysAgo: 6, painLevel: 4),
            makeSession(daysAgo: 4, painLevel: 4),
            makeSession(daysAgo: 2, painLevel: 4)
        ]

        let avg = AdaptiveProgressionAnalyzer.calculateDaysBetween(sessions: sessions)
        XCTAssertEqual(avg, 2.0, accuracy: 0.1)
    }

    func testCalculateDaysBetween_singleSession_returnsZero() {
        let sessions = [makeSession(daysAgo: 2, painLevel: 4)]
        let avg = AdaptiveProgressionAnalyzer.calculateDaysBetween(sessions: sessions)
        XCTAssertEqual(avg, 0)
    }
}
