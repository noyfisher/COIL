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
}
