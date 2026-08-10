import XCTest
@testable import COIL

final class PreventionRoutineEngineTests: XCTestCase {

    // MARK: - Safety Hold

    func testSelectRoutine_symptomsFlagged_returnsNil() {
        let profile = TestFixtures.makePreventionProfile()
        let checkIn = TestFixtures.makeCheckIn(hasSymptoms: true)

        let routine = PreventionRoutineEngine.selectRoutine(
            profile: profile, checkIn: checkIn, healthProfile: nil,
            activePlan: nil, recentFeedback: []
        )

        XCTAssertNil(routine, "No routine should ever be generated when symptoms are flagged")
    }

    // MARK: - Time → Exercise Count

    func testSelectRoutine_exerciseCountMatchesChosenLength() {
        for length in PreventionRoutineLength.allCases {
            let profile = TestFixtures.makePreventionProfile(preferredLength: length)
            let checkIn = TestFixtures.makeCheckIn(length: length)

            let routine = PreventionRoutineEngine.selectRoutine(
                profile: profile, checkIn: checkIn, healthProfile: nil,
                activePlan: nil, recentFeedback: []
            )

            XCTAssertEqual(routine?.essentialExercises.count, length.exerciseCount,
                            "\(length.displayName) should yield \(length.exerciseCount) exercises")
        }
    }

    // MARK: - Focus / Context → Category Emphasis

    func testCategoryEmphasis_deskComfortFocus_isMobilityControl() {
        let emphasis = PreventionRoutineEngine.categoryEmphasis(focus: .deskComfort, context: .deskHeavy, referenceDate: Date())
        XCTAssertEqual(emphasis, .mobilityControl)
    }

    func testCategoryEmphasis_workoutResilienceFocus_isStrengthCapacity() {
        let emphasis = PreventionRoutineEngine.categoryEmphasis(focus: .workoutResilience, context: .activeDay, referenceDate: Date())
        XCTAssertEqual(emphasis, .strengthCapacity)
    }

    func testCategoryEmphasis_balanceFocus_isBalance() {
        let emphasis = PreventionRoutineEngine.categoryEmphasis(focus: .balance, context: .deskHeavy, referenceDate: Date())
        XCTAssertEqual(emphasis, .balance)
    }

    /// Recovery day forces gentle, recovery-oriented emphasis regardless of
    /// the user's chosen focus — spec: "no aggressive progression" on a recovery day.
    func testCategoryEmphasis_recoveryDayContext_overridesFocusToRecoveryHabits() {
        let emphasis = PreventionRoutineEngine.categoryEmphasis(focus: .workoutResilience, context: .recoveryDay, referenceDate: Date())
        XCTAssertEqual(emphasis, .recoveryHabits)
    }

    func testSelectRoutine_recoveryDayContext_onlySelectsGentleExercises() {
        let profile = TestFixtures.makePreventionProfile(focus: .workoutResilience)
        let checkIn = TestFixtures.makeCheckIn(context: .recoveryDay, length: .long)

        let routine = PreventionRoutineEngine.selectRoutine(
            profile: profile, checkIn: checkIn, healthProfile: nil,
            activePlan: nil, recentFeedback: []
        )

        let gentleKeys = Set(PreventionExerciseCatalog.allEntries.filter(\.isGentle).map { $0.template.catalogKey })
        for item in routine?.essentialExercises ?? [] {
            XCTAssertTrue(gentleKeys.contains(item.catalogKey), "\(item.catalogKey) is not tagged gentle — unsafe for a recovery day")
        }
    }

    func testSelectRoutine_commuteContext_excludesFloorSpaceExercises() {
        let profile = TestFixtures.makePreventionProfile(focus: .mobility)
        let checkIn = TestFixtures.makeCheckIn(context: .commute, length: .long)

        let routine = PreventionRoutineEngine.selectRoutine(
            profile: profile, checkIn: checkIn, healthProfile: nil,
            activePlan: nil, recentFeedback: []
        )

        let spaceKeys = Set(PreventionExerciseCatalog.allEntries.filter(\.requiresSpace).map { $0.template.catalogKey })
        for item in routine?.essentialExercises ?? [] {
            XCTAssertFalse(spaceKeys.contains(item.catalogKey), "\(item.catalogKey) needs floor space — unsuitable mid-commute")
        }
    }

    // MARK: - Safety Filtering

