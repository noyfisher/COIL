import XCTest

final class LegacyUITests: UITestBase {

    override var additionalLaunchArguments: [String] { ["--use-legacy-ui"] }

    @MainActor
    func testFourTabs_Exist() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        XCTAssertTrue(tabBar.buttons["Home"].exists, "Home tab should exist")
        XCTAssertTrue(tabBar.buttons["Analyze"].exists, "Analyze tab should exist")
        XCTAssertTrue(tabBar.buttons["Plans"].exists, "Plans tab should exist")
        XCTAssertTrue(tabBar.buttons["Progress"].exists, "Progress tab should exist")

        captureScreenshot(name: "Legacy-FourTabs")
    }

    @MainActor
    func testProgressTab_ShowsChart() throws {
        tapTab("Progress")

        // Progress tab should show chart or empty state
        XCTAssertTrue(
            staticText("Progress").waitForExistence(timeout: 5) ||
            staticText("Pain Trend").waitForExistence(timeout: 5) ||
            staticText("No data yet").waitForExistence(timeout: 5),
            "Progress tab should show content"
        )

        captureScreenshot(name: "Legacy-ProgressTab")
    }
}
