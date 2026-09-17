import XCTest

final class SettingsUITests: UITestBase {

    /// Settings now live under the Profile tab's masthead (no sheet, no gear).
    @MainActor
    private func navigateToProfile() {
        tapTab("Profile")
        // The body is in the tree from the start; Sign Out is a reliable "loaded" signal.
        XCTAssertTrue(app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 10),
                      "Profile tab should show the settings body")
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
        navigateToProfile()

        // Appearance picker is new in the COIL rebrand — assert it's present.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.appearancePicker"].waitForExistence(timeout: 5),
            "Appearance picker should be visible in Settings"
        )

        // Sign Out lives further down the Profile tab but is in the tree from the start.
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 5),
            "Sign Out option should be present"
        )

        captureScreenshot(name: "Settings-AllOptions")
    }

    @MainActor
    func testSettings_SignOut_ShowsConfirmation() throws {
        navigateToProfile()

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
        navigateToProfile()

        // The delete button sits in the Account group near the bottom of the Profile tab.
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

    @MainActor
    func testReminderToggle_hasAccessibleName() throws {
        navigateToProfile()
        // Toggle("", …).labelsHidden() had no name at all; VoiceOver read an unnamed switch.
        // Query by the toggle's identifier (the file's convention), then check its spoken name.
        let toggle = app.switches["settings.reminderToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Reminders toggle should exist")
        XCTAssertEqual(toggle.label, "Reminders", "The Reminders toggle should be named for VoiceOver")
    }

    @MainActor
    func testProfileHero_showsSeededSummary() throws {
        navigateToProfile()

        let name = app.staticTexts["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Masthead name should exist")
        XCTAssertEqual(name.label, "Test User")

        // Seeded: streak 3, Knee Rehab Plan started 10 days ago over 6 weeks.
        let streak = app.descendants(matching: .any)["profile.streakStat"]
        XCTAssertTrue(streak.waitForExistence(timeout: 5))
        XCTAssertEqual(streak.label, "3 day streak")

        let planWeek = app.descendants(matching: .any)["profile.planWeekStat"]
        XCTAssertTrue(planWeek.waitForExistence(timeout: 5))
        XCTAssertEqual(planWeek.label, "Plan week 2 of 6")

        XCTAssertTrue(app.descendants(matching: .any)["profile.planRow"].exists,
                      "The active plan row should be shown")
        XCTAssertTrue(app.buttons["settings.editProfileButton"].exists,
                      "Edit Health Info lives in the masthead now")

        captureScreenshot(name: "Profile-Masthead")
    }

    @MainActor
    func testEditHealthInfo_opensTheEditor() throws {
        navigateToProfile()
        let edit = app.buttons["settings.editProfileButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(staticText("Update Profile").waitForExistence(timeout: 5),
                      "Edit Health Info should present the profile editor")
        captureScreenshot(name: "Profile-EditHealthInfo")
    }
}
