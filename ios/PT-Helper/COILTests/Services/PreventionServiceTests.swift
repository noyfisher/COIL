import XCTest
@testable import COIL

@MainActor
final class PreventionServiceTests: XCTestCase {

    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        testDefaults = UserDefaults(suiteName: "PreventionServiceTests")
        testDefaults.removePersistentDomain(forName: "PreventionServiceTests")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "PreventionServiceTests")
        testDefaults = nil
        super.tearDown()
    }

    private func makeSUT() -> PreventionService {
        PreventionService(defaults: testDefaults)
    }

    // MARK: - Defaults

    func testInit_noPersistedData_usesSafeDefaultProfile() {
        let sut = makeSUT()
        XCTAssertEqual(sut.profile.focus, PreventionProfile.defaultProfile.focus)
        XCTAssertEqual(sut.profile.hasCompletedSetup, false)
        XCTAssertTrue(sut.checkIns.isEmpty)
        XCTAssertTrue(sut.completions.isEmpty)
        XCTAssertTrue(sut.feedback.isEmpty)
    }

    // MARK: - Profile Round Trip

    func testSaveProfile_persistsAcrossInstances() {
        let sut1 = makeSUT()
        var profile = TestFixtures.makePreventionProfile(focus: .balance, preferredLength: .long)
        profile.hasCompletedSetup = false // saveProfile should force this true regardless
        sut1.saveProfile(profile)

        let sut2 = makeSUT()
        XCTAssertEqual(sut2.profile.focus, .balance)
        XCTAssertEqual(sut2.profile.preferredLength, .long)
        XCTAssertTrue(sut2.profile.hasCompletedSetup, "saveProfile must mark setup complete")
    }

    // MARK: - Check-In Round Trip

    func testSubmitCheckIn_roundTripsPerCalendarDay() {
        let sut1 = makeSUT()
        let checkIn = TestFixtures.makeCheckIn(context: .commute, hasSymptoms: false, length: .short)
        sut1.submitCheckIn(checkIn)

        let sut2 = makeSUT()
        let reloaded = sut2.checkIn(for: checkIn.dateKey)
        XCTAssertEqual(reloaded?.context, .commute)
        XCTAssertEqual(reloaded?.length, .short)
        XCTAssertEqual(reloaded?.hasNewOrWorseningSymptoms, false)
    }

    func testSubmitCheckIn_differentDaysAreKeyedIndependently() {
        let sut = makeSUT()
        sut.submitCheckIn(TestFixtures.makeCheckIn(dateKey: "2026-03-01", context: .deskHeavy))
        sut.submitCheckIn(TestFixtures.makeCheckIn(dateKey: "2026-03-02", context: .activeDay))

        XCTAssertEqual(sut.checkIn(for: "2026-03-01")?.context, .deskHeavy)
        XCTAssertEqual(sut.checkIn(for: "2026-03-02")?.context, .activeDay)
    }

    func testSubmitCheckIn_sameDayOverwritesPreviousEntry() {
        let sut = makeSUT()
        sut.submitCheckIn(TestFixtures.makeCheckIn(dateKey: "2026-03-01", context: .deskHeavy))
        sut.submitCheckIn(TestFixtures.makeCheckIn(dateKey: "2026-03-01", context: .recoveryDay))

        XCTAssertEqual(sut.checkIn(for: "2026-03-01")?.context, .recoveryDay)
        XCTAssertEqual(sut.checkIns.count, 1)
    }

    // MARK: - Routine Delegation

    func testRoutine_noCheckInToday_returnsNil() {
        let sut = makeSUT()
        XCTAssertNil(sut.routine(activePlan: nil, healthProfile: nil))
    }

    func testRoutine_symptomsFlaggedToday_returnsNil() {
        let sut = makeSUT()
        sut.submitCheckIn(TestFixtures.makeCheckIn(hasSymptoms: true))
        XCTAssertNil(sut.routine(activePlan: nil, healthProfile: nil))
    }

    func testRoutine_afterNonSymptomCheckIn_returnsARoutine() {
        let sut = makeSUT()
        sut.submitCheckIn(TestFixtures.makeCheckIn(hasSymptoms: false, length: .medium))
        let routine = sut.routine(activePlan: nil, healthProfile: nil)
        XCTAssertNotNil(routine)
        XCTAssertEqual(routine?.essentialExercises.count, PreventionRoutineLength.medium.exerciseCount)
    }

    // MARK: - Completion / Feedback Round Trip

    func testRecordCompletion_persistsAcrossInstances() {
        let sut1 = makeSUT()
        sut1.recordCompletion(TestFixtures.makeCompletion(categories: [.balance, .mobilityControl]))

        let sut2 = makeSUT()
        XCTAssertEqual(sut2.completions.count, 1)
        XCTAssertEqual(sut2.completions.first?.categories, [.balance, .mobilityControl])
    }

    func testRecordFeedback_persistsAcrossInstances() {
        let sut1 = makeSUT()
        sut1.recordFeedback(TestFixtures.makeFeedback(difficulty: .tooMuch, pain: .mild))

        let sut2 = makeSUT()
        XCTAssertEqual(sut2.feedback.count, 1)
        XCTAssertEqual(sut2.feedback.first?.difficulty, .tooMuch)
        XCTAssertEqual(sut2.feedback.first?.pain, .mild)
    }

    func testRecentFeedback_excludesEntriesOlderThanWindow() {
        let sut = makeSUT()
        let now = Date()
        sut.recordFeedback(TestFixtures.makeFeedback(submittedDate: now))
        sut.recordFeedback(TestFixtures.makeFeedback(submittedDate: now.addingTimeInterval(-20 * 86400)))

        let recent = sut.recentFeedback(days: 14, before: now)
        XCTAssertEqual(recent.count, 1)
    }

    // MARK: - History Pruning

    func testHistoryPruning_removesCompletionsOlderThanRetentionWindow() throws {
        let sut = makeSUT()
        let now = Date()
        let old = Calendar.current.date(byAdding: .day, value: -(PreventionService.historyRetentionDays + 5), to: now)!
        sut.recordCompletion(TestFixtures.makeCompletion(completedDate: old))
        sut.recordCompletion(TestFixtures.makeCompletion(completedDate: now))

        XCTAssertEqual(sut.completions.count, 1)
        let remainingDate = try XCTUnwrap(sut.completions.first?.completedDate)
        XCTAssertEqual(remainingDate.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    // MARK: - Clear All

    func testClearAll_resetsEverythingToDefaults() {
        let sut = makeSUT()
        sut.saveProfile(TestFixtures.makePreventionProfile(focus: .balance))
        sut.submitCheckIn(TestFixtures.makeCheckIn())
        sut.recordCompletion(TestFixtures.makeCompletion())
        sut.recordFeedback(TestFixtures.makeFeedback())

        sut.clearAll()

        XCTAssertEqual(sut.profile.focus, PreventionProfile.defaultProfile.focus)
        XCTAssertTrue(sut.checkIns.isEmpty)
        XCTAssertTrue(sut.completions.isEmpty)
        XCTAssertTrue(sut.feedback.isEmpty)

        let sut2 = makeSUT()
        XCTAssertTrue(sut2.checkIns.isEmpty, "clearAll must remove the persisted data, not just in-memory state")
    }

    // MARK: - Legacy Checklist Isolation

    /// `PreventativeTasksView`'s pre-existing checklist keys (`preventiveTasks_yyyy-MM-dd`)
    /// must keep working unmodified — this asserts the new service's keys can
    /// never collide with that legacy per-day key format.
    func testPersistenceKeys_neverCollideWithLegacyPreventativeChecklistKeys() {
        let keys = [
            PreventionService.profileKey, PreventionService.checkInsKey,
            PreventionService.completionsKey, PreventionService.feedbackKey
        ]
        for key in keys {
            XCTAssertFalse(key.hasPrefix("preventiveTasks"), "\(key) must not collide with the legacy checklist's key format")
        }
    }
}
