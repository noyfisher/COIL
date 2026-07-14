import XCTest

/// Tests for the native system tab bar (floating Liquid Glass on iOS 26):
/// four content tabs plus the "Assess" action tab that presents the body map.
final class TabBarUITests: UITestBase {

    @MainActor
    func testNativeTabBar_AllTabsExist() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Native tab bar should exist")

        XCTAssertTrue(tabBar.buttons["Home"].exists, "Home tab should exist")
        XCTAssertTrue(tabBar.buttons["Plan"].exists, "Plan tab should exist")
        XCTAssertTrue(tabBar.buttons["Progress"].exists, "Progress tab should exist")
        XCTAssertTrue(tabBar.buttons["Profile"].exists, "Profile tab should exist")
        XCTAssertTrue(tabBar.buttons["Assess"].exists, "Assess action tab should exist")

        captureScreenshot(name: "TabBar-NativeLayout")
    }

    @MainActor
    func testAssessTab_OpensBodyMapAndBouncesBack() throws {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))

        tabBar.buttons["Assess"].tap()

        // The body map cover should appear with its close button.
        let closeButton = app.buttons["bodyMap.closeButton"].firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5),
                      "Assess tab should present the body map cover")
        captureScreenshot(name: "TabBar-AssessCover")

        closeButton.tap()

        // Selection should have bounced back to Home, not stuck on Assess.
        XCTAssertTrue(tabBar.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.buttons["Home"].isSelected,
                      "Selection should return to the previous tab after Assess")
        captureScreenshot(name: "TabBar-AfterAssessDismiss")
    }
}
