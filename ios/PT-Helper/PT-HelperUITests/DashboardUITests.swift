import XCTest

final class DashboardUITests: UITestBase {

    @MainActor
    func testFourTabs_Exist() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        XCTAssertTrue(tabBar.buttons["Dashboard"].exists, "Dashboard tab should exist")
        XCTAssertTrue(tabBar.buttons["Form Check"].exists, "Form Check tab should exist")
        XCTAssertTrue(tabBar.buttons["Rehab"].exists, "Rehab tab should exist")
        XCTAssertTrue(tabBar.buttons["Profile"].exists, "Profile tab should exist")

        captureScreenshot(name: "Dashboard-FourTabs")
    }

    @MainActor
    func testDashboard_WidgetsLoad() throws {
        // The dashboard tab should show widgets with seeded data
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 5)

        // Widget labels are uppercased by DashStatWidget
        XCTAssertTrue(
            staticText("TOP MATCH").waitForExistence(timeout: 5) ||
            staticText("ACTIVE PLANS").waitForExistence(timeout: 5),
            "Dashboard widget grid should be visible"
        )

        // Scroll down to reveal the gateway section (uppercased by DashSectionHeader)
        app.swipeUp()
        XCTAssertTrue(
            staticText("WHAT CAN WE HELP WITH?").waitForExistence(timeout: 3) ||
            app.descendants(matching: .any)["dashboard.somethingHurtsButton"].waitForExistence(timeout: 3),
            "Gateway section should be visible after scrolling"
        )

        captureScreenshot(name: "Dashboard-Widgets")
    }

    @MainActor
    func testRehabTab_ShowsMetrics() throws {
        tapTab("Rehab")

        // Metric labels are uppercased by DashStatWidget
        XCTAssertTrue(
            staticText("ADHERENCE").waitForExistence(timeout: 5) ||
            staticText("PLAN PROGRESS").waitForExistence(timeout: 5) ||
            staticText("No Rehab Data").waitForExistence(timeout: 5) ||
            app.navigationBars["Rehab"].waitForExistence(timeout: 5),
            "Rehab tab should show metrics content"
        )

        captureScreenshot(name: "Dashboard-RehabTab")
    }

    @MainActor
    func testSomethingHurts_NavigatesToBodyMap() throws {
        // Scroll down to reveal the gateway section
        app.swipeUp()

        let somethingHurtsButton = app.descendants(matching: .any)["dashboard.somethingHurtsButton"]
        XCTAssertTrue(somethingHurtsButton.waitForExistence(timeout: 5))
        somethingHurtsButton.tap()

        // Should navigate to body map
        XCTAssertTrue(
            staticText("Where does it hurt?").waitForExistence(timeout: 5) ||
            app.navigationBars["Body Map"].waitForExistence(timeout: 5) ||
            staticText("Tap a body zone to zoom in").waitForExistence(timeout: 5),
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
