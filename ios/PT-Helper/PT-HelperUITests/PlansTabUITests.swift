import XCTest

final class PlansTabUITests: UITestBase {

    @MainActor
    func testPlansExist_ShowsCards() throws {
        tapTab("Rehab")

        // With seeded mock data, plans should be visible
        XCTAssertTrue(
            staticText("Knee Rehab Plan").waitForExistence(timeout: 5) ||
            staticText("Active Plans").waitForExistence(timeout: 5),
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

        // Should show some content even without plans (empty state or metrics)
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

        let emptyState = app.descendants(matching: .any)["plansTab.emptyState"]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5) ||
            staticText("No Rehab Plans Yet").waitForExistence(timeout: 5),
            "Empty state should be shown when no plans exist"
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
