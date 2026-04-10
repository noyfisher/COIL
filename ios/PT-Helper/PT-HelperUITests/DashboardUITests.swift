import XCTest

final class DashboardUITests: UITestBase {

    @MainActor
    func testThreeTabs_Exist() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        XCTAssertTrue(tabBar.buttons["Assess"].exists, "Assess tab should exist")
        XCTAssertTrue(tabBar.buttons["My Plan"].exists, "My Plan tab should exist")
        XCTAssertTrue(tabBar.buttons["Progress"].exists, "Progress tab should exist")

        captureScreenshot(name: "ThreeTab-Layout")
    }

    @MainActor
    func testAssessTab_GatewayCardsLoad() throws {
        // The Assess tab should show gateway cards
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 5)

        // Gateway section header
        XCTAssertTrue(
            staticText("What can we help with?").waitForExistence(timeout: 5),
            "Gateway section should be visible"
        )

        // Both gateway cards should exist
        let somethingHurts = app.descendants(matching: .any)["assess.somethingHurtsButton"]
        XCTAssertTrue(somethingHurts.waitForExistence(timeout: 3), "Something Hurts card should exist")

        let improveLife = app.descendants(matching: .any)["assess.improveLifeButton"]
        XCTAssertTrue(improveLife.waitForExistence(timeout: 3), "Improve My Life card should exist")

        captureScreenshot(name: "AssessTab-GatewayCards")
    }

    @MainActor
    func testMyPlanTab_ShowsContent() throws {
        tapTab("My Plan")

        XCTAssertTrue(
            app.navigationBars["My Plan"].waitForExistence(timeout: 5) ||
            staticText("Knee Rehab Plan").waitForExistence(timeout: 5) ||
            staticText("No Plan Yet").waitForExistence(timeout: 5),
            "My Plan tab should show plan content or empty state"
        )

        captureScreenshot(name: "MyPlanTab-Content")
    }

    @MainActor
    func testSomethingHurts_NavigatesToBodyMap() throws {
        let somethingHurtsButton = app.descendants(matching: .any)["assess.somethingHurtsButton"]
        XCTAssertTrue(somethingHurtsButton.waitForExistence(timeout: 5))
        somethingHurtsButton.tap()

        // Should navigate to body map
        XCTAssertTrue(
            staticText("Where does it hurt?").waitForExistence(timeout: 5) ||
            app.navigationBars["Body Map"].waitForExistence(timeout: 5) ||
            staticText("Tap a body zone to zoom in").waitForExistence(timeout: 5),
            "Should navigate to body map view"
        )

        captureScreenshot(name: "AssessTab-NavigateToBodyMap")
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
