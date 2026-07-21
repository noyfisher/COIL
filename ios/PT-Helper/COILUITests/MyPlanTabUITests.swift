import XCTest

/// Covers the live "Plan" tab (`MyPlanTab`) reached from the FloatingTabBar.
/// Replaces the retired legacy PlansTab tests, which navigated via a system
/// "Plans" tab that no longer exists in the shipped 4-tab shell.
final class MyPlanTabUITests: UITestBase {

    @MainActor
    func testInjuryPlans_ShowWithSeededData() throws {
        tapTab("Plan")

        // Seeded data has two rehab plans (Knee Rehab, Shoulder Mobility), so the
        // Injury sub-tab (default) shows its type picker and a plan hero card.
        XCTAssertTrue(
            app.descendants(matching: .any)["myPlan.typePicker"].waitForExistence(timeout: 10),
            "Plan type picker should be visible"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["myPlan.startWorkoutButton"].waitForExistence(timeout: 5),
            "A plan hero card with a start-workout CTA should be visible"
        )

        captureScreenshot(name: "MyPlan-InjuryPlans")
    }

    @MainActor
    func testTypePicker_WellnessTab_EmptyState() throws {
        tapTab("Plan")

        let picker = app.descendants(matching: .any)["myPlan.typePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))

        // Switch to the Wellness segment. Seeded data has no wellness plans, so the
        // wellness empty state appears.
        let wellnessSegment = app.buttons["Wellness"]
        XCTAssertTrue(wellnessSegment.waitForExistence(timeout: 3), "Wellness segment should exist")
        wellnessSegment.tap()

        XCTAssertTrue(
            staticText("No Wellness Plans Yet").waitForExistence(timeout: 5),
            "Wellness empty state should appear when no wellness plans are seeded"
        )

        captureScreenshot(name: "MyPlan-WellnessEmpty")
    }

    @MainActor
    func testEmptyState_NoInjuryPlans() throws {
        // Relaunch without seeded plans, preserving the launch-crash workaround.
        app.terminate()
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()

        tapTab("Plan")

        // Injury sub-tab (default) with no plans shows its empty state.
        XCTAssertTrue(
            app.descendants(matching: .any)["myPlan.typePicker"].waitForExistence(timeout: 10),
            "Plan type picker should still render with no plans"
        )
        XCTAssertTrue(
            staticText("No Injury Plans Yet").waitForExistence(timeout: 5),
            "Injury empty state should appear with no seeded plans"
        )

        captureScreenshot(name: "MyPlan-EmptyState")
    }
}
