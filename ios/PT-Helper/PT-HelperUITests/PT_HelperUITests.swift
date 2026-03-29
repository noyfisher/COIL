import XCTest

// MARK: - Onboarding UI Tests

final class OnboardingUITests: UITestBase {

    override var skipOnboarding: Bool { false }
    override var seedMockData: Bool { false }

    /// Fill all required Step 1 fields so the Continue button becomes enabled.
    @MainActor
    private func fillStep1RequiredFields() {
        // First Name
        let firstNameField = app.textFields["First Name"]
        if firstNameField.waitForExistence(timeout: 3) {
            firstNameField.tap()
            firstNameField.typeText("Test")
        }

        // Last Name
        let lastNameField = app.textFields["Last Name"]
        if lastNameField.exists {
            lastNameField.tap()
            lastNameField.typeText("User")
        }

        // Dismiss keyboard
        app.swipeDown()

        // Scroll down to see Sex, Height, and Weight fields
        app.swipeUp()

        // Sex — tap "Male" chip
        let maleButton = button("Male")
        if maleButton.waitForExistence(timeout: 3) {
            maleButton.tap()
        }

        // Height — tap feet menu then select 5 ft
        let feetMenu = app.buttons.matching(NSPredicate(format: "label CONTAINS 'ft'")).firstMatch
        if feetMenu.waitForExistence(timeout: 3) {
            feetMenu.tap()
            let fiveFeet = button("5 ft")
            if fiveFeet.waitForExistence(timeout: 3) {
                fiveFeet.tap()
            }
        }

        // Scroll down more for weight
        app.swipeUp()

        // Weight — type 170
        let weightField = app.textFields["Enter weight"]
        if weightField.waitForExistence(timeout: 3) {
            weightField.tap()
            weightField.typeText("170")
        }

        // Dismiss keyboard
        app.swipeDown()
    }

    @MainActor
    func testFullFlow_CompletesAllSixSteps() throws {
        // Step 1: Basic Info
        assertExists("onboarding.stepIndicator")
        XCTAssertTrue(staticText("Step 1 of 6").exists)

        // Fill all required fields
        fillStep1RequiredFields()

        // Tap continue to advance
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        if continueButton.isEnabled { continueButton.tap() }

        // Step 2: Medical History (optional step)
        XCTAssertTrue(staticText("Step 2 of 6").waitForExistence(timeout: 3))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 3: Surgical History (optional step)
        XCTAssertTrue(staticText("Step 3 of 6").waitForExistence(timeout: 3))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 4: Injuries (optional step)
        XCTAssertTrue(staticText("Step 4 of 6").waitForExistence(timeout: 3))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 5: Activity Level — select a level
        XCTAssertTrue(staticText("Step 5 of 6").waitForExistence(timeout: 3))
        let moderateButton = button("Moderate")
        if moderateButton.waitForExistence(timeout: 3) {
            moderateButton.tap()
        }
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 6: Review & Submit
        XCTAssertTrue(staticText("Step 6 of 6").waitForExistence(timeout: 3))

        captureScreenshot(name: "Onboarding-Step6-Review")
    }

    @MainActor
    func testSkipButton_GoesToMainView() throws {
        let skipButton = app.descendants(matching: .any)["onboarding.skipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 3))
        skipButton.tap()

        // Should land on the main tab view (Dashboard or legacy tabs)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Tab bar should appear after skipping onboarding")
    }

    @MainActor
    func testBackButton_NavigatesToPreviousStep() throws {
        // Fill step 1 required fields and advance
        fillStep1RequiredFields()

        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        if continueButton.waitForExistence(timeout: 3), continueButton.isEnabled {
            // Step 1 → 2
            continueButton.tap()
            _ = staticText("Step 2 of 6").waitForExistence(timeout: 3)
            // Step 2 → 3
            if continueButton.isEnabled { continueButton.tap() }
            _ = staticText("Step 3 of 6").waitForExistence(timeout: 3)
        }

        // Go back twice
        let backButton = app.descendants(matching: .any)["onboarding.backButton"]
        XCTAssertTrue(backButton.exists)
        backButton.tap()
        XCTAssertTrue(staticText("Step 2 of 6").waitForExistence(timeout: 3))
        backButton.tap()
        XCTAssertTrue(staticText("Step 1 of 6").waitForExistence(timeout: 3))
    }

    @MainActor
    func testContinueDisabled_WhenRequiredFieldsMissing() throws {
        // On step 1 with no fields filled, Continue should be disabled
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3))
        XCTAssertFalse(continueButton.isEnabled, "Continue should be disabled before required fields are filled")
    }
}
