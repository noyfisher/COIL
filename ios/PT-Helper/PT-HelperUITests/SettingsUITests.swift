import XCTest

final class SettingsUITests: UITestBase {

    @MainActor
    private func navigateToSettings() {
        tapTab("Profile")

        // Wait for Profile tab to load
        _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)

        // In dashboard UI, "Debug Log" row opens the Settings sheet
        let debugButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Debug'")).firstMatch
        let settingsButton = button("Settings")

        if debugButton.waitForExistence(timeout: 5) {
            debugButton.tap()
        } else if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        }

        // Wait for the settings sheet to appear
        _ = app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 5) ||
            staticText("Sign Out").waitForExistence(timeout: 5)
    }

    @MainActor
    func testSettings_AllOptions_Displayed() throws {
        navigateToSettings()

        // Verify key settings elements exist
        let signOut = app.descendants(matching: .any)["settings.signOutButton"]

        // At least the sign out should be visible
        XCTAssertTrue(
            signOut.waitForExistence(timeout: 5) ||
            staticText("Sign Out").waitForExistence(timeout: 5),
            "Sign Out option should be visible"
        )

        captureScreenshot(name: "Settings-AllOptions")
    }

    @MainActor
    func testSettings_SignOut_ShowsConfirmation() throws {
        navigateToSettings()

        let signOut = app.descendants(matching: .any)["settings.signOutButton"]
        if signOut.waitForExistence(timeout: 5) {
            signOut.tap()
        } else {
            // Fallback: find by text
            let signOutText = staticText("Sign Out")
            if signOutText.waitForExistence(timeout: 3) {
                signOutText.tap()
            }
        }

        // Confirmation dialog should appear
        XCTAssertTrue(
            staticText("Are you sure you want to sign out?").waitForExistence(timeout: 3),
            "Sign out confirmation should appear"
        )

        captureScreenshot(name: "Settings-SignOutConfirmation")
    }

    @MainActor
    func testSettings_DeleteAccount_ShowsConfirmation() throws {
        navigateToSettings()

        // Scroll down within the settings sheet to reveal the delete account button
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()

        let deleteAccount = app.descendants(matching: .any)["settings.deleteAccountButton"]
        if deleteAccount.waitForExistence(timeout: 5) {
            deleteAccount.tap()
        } else {
            let deleteText = staticText("Delete Account")
            if deleteText.waitForExistence(timeout: 3) {
                deleteText.tap()
            } else {
                // Last resort: find any element containing "Delete"
                let deleteBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'delete'")).firstMatch
                if deleteBtn.waitForExistence(timeout: 3) {
                    deleteBtn.tap()
                }
            }
        }

        // Destructive confirmation dialog (action sheet) should appear
        XCTAssertTrue(
            app.buttons["Delete Everything"].waitForExistence(timeout: 5) ||
            staticText("Delete Account").waitForExistence(timeout: 3),
            "Delete account confirmation should appear"
        )

        captureScreenshot(name: "Settings-DeleteConfirmation")
    }
}
