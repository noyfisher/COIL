import XCTest
@testable import COIL

// MARK: - Streak Logic Tests

@MainActor
final class StreakServiceTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a testable StreakService instance (no Firebase).
    private func makeSUT() -> StreakService {
        StreakService(skipFirebaseLoad: true)
    }

    /// Creates a minimal WorkoutSession for testing.
    private func makeSession(date: Date = Date()) -> WorkoutSession {
        WorkoutSession(
            id: UUID(), date: date, duration: 300,
            painLevel: 3, isCompleted: true,
            exercisesPerformed: ["Test Exercise"]
        )
    }

    // MARK: - StreakData Tests

    func testStreakData_defaultValues() {
        let data = StreakData()

        XCTAssertEqual(data.currentStreak, 0)
        XCTAssertEqual(data.longestStreak, 0)
        XCTAssertNil(data.lastWorkoutDate)
    }

    func testStreakData_isActive_noLastWorkout_false() {
        let data = StreakData()

        XCTAssertFalse(data.isActive)
    }

    func testStreakData_isActive_today_true() {
        var data = StreakData()
        data.lastWorkoutDate = Date()

        XCTAssertTrue(data.isActive)
    }

    func testStreakData_isActive_yesterday_true() {
        var data = StreakData()
        data.lastWorkoutDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())

        XCTAssertTrue(data.isActive)
    }

    func testStreakData_isActive_twoDaysAgo_false() {
        var data = StreakData()
        data.lastWorkoutDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())

        XCTAssertFalse(data.isActive)
    }

    // MARK: - Achievement Catalog Tests

    func testAchievementCatalog_hasSixPlusEntries() {
        XCTAssertGreaterThanOrEqual(Achievement.catalog.count, 6)
    }

    func testAchievement_isEarned_false_whenNoDate() {
        let achievement = Achievement.catalog[0]

        XCTAssertFalse(achievement.isEarned)
        XCTAssertNil(achievement.dateEarned)
    }

    func testAchievement_isEarned_true_whenDateSet() {
        var achievement = Achievement.catalog[0]
        achievement.dateEarned = Date()

        XCTAssertTrue(achievement.isEarned)
    }

    func testAchievementCatalog_uniqueIds() {
        let ids = Achievement.catalog.map { $0.id }
        XCTAssertEqual(ids.count, Set(ids).count, "Achievement IDs should be unique")
    }

    func testAchievementCatalog_knownIds() {
        let ids = Set(Achievement.catalog.map { $0.id })

        XCTAssertTrue(ids.contains("first_workout"))
        XCTAssertTrue(ids.contains("streak_3"))
        XCTAssertTrue(ids.contains("streak_7"))
        XCTAssertTrue(ids.contains("streak_30"))
        XCTAssertTrue(ids.contains("sessions_10"))
        XCTAssertTrue(ids.contains("sessions_50"))
    }

    // MARK: - updateStreak Tests (real StreakService)

    func testUpdateStreak_firstWorkout_streakIsOne() {
        let sut = makeSUT()

        sut.updateStreak(after: makeSession())

        XCTAssertEqual(sut.streakData.currentStreak, 1)
        XCTAssertEqual(sut.streakData.longestStreak, 1)
        XCTAssertNotNil(sut.streakData.lastWorkoutDate)
    }

    func testUpdateStreak_consecutiveDay_incrementsStreak() {
        let sut = makeSUT()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        // Set up a pre-existing streak from yesterday
        sut.streakData.currentStreak = 3
        sut.streakData.longestStreak = 5
        sut.streakData.lastWorkoutDate = yesterday

        sut.updateStreak(after: makeSession())

        XCTAssertEqual(sut.streakData.currentStreak, 4)
        XCTAssertEqual(sut.streakData.longestStreak, 5, "Longest should remain 5")
    }

    func testUpdateStreak_consecutiveDay_updatesLongest() {
        let sut = makeSUT()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        sut.streakData.currentStreak = 5
        sut.streakData.longestStreak = 5
        sut.streakData.lastWorkoutDate = yesterday

        sut.updateStreak(after: makeSession())

        XCTAssertEqual(sut.streakData.currentStreak, 6)
        XCTAssertEqual(sut.streakData.longestStreak, 6, "Longest should be updated to 6")
    }

    func testUpdateStreak_sameDay_noChange() {
        let sut = makeSUT()

        sut.streakData.currentStreak = 3
        sut.streakData.longestStreak = 5
        sut.streakData.lastWorkoutDate = Date()

        sut.updateStreak(after: makeSession())

        XCTAssertEqual(sut.streakData.currentStreak, 3, "Same-day workout should not change streak")
        XCTAssertEqual(sut.streakData.longestStreak, 5)
    }

    func testUpdateStreak_streakBroken_resetsToOne() {
        let sut = makeSUT()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!

        sut.streakData.currentStreak = 10
        sut.streakData.longestStreak = 10
        sut.streakData.lastWorkoutDate = twoDaysAgo

        sut.updateStreak(after: makeSession())

        XCTAssertEqual(sut.streakData.currentStreak, 1)
        XCTAssertEqual(sut.streakData.longestStreak, 10, "Longest streak should be preserved")
    }

    func testUpdateStreak_streakBroken_weekAgo() {
        let sut = makeSUT()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        sut.streakData.currentStreak = 20
        sut.streakData.longestStreak = 20
        sut.streakData.lastWorkoutDate = weekAgo

        sut.updateStreak(after: makeSession())

        XCTAssertEqual(sut.streakData.currentStreak, 1)
        XCTAssertEqual(sut.streakData.longestStreak, 20)
    }

    // MARK: - checkAchievements Tests (real StreakService)

    func testCheckAchievements_firstWorkout_earnedWithSession() {
        let sut = makeSUT()
        sut.streakData.currentStreak = 0

        sut.checkAchievements(totalSessions: 1)

        let first = sut.achievements.first(where: { $0.id == "first_workout" })
        XCTAssertTrue(first?.isEarned == true)
    }

    func testCheckAchievements_firstWorkout_earnedWithStreak() {
        let sut = makeSUT()
        sut.streakData.currentStreak = 1

        sut.checkAchievements(totalSessions: 0)

        let first = sut.achievements.first(where: { $0.id == "first_workout" })
        XCTAssertTrue(first?.isEarned == true)
    }

    func testCheckAchievements_firstWorkout_notEarned() {
        let sut = makeSUT()

        sut.checkAchievements(totalSessions: 0)

        let first = sut.achievements.first(where: { $0.id == "first_workout" })
        XCTAssertFalse(first?.isEarned == true)
    }

    func testCheckAchievements_streak3_earned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 3

        sut.checkAchievements(totalSessions: nil)

        let streak3 = sut.achievements.first(where: { $0.id == "streak_3" })
        XCTAssertTrue(streak3?.isEarned == true)
    }

    func testCheckAchievements_streak3_notEarned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 2

        sut.checkAchievements(totalSessions: nil)

        let streak3 = sut.achievements.first(where: { $0.id == "streak_3" })
        XCTAssertFalse(streak3?.isEarned == true)
    }

    func testCheckAchievements_streak7_earned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 7

        sut.checkAchievements(totalSessions: nil)

        let streak7 = sut.achievements.first(where: { $0.id == "streak_7" })
        XCTAssertTrue(streak7?.isEarned == true)
    }

    func testCheckAchievements_streak30_earned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 30

        sut.checkAchievements(totalSessions: nil)

        let streak30 = sut.achievements.first(where: { $0.id == "streak_30" })
        XCTAssertTrue(streak30?.isEarned == true)
    }

    func testCheckAchievements_streak30_notEarned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 29

        sut.checkAchievements(totalSessions: nil)

        let streak30 = sut.achievements.first(where: { $0.id == "streak_30" })
        XCTAssertFalse(streak30?.isEarned == true)
    }

    func testCheckAchievements_sessions10_earned() {
        let sut = makeSUT()

        sut.checkAchievements(totalSessions: 10)

        let sessions10 = sut.achievements.first(where: { $0.id == "sessions_10" })
        XCTAssertTrue(sessions10?.isEarned == true)
    }

    func testCheckAchievements_sessions10_notEarned() {
        let sut = makeSUT()

        sut.checkAchievements(totalSessions: 9)

        let sessions10 = sut.achievements.first(where: { $0.id == "sessions_10" })
        XCTAssertFalse(sessions10?.isEarned == true)
    }

    func testCheckAchievements_sessions50_earned() {
        let sut = makeSUT()

        sut.checkAchievements(totalSessions: 50)

        let sessions50 = sut.achievements.first(where: { $0.id == "sessions_50" })
        XCTAssertTrue(sessions50?.isEarned == true)
    }

    func testCheckAchievements_sessions50_notEarned() {
        let sut = makeSUT()

        sut.checkAchievements(totalSessions: 49)

        let sessions50 = sut.achievements.first(where: { $0.id == "sessions_50" })
        XCTAssertFalse(sessions50?.isEarned == true)
    }

    func testCheckAchievements_setsNewlyEarned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 7

        sut.checkAchievements(totalSessions: nil)

        XCTAssertNotNil(sut.newlyEarned)
    }

    func testClearNewlyEarned() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 3
        sut.checkAchievements(totalSessions: nil)
        XCTAssertNotNil(sut.newlyEarned)

        sut.clearNewlyEarned()

        XCTAssertNil(sut.newlyEarned)
    }

    func testCheckAchievements_doesNotReEarn() {
        let sut = makeSUT()
        sut.streakData.longestStreak = 3

        // First check earns it
        sut.checkAchievements(totalSessions: nil)
        let firstDate = sut.achievements.first(where: { $0.id == "streak_3" })?.dateEarned
        XCTAssertNotNil(firstDate)

        sut.clearNewlyEarned()

        // Second check should not re-earn (date should stay the same)
        sut.checkAchievements(totalSessions: nil)
        let secondDate = sut.achievements.first(where: { $0.id == "streak_3" })?.dateEarned
        XCTAssertEqual(firstDate, secondDate, "Already-earned achievement should not be re-earned")
        XCTAssertNil(sut.newlyEarned, "Should not trigger newlyEarned for already-earned")
    }
}
