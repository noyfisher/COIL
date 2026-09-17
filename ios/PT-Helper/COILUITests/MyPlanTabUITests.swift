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

    @MainActor
    func testPlanCard_isExposedAsButtonAndOpensPlan() throws {
        tapTab("Plan")

        // The card's open action was an onTapGesture with no accessibility trait, so
        // VoiceOver had no way to open a plan.
        let cardButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Knee Rehab Plan, 6 weeks")).firstMatch
        XCTAssertTrue(cardButton.waitForExistence(timeout: 10), "Plan card should be exposed as a button")

        let name = app.descendants(matching: .any)["myPlan.planCard"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        assertExists("rehabPlan.editButton", timeout: 10)
        captureScreenshot(name: "MyPlan-CardOpensPlan")
    }

    @MainActor
    func testRehabPlan_exerciseCardsHaveUniqueIdentifiers() throws {
        tapTab("Plan")
        let name = app.descendants(matching: .any)["myPlan.planCard"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Seeded Knee plan has three exercises.
        assertExists("rehabPlan.exerciseName.0", timeout: 10)
        assertExists("rehabPlan.exerciseName.2")

        // The whole card used to inherit the swap button's identifier, so the id
        // matched six elements (three cards + three buttons) instead of three.
        let swapButtons = app.buttons.matching(identifier: "rehabPlan.swapExerciseButton")
        XCTAssertEqual(swapButtons.count, 3, "Only the three swap buttons should carry the swap identifier")
    }
}
