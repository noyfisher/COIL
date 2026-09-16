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

    /// Scroll the Progress ScrollView until `element` sits fully above the floating tab
    /// bar. XCUI reports a partially covered element as hittable and may then tap the
    /// covered part, so `isHittable` alone is not enough here.
    @MainActor
    @discardableResult
    private func scrollClearOfTabBar(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        let barTop = app.buttons["Home"].frame.minY
        var swipes = 0
        while element.frame.maxY > barTop && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.isHittable && element.frame.maxY <= barTop
    }

    @MainActor
    func testActionTiles_navigateToLogWorkoutAndNotes() throws {
        tapTab("Progress")

        // Identifier on a NavigationLink: query `.any`, the file convention for
        // container identifiers (see `progress.streakBadge` above).
        let logTile = app.descendants(matching: .any)["progress.logWorkoutTile"].firstMatch
        XCTAssertTrue(scrollClearOfTabBar(logTile), "Log Workout tile should scroll into view")
        XCTAssertTrue(app.descendants(matching: .any)["progress.notesTile"].firstMatch.exists,
                      "Recovery Notes tile should exist")
        logTile.tap()
        let workoutBar = app.navigationBars["Workout Session"]
        XCTAssertTrue(workoutBar.waitForExistence(timeout: 5),
                      "Log Workout tile should push the workout session screen")
        workoutBar.buttons.element(boundBy: 0).tap()

        let notesTile = app.descendants(matching: .any)["progress.notesTile"].firstMatch
        XCTAssertTrue(scrollClearOfTabBar(notesTile), "Recovery Notes tile should scroll into view")
        notesTile.tap()
        XCTAssertTrue(app.navigationBars["Recovery Notes"].waitForExistence(timeout: 5),
                      "Recovery Notes tile should push the notes screen")

        captureScreenshot(name: "Progress-ActionTiles")
    }

    @MainActor
    func testOutcomeBanner_expandsToOptions() throws {
        tapTab("Progress")
        // The seeded Knee plan started 10 days ago, so the prompt is eligible unless
        // this simulator already recorded a rating (persisted UserDefaults state).
        let expand = app.buttons["outcomePrompt.expand"]
        guard scrollClearOfTabBar(expand) else {
            throw XCTSkip("Outcome prompt already answered in this simulator's persisted state")
        }
        XCTAssertFalse(app.buttons["outcomePrompt.accurate"].exists,
                       "Rating options stay collapsed until the row is tapped")
        expand.tap()
        XCTAssertTrue(app.buttons["outcomePrompt.accurate"].waitForExistence(timeout: 3),
                      "Tapping the banner row should reveal the rating options")

        captureScreenshot(name: "Progress-OutcomeBannerExpanded")
    }
}
