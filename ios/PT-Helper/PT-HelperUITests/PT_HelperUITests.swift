import XCTest

// MARK: - Onboarding UI Tests

final class OnboardingUITests: UITestBase {

    override var skipOnboarding: Bool { false }
    override var seedMockData: Bool { false }

    @MainActor
    func testFullFlow_CompletesAllSixSteps() throws {
        // Step 1: Basic Info
        assertExists("onboarding.stepIndicator")
        XCTAssertTrue(staticText("Step 1 of 6").exists)

        // Fill basic info fields
        let firstNameField = app.textFields["First Name"]
        if firstNameField.waitForExistence(timeout: 3) {
            firstNameField.tap()
            firstNameField.typeText("Test")
        }

        let lastNameField = app.textFields["Last Name"]
        if lastNameField.exists {
            lastNameField.tap()
            lastNameField.typeText("User")
        }

        // Tap continue to advance
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        if continueButton.waitForExistence(timeout: 3), continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 2: Medical History
        XCTAssertTrue(staticText("Step 2 of 6").waitForExistence(timeout: 3))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 3: Surgical History
        XCTAssertTrue(staticText("Step 3 of 6").waitForExistence(timeout: 3))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 4: Injuries
        XCTAssertTrue(staticText("Step 4 of 6").waitForExistence(timeout: 3))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 5: Activity Level
        XCTAssertTrue(staticText("Step 5 of 6").waitForExistence(timeout: 3))
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
        // Advance to step 3
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        if continueButton.waitForExistence(timeout: 3) {
            // Step 1 → 2
            if continueButton.isEnabled { continueButton.tap() }
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
