import XCTest

// MARK: - Onboarding UI Tests

final class OnboardingUITests: UITestBase {

    override var skipOnboarding: Bool { false }
    override var seedMockData: Bool { false }
    override var additionalLaunchArguments: [String] { ["--prefill-weight"] }

    /// Dismiss the software keyboard if it's showing.
    @MainActor
    private func dismissKeyboard() {
        // Tap on the step indicator area at the top, which is always visible and non-interactive
        let stepIndicator = app.descendants(matching: .any)["onboarding.stepIndicator"]
        if stepIndicator.exists {
            stepIndicator.tap()
        }
    }

    /// Fill all required Step 1 fields so the Continue button becomes enabled.
    @MainActor
    private func fillStep1RequiredFields() {
        // First Name — tap and type
        let firstNameField = app.textFields["First Name"]
        if firstNameField.waitForExistence(timeout: 3) {
            firstNameField.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
            firstNameField.typeText("Test")
        }

        // Last Name — tap directly (keyboard already up from first field)
        let lastNameField = app.textFields["Last Name"]
        if lastNameField.waitForExistence(timeout: 3) {
            lastNameField.tap()
            lastNameField.typeText("User")
        }

        // Dismiss keyboard by tapping the step indicator
        dismissKeyboard()

        // Sex — tap "Male" chip
        let maleButton = button("Male")
        if maleButton.waitForExistence(timeout: 3) {
            maleButton.tap()
        }

        // Height uses default 5ft 7in which passes validation.
        // Weight is pre-filled to 170 via --prefill-weight launch argument.

        // Accept Terms of Service checkbox (required for Continue)
        app.swipeUp()
        let termsCheckbox = app.descendants(matching: .any)["onboarding.termsCheckbox"]
        if termsCheckbox.waitForExistence(timeout: 3) {
            termsCheckbox.tap()
        }
    }

    @MainActor
    func testFullFlow_CompletesAllSixSteps() throws {
        // Step 1: Basic Info
        assertExists("onboarding.stepIndicator")
        XCTAssertTrue(staticText("Step 1 of 6").exists)

        // Fill all required fields
        fillStep1RequiredFields()

        // Dismiss keyboard and scroll to reveal Continue button
        dismissKeyboard()
        app.swipeUp()

        // Wait for validation to enable Continue, then tap
        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))

        // Wait for button to become enabled after field validation
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: continueButton)
        let result = XCTWaiter.wait(for: [expectation], timeout: 5)
        XCTAssertTrue(result == .completed, "Continue button should become enabled after filling required fields")

        continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Step 2: Medical History (optional step)
        XCTAssertTrue(staticText("Step 2 of 6").waitForExistence(timeout: 5))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 3: Surgical History (optional step)
        XCTAssertTrue(staticText("Step 3 of 6").waitForExistence(timeout: 5))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 4: Injuries (optional step)
        XCTAssertTrue(staticText("Step 4 of 6").waitForExistence(timeout: 5))
        if continueButton.exists, continueButton.isEnabled {
            continueButton.tap()
        }

        // Step 5: Activity Level — select a level
        XCTAssertTrue(staticText("Step 5 of 6").waitForExistence(timeout: 5))
        let moderateButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Moderately'")).firstMatch
        if moderateButton.waitForExistence(timeout: 3) {
            moderateButton.tap()
        }
        if continueButton.exists, continueButton.isEnabled {
            continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // Step 6: Review & Submit
        XCTAssertTrue(staticText("Step 6 of 6").waitForExistence(timeout: 5))

        captureScreenshot(name: "Onboarding-Step6-Review")
    }

    @MainActor
    func testSkipButton_GoesToMainView() throws {
        let skipButton = app.descendants(matching: .any)["onboarding.skipButton"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 3))
        skipButton.tap()

        // Should land on the main tab view (Dashboard or legacy tabs)
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should appear after skipping onboarding")
    }

    @MainActor
    func testBackButton_NavigatesToPreviousStep() throws {
        // Fill step 1 required fields and advance
        fillStep1RequiredFields()
        dismissKeyboard()
        app.swipeUp()

        let continueButton = app.descendants(matching: .any)["onboarding.continueButton"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))

        // Wait for button to become enabled after field validation
        let enabledPredicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: enabledPredicate, object: continueButton)
        _ = XCTWaiter.wait(for: [expectation], timeout: 5)

        if continueButton.isEnabled {
            // Step 1 → 2
            continueButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            _ = staticText("Step 2 of 6").waitForExistence(timeout: 5)
            // Step 2 → 3
            if continueButton.isEnabled { continueButton.tap() }
            _ = staticText("Step 3 of 6").waitForExistence(timeout: 5)
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