    func testSafetyFilteredPool_currentInjury_excludesMatchingTargetArea() {
        var healthProfile = TestFixtures.makeProfile()
        healthProfile.injuries = [
            UserProfile.Injury(bodyArea: "Knee", description: "Sprain", isCurrent: true)
        ]

        let pool = PreventionRoutineEngine.safetyFilteredPool(healthProfile: healthProfile, activePlan: nil)

        XCTAssertFalse(pool.contains { $0.template.exercise.targetArea.lowercased().contains("knee") },
                        "A current knee injury should exclude every knee-targeting catalog entry")
    }

    func testSafetyFilteredPool_pastInjury_doesNotExclude() {
        var healthProfile = TestFixtures.makeProfile()
        healthProfile.injuries = [
            UserProfile.Injury(bodyArea: "Knee", description: "Old sprain", isCurrent: false)
        ]

        let pool = PreventionRoutineEngine.safetyFilteredPool(healthProfile: healthProfile, activePlan: nil)

        XCTAssertTrue(pool.contains { $0.template.exercise.targetArea.lowercased().contains("knee") },
                       "A resolved (non-current) injury should not restrict the catalog")
    }

    func testSafetyFilteredPool_stillRecoveringSurgery_excludesMatchingArea() {
        var healthProfile = TestFixtures.makeProfile()
        healthProfile.surgeries = [
            TestFixtures.makeSurgery(bodyArea: "Shoulder", recoveryStatus: "Still recovering")
        ]

        let pool = PreventionRoutineEngine.safetyFilteredPool(healthProfile: healthProfile, activePlan: nil)

        XCTAssertFalse(pool.contains { $0.template.exercise.targetArea.lowercased().contains("shoulder") })
    }

    func testSafetyFilteredPool_activePlanExercises_areExcludedAsDuplicates() {
        let plan = TestFixtures.makePlan(exercises: [TestFixtures.makeExercise(name: "Chin Tucks")])

        let pool = PreventionRoutineEngine.safetyFilteredPool(healthProfile: nil, activePlan: plan)

        XCTAssertFalse(pool.contains { $0.template.exercise.name.lowercased() == "chin tucks" })
    }

    /// Osteoporosis excludes impact/jump-named candidates. The production
    /// catalog deliberately contains none (it's all gentle by design), so
    /// this injects a synthetic impact-named entry via the injectable `pool`
    /// parameter to prove the exclusion rule itself actually fires.
    func testSafetyFilteredPool_osteoporosis_excludesImpactNamedEntries() {
        var healthProfile = TestFixtures.makeProfile(medicalConditions: ["Osteoporosis"])
        let jumpEntry = PreventionCatalogEntry(
            template: TestFixtures.makePreventionExercise(name: "Jump Squats", catalogKey: "jump-squats-synthetic"),
            suitableFocuses: [], suitableContexts: [], isGentle: false, requiresSpace: false
        )
        let safeEntry = PreventionCatalogEntry(
            template: TestFixtures.makePreventionExercise(name: "Ankle Circles", catalogKey: "ankle-circles"),
            suitableFocuses: [], suitableContexts: [], isGentle: true, requiresSpace: false
        )

        let poolWithOsteoporosis = PreventionRoutineEngine.safetyFilteredPool(
            healthProfile: healthProfile, activePlan: nil, pool: [jumpEntry, safeEntry]
        )
        XCTAssertFalse(poolWithOsteoporosis.contains { $0.template.catalogKey == "jump-squats-synthetic" })
        XCTAssertTrue(poolWithOsteoporosis.contains { $0.template.catalogKey == "ankle-circles" })

        healthProfile.medicalConditions = []
        let poolWithoutOsteoporosis = PreventionRoutineEngine.safetyFilteredPool(
            healthProfile: healthProfile, activePlan: nil, pool: [jumpEntry, safeEntry]
        )
        XCTAssertTrue(poolWithoutOsteoporosis.contains { $0.template.catalogKey == "jump-squats-synthetic" },
                       "Without osteoporosis, the impact-keyword exclusion should not apply")
    }

    // MARK: - Rotation vs. Weekly Coherence

