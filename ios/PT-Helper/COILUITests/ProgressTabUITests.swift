import XCTest

/// Covers the Progress tab's toolbar and top-of-page content.
final class ProgressTabUITests: UITestBase {

    @MainActor
    func testStreakBadge_hasDescriptiveLabel() throws {
        tapTab("Progress")
        // Seeded streak is 3; the badge used to announce just "3". Query by identifier
        // (file convention), then check the spoken name.
        let badge = app.descendants(matching: .any)["progress.streakBadge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 10), "Streak badge should exist")
        XCTAssertEqual(badge.label, "3 day streak, view achievements",
                       "Streak badge should say what the number means and where it goes")
    }
}
