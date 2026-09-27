import XCTest

final class COILUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding", "--seed-mock-data"]
        // Same launch-crash workaround as UITestBase: the app's custom UIAppFonts
        // trip an os_log fault during registration that XCTAutomationSupport
        // mishandles into an EXC_BAD_ACCESS on launch. This standalone test doesn't
        // inherit UITestBase, so set it here too.
        app.launchEnvironment["OS_ACTIVITY_MODE"] = "disable"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
