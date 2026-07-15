import XCTest

/// Exercises the live app shell: the custom `FloatingTabBar` (Home · Plan ·
/// Progress · Profile, plus a centre "New Assessment" button) and the assessment
/// gateway it presents. Replaces the retired Dashboard tests, which asserted a
/// system `UITabBar` with "Assess" / "My Plan" tabs that no longer ship — the live
/// UI hides the system tab bar and renders a custom SwiftUI bar of plain buttons.
final class ShellNavigationUITests: UITestBase {

    @MainActor
    func testFloatingTabBar_AllTabsExist() throws {
        // Each FloatingTabBar item is exposed as a plain accessibility button.
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10), "Home tab should exist")
        XCTAssertTrue(app.buttons["Plan"].exists, "Plan tab should exist")
        XCTAssertTrue(app.buttons["Progress"].exists, "Progress tab should exist")
        XCTAssertTrue(app.buttons["Profile"].exists, "Profile tab should exist")
        XCTAssertTrue(app.buttons["New Assessment"].exists, "Centre assessment button should exist")

        captureScreenshot(name: "Shell-FloatingTabBar")
    }

    @MainActor
    func testNewAssessment_OpensGateway() throws {
        let assessButton = app.buttons["New Assessment"]
        XCTAssertTrue(assessButton.waitForExistence(timeout: 10))
        assessButton.tap()

        // The dual gateway chooser appears in a full-screen cover.
        XCTAssertTrue(
            staticText("What Can We Help With?").waitForExistence(timeout: 5),
            "Gateway chooser header should appear"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["gateway.somethingHurtsButton"].waitForExistence(timeout: 3),
            "Something Hurts card should exist"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["gateway.improveLifeButton"].waitForExistence(timeout: 3),
            "Improve My Life card should exist (a mock profile is seeded)"
        )

        captureScreenshot(name: "Shell-AssessmentGateway")
    }

    @MainActor
    func testSomethingHurts_NavigatesToBodyMap() throws {
        let assessButton = app.buttons["New Assessment"]
        XCTAssertTrue(assessButton.waitForExistence(timeout: 10))
        assessButton.tap()

        let somethingHurts = app.descendants(matching: .any)["gateway.somethingHurtsButton"]
        XCTAssertTrue(somethingHurts.waitForExistence(timeout: 5))
        somethingHurts.tap()

        // Picking the pain path swaps the body map in place (BodyMap3DView). Its
        // header overlay renders immediately, independent of the 3D model load.
        XCTAssertTrue(
            staticText("Where does it hurt?").waitForExistence(timeout: 10) ||
            staticText("Tap a body zone to zoom in").waitForExistence(timeout: 3) ||
            app.descendants(matching: .any)["bodyMap.chooseFromListButton"].waitForExistence(timeout: 3),
            "Should land on the body map"
        )

        captureScreenshot(name: "Shell-BodyMap")
    }

    @MainActor
    func testPlanTab_ShowsContent() throws {
        tapTab("Plan")

        // With seeded data, MyPlanTab shows its Injury/Wellness type picker and the
        // seeded plan's hero card.
        XCTAssertTrue(
            app.descendants(matching: .any)["myPlan.typePicker"].waitForExistence(timeout: 10) ||
            app.descendants(matching: .any)["myPlan.startWorkoutButton"].waitForExistence(timeout: 5),
            "Plan tab should show plan content"
        )

        captureScreenshot(name: "Shell-PlanTab")
    }

    @MainActor
    func testProfileTab_ShowsSettings() throws {
        tapTab("Profile")

        // The Profile tab hosts SettingsView directly.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.appearancePicker"].waitForExistence(timeout: 10) ||
            app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 5),
            "Profile tab should show settings content"
        )

        captureScreenshot(name: "Shell-ProfileTab")
    }

    @MainActor
    func testOfflineBanner_ShowsWhenDisconnected() throws {
        // Relaunch with offline simulation, preserving the launch-crash workaround
        // (OS_ACTIVITY_MODE) that setUp installs.
        app.terminate()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--seed-mock-data", "--simulate-offline"]
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()

        assertExists("offlineBanner", timeout: 10)
        captureScreenshot(name: "Shell-OfflineBanner")
    }
}
