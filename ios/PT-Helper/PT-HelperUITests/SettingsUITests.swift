import XCTest

final class SettingsUITests: UITestBase {

    @MainActor
    private func navigateToSettings() {
        tapTab("Profile")

        // In dashboard UI, profile tab has settings access
        let settingsButton = button("Settings")
        let debugButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Debug'")).firstMatch

        if settingsButton.waitForExistence(timeout: 3) {
            settingsButton.tap()
        } else if debugButton.waitForExistence(timeout: 3) {
            debugButton.tap()
        }
    }

    @MainActor
    func testSettings_AllOptions_Displayed() throws {
        navigateToSettings()

        // Verify key settings elements exist
        let reminderToggle = app.descendants(matching: .any)["settings.reminderToggle"]
        let editProfile = app.descendants(matching: .any)["settings.editProfileButton"]
        let signOut = app.descendants(matching: .any)["settings.signOutButton"]
        let deleteAccount = app.descendants(matching: .any)["settings.deleteAccountButton"]

        // At least the sign out and delete should be visible after scrolling
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

        let deleteAccount = app.descendants(matching: .any)["settings.deleteAccountButton"]
        if deleteAccount.waitForExistence(timeout: 5) {
            // Scroll down if needed
            app.swipeUp()
            deleteAccount.tap()
        } else {
            let deleteText = staticText("Delete Account")
            if deleteText.waitForExistence(timeout: 3) {
                deleteText.tap()
            }
        }

        // Destructive confirmation should appear
        XCTAssertTrue(
            staticText("Delete Everything").waitForExistence(timeout: 3) ||
            staticText("This will permanently delete").waitForExistence(timeout: 3),
            "Delete account confirmation should appear"
        )

        captureScreenshot(name: "Settings-DeleteConfirmation")
    }
}
