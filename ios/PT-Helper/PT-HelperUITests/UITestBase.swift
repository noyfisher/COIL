import XCTest

/// Base class for all PT Helper UI tests.
/// Configures the app with test mode launch arguments and provides common helpers.
class UITestBase: XCTestCase {
    var app: XCUIApplication!

    /// Override in subclasses to customize launch arguments.
    var additionalLaunchArguments: [String] { [] }

    /// Whether to skip onboarding (default: true for most tests).
    var skipOnboarding: Bool { true }

    /// Whether to seed mock data (default: true).
    var seedMockData: Bool { true }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        var args = ["--uitesting"]
        if skipOnboarding { args.append("--skip-onboarding") }
        if seedMockData { args.append("--seed-mock-data") }
        args.append(contentsOf: additionalLaunchArguments)

        app.launchArguments = args

        // Workaround for a simulator/XCTest launch crash: the app's custom UIAppFonts
        // (Industry-Bold / Inter) emit an os_log fault during font registration that
        // XCTAutomationSupport's runtime-issue handler mishandles, segfaulting the app
        // on launch (EXC_BAD_ACCESS in libGSFont `AddFontsFromURLOrPath`). Disabling
        // os_activity in the launched process suppresses the fault so the app launches
        // cleanly under UI automation. Pre-existing; unrelated to app logic.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"

        app.launch()
    }

    // MARK: - Helpers

    /// Wait for an element to exist within the given timeout.
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        element.waitForExistence(timeout: timeout)
    }

    /// Assert an element with the given accessibility identifier exists.
    func assertExists(_ identifier: String, timeout: TimeInterval = 5, file: StaticString = #file, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "Expected element '\(identifier)' to exist", file: file, line: line)
    }

    /// Assert an element does NOT exist.
    func assertNotExists(_ identifier: String, file: StaticString = #file, line: UInt = #line) {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertFalse(element.exists, "Expected element '\(identifier)' to not exist", file: file, line: line)
    }

    /// Tap a tab bar item by label text.
    /// The app's live shell uses a custom SwiftUI `FloatingTabBar` (whose items are plain
    /// accessibility buttons via `accessibilityLabel`), not a system `UITabBar`, so query
    /// `app.buttons` first and fall back to `tabBars.buttons` for any legacy system bar.
    func tapTab(_ label: String) {
        let floatingItem = app.buttons[label]
        if floatingItem.waitForExistence(timeout: 5) {
            floatingItem.tap()
        } else {
            app.tabBars.buttons[label].tap()
        }
    }

    /// Capture a screenshot with a descriptive name.
    func captureScreenshot(name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Find a button by its text label.
    func button(_ label: String) -> XCUIElement {
        app.buttons[label]
    }

    /// Find a static text element.
    func staticText(_ text: String) -> XCUIElement {
        app.staticTexts[text]
    }
}
