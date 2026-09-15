import XCTest

/// Covers the Home tab (week strip + today's program).
final class HomeTabUITests: UITestBase {

    @MainActor
    func testWeekStrip_announcesEachDayWithCompletionState() throws {
        // Home is the launch tab. Each day cell was three separate elements ("TUE", "8",
        // an unlabeled dot); it should be one element ending in its completion state.
        let predicate = NSPredicate(format: "label ENDSWITH %@ OR label ENDSWITH %@",
                                    "no workout", "workout completed")
        let cells = app.descendants(matching: .any).matching(predicate)
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "Day cells should be labelled")
        XCTAssertEqual(cells.count, 7, "One combined element per day in the 7-day strip")
    }

    @MainActor
    func testStartWorkoutButton_existsOnRestAndTrainingDays() throws {
        // The seeded Knee plan trains Sun/Tue/Thu. On a rest day the CTA moves into the
        // rest-day card as "Start a workout anyway" but keeps the same identifier, so
        // this assertion holds whichever weekday the suite runs on.
        assertExists("home.startWorkoutButton", timeout: 10)
        let weekday = Calendar.current.component(.weekday, from: Date())   // 1 = Sunday
        let isTrainingDay = [1, 3, 5].contains(weekday)
        if isTrainingDay {
            let todayCount = app.staticTexts.matching(
                NSPredicate(format: "label ENDSWITH %@", "today")).firstMatch   // "N exercises today"
            XCTAssertTrue(todayCount.waitForExistence(timeout: 5), "Training day should show today's exercise count")
        } else {
            XCTAssertTrue(staticText("Rest day").waitForExistence(timeout: 5), "Rest day should show the rest-day card")
        }
    }
}