    func testPickExercises_rotatesAcrossDaysWithinTheSameEmphasis() {
        let calendar = Calendar.current
        let base = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))! // a Monday
        var selections: Set<[String]> = []

        for dayOffset in 0..<6 {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: base)!
            let profile = TestFixtures.makePreventionProfile(focus: .mobility)
            let checkIn = TestFixtures.makeCheckIn(context: .deskHeavy, length: .short)
            let routine = PreventionRoutineEngine.selectRoutine(
                profile: profile, checkIn: checkIn, healthProfile: nil,
                activePlan: nil, recentFeedback: [], referenceDate: day
            )
            selections.insert((routine?.essentialExercises ?? []).map(\.catalogKey).sorted())
        }

        XCTAssertGreaterThan(selections.count, 1, "The exact exercise set should vary across at least some days in the week")
    }

    func testCategoryEmphasis_healthyAgingFocus_stableWithinAWeek() {
        let calendar = Calendar.current
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        // Derive the calendar's own week boundaries rather than assuming a
        // fixed Mon-Sun span — `weekOfYear` follows the locale's first weekday.
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: anchor)!.start

        var emphases: Set<PreventionCategory> = []
        for dayOffset in 0..<7 {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart)!
            emphases.insert(PreventionRoutineEngine.categoryEmphasis(focus: .healthyAging, context: .activeDay, referenceDate: day))
        }
        XCTAssertEqual(emphases.count, 1, "healthyAging emphasis should stay the same across every day of one calendar week")
    }

    // MARK: - Progression / Regression

    func testDecideProgression_tooMuchFeedback_regresses() {
        let feedback = [TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .tooMuch)]
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: feedback, emphasis: .mobilityControl)
        XCTAssertEqual(decision, .regress)
    }

    func testDecideProgression_concerningPain_regressesEvenIfAboutRight() {
        let feedback = [TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .aboutRight, pain: .concerning)]
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: feedback, emphasis: .mobilityControl)
        XCTAssertEqual(decision, .regress)
    }

    func testDecideProgression_nonePain_doesNotRegress() {
        let feedback = [TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .aboutRight, pain: PreventionPainLevel.none)]
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: feedback, emphasis: .mobilityControl)
        XCTAssertEqual(decision, .maintain, "Explicit 'no pain' must not be confused with 'no pain field set'")
    }

    func testDecideProgression_twoConsecutiveEasier_advances() {
        let now = Date()
        let feedback = [
            TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .easier, submittedDate: now),
            TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .easier, submittedDate: now.addingTimeInterval(-86400))
        ]
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: feedback, emphasis: .mobilityControl)
        XCTAssertEqual(decision, .advance)
    }

    func testDecideProgression_singleEasier_maintainsUntilConfirmed() {
        let feedback = [TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .easier)]
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: feedback, emphasis: .mobilityControl)
        XCTAssertEqual(decision, .maintain)
    }

    func testDecideProgression_noFeedback_maintains() {
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: [], emphasis: .mobilityControl)
        XCTAssertEqual(decision, .maintain)
    }

    func testDecideProgression_ignoresFeedbackFromOtherCategories() {
        let feedback = [TestFixtures.makeFeedback(categories: [.strengthCapacity], difficulty: .tooMuch)]
        let decision = PreventionRoutineEngine.decideProgression(recentFeedback: feedback, emphasis: .mobilityControl)
        XCTAssertEqual(decision, .maintain)
    }

    func testSelectRoutine_regression_marksRoutineAsRegressed() {
        let profile = TestFixtures.makePreventionProfile(focus: .mobility)
        let checkIn = TestFixtures.makeCheckIn(context: .deskHeavy, length: .medium)
        let feedback = [TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .tooMuch)]

        let routine = PreventionRoutineEngine.selectRoutine(
            profile: profile, checkIn: checkIn, healthProfile: nil,
            activePlan: nil, recentFeedback: feedback
        )

        XCTAssertEqual(routine?.wasRegressed, true)
        XCTAssertEqual(routine?.wasAdvanced, false)
    }

    func testSelectRoutine_advance_marksRoutineAsAdvanced() {
        let profile = TestFixtures.makePreventionProfile(focus: .mobility)
        let checkIn = TestFixtures.makeCheckIn(context: .deskHeavy, length: .medium)
        let now = Date()
        let feedback = [
            TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .easier, submittedDate: now),
            TestFixtures.makeFeedback(categories: [.mobilityControl], difficulty: .easier, submittedDate: now.addingTimeInterval(-86400))
        ]

        let routine = PreventionRoutineEngine.selectRoutine(
            profile: profile, checkIn: checkIn, healthProfile: nil,
            activePlan: nil, recentFeedback: feedback
        )

        XCTAssertEqual(routine?.wasAdvanced, true)
        XCTAssertEqual(routine?.wasRegressed, false)
    }

    // MARK: - Micro-Action

    func testSelectRoutine_alwaysIncludesOneMicroActionMatchingContext() {
        for context in DailyContext.allCases {
            let profile = TestFixtures.makePreventionProfile()
            let checkIn = TestFixtures.makeCheckIn(context: context)
            let routine = PreventionRoutineEngine.selectRoutine(
                profile: profile, checkIn: checkIn, healthProfile: nil,
                activePlan: nil, recentFeedback: []
            )
            XCTAssertNotNil(routine?.microAction, "Every context should resolve a micro-action")
        }
    }
}
