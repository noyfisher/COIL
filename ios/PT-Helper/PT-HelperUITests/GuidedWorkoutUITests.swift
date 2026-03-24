import XCTest

final class GuidedWorkoutUITests: UITestBase {

    /// Navigate to a rehab plan and start a guided workout.
    @MainActor
    private func navigateToWorkout() {
        tapTab("Rehab")

        // Tap on the first plan in active plans list
        let planLink = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Knee Rehab Plan'")).firstMatch
        if planLink.waitForExistence(timeout: 5) {
            planLink.tap()
        }

        // Tap Start Guided Workout
        let startButton = button("Start Guided Workout")
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
        }
    }

    @MainActor
    func testStartWorkout_ShowsFirstExercise() throws {
        navigateToWorkout()

        // Should show exercise name and set counter
        assertExists("workout.exerciseName", timeout: 5)
        assertExists("workout.completeSetButton")

        captureScreenshot(name: "Workout-FirstExercise")
    }

    @MainActor
    func testCompleteSet_ButtonExists() throws {
        navigateToWorkout()

        let completeButton = app.descendants(matching: .any)["workout.completeSetButton"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))

        // Tap complete set
        completeButton.tap()

        captureScreenshot(name: "Workout-AfterCompleteSet")
    }

    @MainActor
    func testSkipExercise_AdvancesToNext() throws {
        navigateToWorkout()

        let skipButton = app.descendants(matching: .any)["workout.skipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        // Should still show exercise phase (next exercise)
        assertExists("workout.exerciseName", timeout: 5)

        captureScreenshot(name: "Workout-AfterSkip")
    }

    @MainActor
    func testPauseResume_TogglesState() throws {
        navigateToWorkout()

        let pauseButton = app.descendants(matching: .any)["workout.pauseButton"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 5))

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
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
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
        XCTAssertTrue(swapButton.waitForExistence(timeout: 5))
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
