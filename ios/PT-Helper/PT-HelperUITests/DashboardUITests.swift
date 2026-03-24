import XCTest

final class DashboardUITests: UITestBase {

    @MainActor
    func testThreeTabs_Exist() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        XCTAssertTrue(tabBar.buttons["Dashboard"].exists, "Dashboard tab should exist")
        XCTAssertTrue(tabBar.buttons["Rehab"].exists, "Rehab tab should exist")
        XCTAssertTrue(tabBar.buttons["Profile"].exists, "Profile tab should exist")

        captureScreenshot(name: "Dashboard-ThreeTabs")
    }

    @MainActor
    func testDashboard_WidgetsLoad() throws {
        // The dashboard tab should show widgets with seeded data
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 5)

        // Verify key content is visible
        XCTAssertTrue(staticText("Quick Actions").waitForExistence(timeout: 5),
                      "Quick Actions section should be visible")
        assertExists("dashboard.newAnalysisButton")

        captureScreenshot(name: "Dashboard-Widgets")
    }

    @MainActor
    func testRehabTab_ShowsMetrics() throws {
        tapTab("Rehab")

        // Should show rehab metrics content
        let rehabContent = app.navigationBars["Rehab"].firstMatch
        // Look for any rehab-specific text
        XCTAssertTrue(
            staticText("Adherence").waitForExistence(timeout: 5) ||
            staticText("Active Plans").waitForExistence(timeout: 5),
            "Rehab tab should show metrics content"
        )

        captureScreenshot(name: "Dashboard-RehabTab")
    }

    @MainActor
    func testNewAnalysis_NavigatesToBodyMap() throws {
        let newAnalysisButton = app.descendants(matching: .any)["dashboard.newAnalysisButton"]
        XCTAssertTrue(newAnalysisButton.waitForExistence(timeout: 5))
        newAnalysisButton.tap()

        // Should navigate to body map
        XCTAssertTrue(
            staticText("Select Pain Areas").waitForExistence(timeout: 5) ||
            app.navigationBars["Analyze"].waitForExistence(timeout: 5) ||
            staticText("Tap to select").waitForExistence(timeout: 5),
            "Should navigate to body map view"
        )

        captureScreenshot(name: "Dashboard-NavigateToBodyMap")
    }

    @MainActor
    func testOfflineBanner_ShowsWhenDisconnected() throws {
        // Relaunch with offline simulation
        app.terminate()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--seed-mock-data", "--simulate-offline"]
        app.launch()

        assertExists("offlineBanner", timeout: 5)
        captureScreenshot(name: "Dashboard-OfflineBanner")
    }
}
