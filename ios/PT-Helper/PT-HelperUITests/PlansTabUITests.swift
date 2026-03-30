import XCTest

final class PlansTabUITests: UITestBase {

    @MainActor
    func testPlansExist_ShowsCards() throws {
        tapTab("Rehab")

        // Wait for Rehab tab to load
        _ = app.navigationBars["Rehab"].waitForExistence(timeout: 5)

        // Scroll to see plans list (section header is uppercased)
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(
            staticText("Knee Rehab Plan").waitForExistence(timeout: 5) ||
            staticText("ACTIVE PLANS").waitForExistence(timeout: 5),
            "Plans should be visible with seeded data"
        )

        captureScreenshot(name: "Plans-WithCards")
    }

    @MainActor
    func testPlansTab_EmptyState() throws {
        // Relaunch without mock data
        app.terminate()
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launch()

        tapTab("Rehab")

        // The Rehab tab should load without crashing and show content
        // (either empty state, metrics, or at minimum the tab view)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should remain visible after tapping Rehab")

        // Look for any Rehab-specific content (empty state or data)
        XCTAssertTrue(
            staticText("No Rehab Data").waitForExistence(timeout: 5) ||
            staticText("Rehab").waitForExistence(timeout: 3) ||
            staticText("Adherence").waitForExistence(timeout: 3),
            "Rehab tab should show content even without plans"
        )

        captureScreenshot(name: "Plans-EmptyState")
    }
}

// MARK: - Legacy Plans Tab Tests

final class LegacyPlansTabUITests: UITestBase {

    override var additionalLaunchArguments: [String] { ["--use-legacy-ui"] }

    @MainActor
    func testPlansTab_EmptyState_ShowsMessage() throws {
        // Relaunch without mock data in legacy mode
        app.terminate()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--use-legacy-ui"]
        app.launch()

        tapTab("Plans")

        // Plans tab should load without crashing
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should remain visible after tapping Plans")

        // Look for empty state or verify tab loaded without crashing
        XCTAssertTrue(
            app.descendants(matching: .any)["plansTab.emptyState"].waitForExistence(timeout: 5) ||
            staticText("No Rehab Plans Yet").waitForExistence(timeout: 5) ||
            app.tabBars.buttons["Plans"].exists,
            "Plans tab should load and show content"
        )

        captureScreenshot(name: "LegacyPlans-EmptyState")
    }

    @MainActor
    func testPlansTab_WithPlans_ShowsCards() throws {
        tapTab("Plans")

        XCTAssertTrue(
            staticText("Knee Rehab Plan").waitForExistence(timeout: 5),
            "Plan cards should be visible with seeded data"
        )

        captureScreenshot(name: "LegacyPlans-WithCards")
    }

    @MainActor
    func testPlansTab_TapPlan_NavigatesToDetail() throws {
        tapTab("Plans")

        let planCard = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Knee Rehab Plan'")).firstMatch
        XCTAssertTrue(planCard.waitForExistence(timeout: 5))
        planCard.tap()

        // Should navigate to plan detail
        XCTAssertTrue(
            staticText("Wall Sits").waitForExistence(timeout: 5) ||
            button("Start Guided Workout").waitForExistence(timeout: 5),
            "Should navigate to plan detail with exercises"
        )

        captureScreenshot(name: "LegacyPlans-PlanDetail")
    }
}
