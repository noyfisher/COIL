import XCTest
@testable import PT_Helper

// MARK: - Weekly Schedule Tests

final class WeeklyScheduleTests: XCTestCase {

    func testScheduleDistribution_Sedentary() {
        // Sedentary = 3 days: Mon(1), Wed(3), Fri(5)
        let schedule = createSchedule(activityLevel: "sedentary", exerciseCount: 2)
        XCTAssertEqual(schedule.count, 7)
        XCTAssertTrue(schedule[0].isEmpty, "Sunday should be rest")
        XCTAssertFalse(schedule[1].isEmpty, "Monday should have exercises")
        XCTAssertTrue(schedule[2].isEmpty, "Tuesday should be rest")
        XCTAssertFalse(schedule[3].isEmpty, "Wednesday should have exercises")
        XCTAssertTrue(schedule[4].isEmpty, "Thursday should be rest")
        XCTAssertFalse(schedule[5].isEmpty, "Friday should have exercises")
        XCTAssertTrue(schedule[6].isEmpty, "Saturday should be rest")
    }

    func testScheduleDistribution_ModeratelyActive() {
        // Moderately active = 4 days: Mon(1), Tue(2), Thu(4), Fri(5)
        let schedule = createSchedule(activityLevel: "moderately active", exerciseCount: 2)
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 4)
    }

    func testScheduleDistribution_VeryActive() {
        // Very active = 5 days: Mon-Fri
        let schedule = createSchedule(activityLevel: "very active", exerciseCount: 2)
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 5)
    }

    func testScheduleDistribution_UnknownDefaultsTo3Days() {
        let schedule = createSchedule(activityLevel: "something weird", exerciseCount: 2)
        let activeDays = schedule.filter { !$0.isEmpty }.count
        XCTAssertEqual(activeDays, 3)
    }

    // Replicate the schedule logic from RehabPlanViewModel for testing
    private func createSchedule(activityLevel: String, exerciseCount: Int) -> [[String]] {
        let exerciseDays: Int
        switch activityLevel.lowercased() {
        case "sedentary", "lightly active": exerciseDays = 3
        case "moderately active": exerciseDays = 4
        case "very active", "athlete": exerciseDays = 5
        default: exerciseDays = 3
        }

        let exerciseIds = (0..<exerciseCount).map { _ in UUID().uuidString }
        var schedule: [[String]] = Array(repeating: [], count: 7)

        let dayIndices: [Int]
        switch exerciseDays {
        case 3: dayIndices = [1, 3, 5]
        case 4: dayIndices = [1, 2, 4, 5]
        case 5: dayIndices = [1, 2, 3, 4, 5]
        default: dayIndices = [1, 3, 5]
        }

        for dayIndex in dayIndices {
            schedule[dayIndex] = exerciseIds
        }

        return schedule
    }
}
