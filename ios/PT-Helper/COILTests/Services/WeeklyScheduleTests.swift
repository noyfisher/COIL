import XCTest
@testable import COIL

// MARK: - Weekly Schedule Tests (tests real RehabPlanViewModel.createWeeklySchedule)

@MainActor
final class WeeklyScheduleTests: XCTestCase {

    private func makeSUT() -> RehabPlanViewModel {
        RehabPlanViewModel()
    }

    private func makeExercises(count: Int) -> [RehabExercise] {
        (0..<count).map { TestFixtures.makeExercise(name: "Exercise \($0)") }
    }

    func testScheduleDistribution_Sedentary() {
        let sut = makeSUT()
        let exercises = makeExercises(count: 2)

        let schedule = sut.createWeeklySchedule(for: exercises, activityLevel: "sedentary")

        XCTAssertEqual(schedule.count, 7)
        XCTAssertTrue(schedule[0].isEmpty, "Sunday should be rest")
        XCTAssertFalse(schedule[1].isEmpty, "Monday should have exercises")
        XCTAssertTrue(schedule[2].isEmpty, "Tuesday should be rest")
        XCTAssertFalse(schedule[3].isEmpty, "Wednesday should have exercises")
        XCTAssertTrue(schedule[4].isEmpty, "Thursday should be rest")
        XCTAssertFalse(schedule[5].isEmpty, "Friday should have exercises")
        XCTAssertTrue(schedule[6].isEmpty, "Saturday should be rest")
    }

    func testScheduleDistribution_LightlyActive() {
        let sut = makeSUT()
        let schedule = sut.createWeeklySchedule(for: makeExercises(count: 2), activityLevel: "lightly active")
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 3)
    }

    func testScheduleDistribution_ModeratelyActive() {
        let sut = makeSUT()
        let schedule = sut.createWeeklySchedule(for: makeExercises(count: 2), activityLevel: "moderately active")
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 4)
    }

    func testScheduleDistribution_VeryActive() {
        let sut = makeSUT()
        let schedule = sut.createWeeklySchedule(for: makeExercises(count: 2), activityLevel: "very active")
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 5)
    }

    func testScheduleDistribution_Athlete() {
        let sut = makeSUT()
        let schedule = sut.createWeeklySchedule(for: makeExercises(count: 2), activityLevel: "athlete")
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 5)
    }

    func testScheduleDistribution_UnknownDefaultsTo3Days() {
        let sut = makeSUT()
        let schedule = sut.createWeeklySchedule(for: makeExercises(count: 2), activityLevel: "something weird")
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 3)
    }

    func testSchedule_exerciseIdsMatchInput() {
        let sut = makeSUT()
        let exercises = makeExercises(count: 3)
        let expectedIds = exercises.map { $0.id.uuidString }

        let schedule = sut.createWeeklySchedule(for: exercises, activityLevel: "sedentary")

        // All active days should contain the same exercise IDs
        for day in schedule where !day.isEmpty {
            XCTAssertEqual(day, expectedIds)
        }
    }

    func testSchedule_alwaysHas7Days() {
        let sut = makeSUT()
        for level in ["sedentary", "lightly active", "moderately active", "very active", "athlete", "unknown"] {
            let schedule = sut.createWeeklySchedule(for: makeExercises(count: 1), activityLevel: level)
            XCTAssertEqual(schedule.count, 7, "Schedule for '\(level)' should always have 7 days")
        }
    }

    func testSchedule_weekendAlwaysRest() {
        let sut = makeSUT()
        for level in ["sedentary", "moderately active", "very active", "athlete"] {
            let schedule = sut.createWeeklySchedule(for: makeExercises(count: 2), activityLevel: level)
            XCTAssertTrue(schedule[0].isEmpty, "Sunday should be rest for '\(level)'")
            XCTAssertTrue(schedule[6].isEmpty, "Saturday should be rest for '\(level)'")
        }
    }
}
