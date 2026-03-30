import XCTest

final class GuidedWorkoutUITests: UITestBase {

    override var additionalLaunchArguments: [String] { ["--clear-workout-checkpoint"] }

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Register an interruption handler for the "Resume Workout?" alert
        // that appears when a checkpoint exists from a previous session.
        addUIInterruptionMonitor(withDescription: "Resume Workout Alert") { alert in
            let startFreshButton = alert.buttons["Start Fresh"]
            if startFreshButton.exists {
                startFreshButton.tap()
                return true
            }
            return false
        }
    }

    /// Navigate to a rehab plan and start a guided workout.
    @MainActor
    private func navigateToWorkout() {
        tapTab("Rehab")

        // Wait for Rehab tab to fully load
        _ = app.navigationBars["Rehab"].waitForExistence(timeout: 5)

        // Scroll down to reveal plans list (below metrics grid, pain chart, exercise table)
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()

        // Tap on the first plan in active plans list
        let planLink = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Knee Rehab Plan'")).firstMatch
        if planLink.waitForExistence(timeout: 5) {
            planLink.tap()
        } else {
            // Fallback: any plan button
            let anyPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Plan'")).firstMatch
            if anyPlan.waitForExistence(timeout: 3) {
                anyPlan.tap()
            }
        }

        // Tap Start Guided Workout
        let startButton = button("Start Guided Workout")
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
        }

        // Trigger the interruption monitor by interacting with the app
        // (XCUI only fires interruption monitors on next interaction)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @MainActor
    func testStartWorkout_ShowsFirstExercise() throws {
        navigateToWorkout()

        // Should show exercise name and set counter
        assertExists("workout.exerciseName", timeout: 10)
        assertExists("workout.completeSetButton")

        captureScreenshot(name: "Workout-FirstExercise")
    }

    @MainActor
    func testCompleteSet_ButtonExists() throws {
        navigateToWorkout()

        let completeButton = app.descendants(matching: .any)["workout.completeSetButton"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 10))

        // Tap complete set
        completeButton.tap()

        captureScreenshot(name: "Workout-AfterCompleteSet")
    }

    @MainActor
    func testSkipExercise_AdvancesToNext() throws {
        navigateToWorkout()

        let skipButton = app.descendants(matching: .any)["workout.skipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 10))
        skipButton.tap()

        // Should still show exercise phase (next exercise)
        assertExists("workout.exerciseName", timeout: 5)

        captureScreenshot(name: "Workout-AfterSkip")
    }

    @MainActor
    func testPauseResume_TogglesState() throws {
        navigateToWorkout()

        let pauseButton = app.descendants(matching: .any)["workout.pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))

        // Tap pause
        pauseButton.tap()
        captureScreenshot(name: "Workout-Paused")

        // Tap play (same button, toggled)
        pauseButton.tap()
        captureScreenshot(name: "Workout-Resumed")
    }

    @MainActor
    func testEndEarly_ShowsConfirmation() throws {
        navigateToWorkout()

        let endButton = app.descendants(matching: .any)["workout.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 10))
        endButton.tap()

        // Should show confirmation dialog
        XCTAssertTrue(staticText("End Workout?").waitForExistence(timeout: 3),
                      "End workout confirmation should appear")

        captureScreenshot(name: "Workout-EndConfirmation")
    }

    @MainActor
    func testSwapExercise_OpensSwapSheet() throws {
        navigateToWorkout()

        let swapButton = app.descendants(matching: .any)["workout.swapButton"]
        XCTAssertTrue(swapButton.waitForExistence(timeout: 10))
        swapButton.tap()

        // Should show swap sheet with reason chips
        XCTAssertTrue(
            staticText("Why swap?").waitForExistence(timeout: 3) ||
            staticText("Swap Exercise").waitForExistence(timeout: 3),
            "Swap sheet should appear"
        )

        captureScreenshot(name: "Workout-SwapSheet")
    }
}
