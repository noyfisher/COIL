import XCTest

final class SettingsUITests: UITestBase {

    /// Open the Settings sheet from the Progress tab's toolbar gear.
    @MainActor
    private func navigateToSettings() {
        tapTab("Progress")

        // Settings lives behind the gear button in the Progress toolbar.
        let gearButton = app.buttons["progress.settingsButton"]
        XCTAssertTrue(gearButton.waitForExistence(timeout: 10),
                      "Settings gear should appear in the Progress toolbar")
        gearButton.tap()

        // The sheet has fully presented once a known settings control exists.
        XCTAssertTrue(app.buttons["settings.appearancePicker"].waitForExistence(timeout: 5) ||
                      app.otherElements["settings.appearancePicker"].waitForExistence(timeout: 2) ||
                      app.buttons["settings.signOutButton"].waitForExistence(timeout: 5),
                      "Settings sheet should present")
    }

    /// Scroll the settings ScrollView up until `element` is hittable (it exists in
    /// the tree from the start but may sit below the fold).
    @MainActor
    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.isHittable
    }

    @MainActor
    func testSettings_AllOptions_Displayed() throws {
        navigateToSettings()

        // Appearance picker is new in the COIL rebrand — assert it's present.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.appearancePicker"].waitForExistence(timeout: 5),
            "Appearance picker should be visible in Settings"
        )

        // Sign Out lives further down the sheet but is in the tree from the start.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 5),
            "Sign Out option should be present"
        )

        captureScreenshot(name: "Settings-AllOptions")
    }

    @MainActor
    func testSettings_SignOut_ShowsConfirmation() throws {
        navigateToSettings()

        let signOut = app.descendants(matching: .any)["settings.signOutButton"]
        XCTAssertTrue(scrollToHittable(signOut), "Sign Out button should scroll into view")
        signOut.tap()

        // Confirmation dialog should appear.
        XCTAssertTrue(
            staticText("Are you sure you want to sign out?").waitForExistence(timeout: 3),
            "Sign out confirmation should appear"
        )

        captureScreenshot(name: "Settings-SignOutConfirmation")
    }

    @MainActor
    func testSettings_DeleteAccount_ShowsConfirmation() throws {
        navigateToSettings()

        // The delete button sits in the "Danger zone" at the very bottom of the sheet.
        let deleteAccount = app.descendants(matching: .any)["settings.deleteAccountButton"]
        XCTAssertTrue(scrollToHittable(deleteAccount), "Delete Account button should scroll into view")
        deleteAccount.tap()

        // Destructive confirmation dialog should appear with the "Delete Everything" action.
        XCTAssertTrue(
            app.buttons["Delete Everything"].waitForExistence(timeout: 5),
            "Delete account confirmation should appear"
        )

        captureScreenshot(name: "Settings-DeleteConfirmation")
    }
}
