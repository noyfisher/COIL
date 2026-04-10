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
        tapTab("My Plan")

        // Wait for My Plan tab to fully load
        _ = app.navigationBars["My Plan"].waitForExistence(timeout: 5)

        // In the 3-tab layout, the "Start Guided Workout" CTA is directly visible
        // on the hero card — no need to scroll through metrics
        let startButton = app.descendants(matching: .any)["myPlan.startWorkoutButton"]
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
        } else {
            // Fallback: find by label text
            let startByLabel = button("Start Guided Workout")
            if startByLabel.waitForExistence(timeout: 3) {
                startByLabel.tap()
            }
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

        let pauseButton = app.buttons["workout.pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 10))

        // Tap pause
        pauseButton.tap()
        captureScreenshot(name: "Workout-Paused")

        // Tap play (same button, toggled)
        let resumeButton = app.buttons["workout.pauseButton"]
        _ = resumeButton.waitForExistence(timeout: 3)
        resumeButton.tap()
        captureScreenshot(name: "Workout-Resumed")
    }

    @MainActor
    func testEndEarly_ShowsConfirmation() throws {
        navigateToWorkout()

        let endButton = app.buttons["workout.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 10))
        endButton.tap()

        // Should show confirmation dialog
        XCTAssertTrue(staticText("End Workout?").waitForExistence(timeout: 3),
                      "End workout confirmation should appear")

        // Verify both save and discard options exist
        XCTAssertTrue(button("End & Save").exists, "End & Save button should exist")
        XCTAssertTrue(button("Discard Workout").exists, "Discard Workout button should exist")

        captureScreenshot(name: "Workout-EndConfirmation")
    }

    @MainActor
    func testDiscardWorkout_DismissesWithoutSaving() throws {
        navigateToWorkout()

        let endButton = app.buttons["workout.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 10))
        endButton.tap()

        // Tap Discard
        let discardButton = button("Discard Workout")
        XCTAssertTrue(discardButton.waitForExistence(timeout: 3))
        discardButton.tap()

        // Should dismiss back to My Plan tab
        XCTAssertTrue(
            app.navigationBars["My Plan"].waitForExistence(timeout: 5) ||
            staticText("Knee Rehab Plan").waitForExistence(timeout: 5),
            "Should return to My Plan after discarding"
        )

        captureScreenshot(name: "Workout-DiscardedBackToPlan")
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
