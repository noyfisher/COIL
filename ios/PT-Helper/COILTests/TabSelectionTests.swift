import XCTest
@testable import COIL

@MainActor
final class TabSelectionTests: XCTestCase {

    func testTabBarHidden_defaultsToFalse() {
        XCTAssertFalse(TabSelection().isTabBarHidden)
    }

    func testPopToRootAndGoHome_restoresTabBar() {
        let selection = TabSelection()
        selection.selectedTab = 2
        selection.isTabBarHidden = true
        selection.popToRootAndGoHome()
        XCTAssertEqual(selection.selectedTab, 0)
        XCTAssertFalse(selection.isTabBarHidden,
                      "Pop-to-root leaves no workout on screen, so the bar must come back")
    }

    func testPopToRootCurrentTab_restoresTabBar() {
        let selection = TabSelection()
        selection.selectedTab = 2
        selection.isTabBarHidden = true
        selection.popToRootCurrentTab()
        XCTAssertFalse(selection.isTabBarHidden,
                      "Pop-to-root leaves no workout on screen, so the bar must come back")
    }

    func testPopToRootAndGoHome_onHome_restoresTabBar() {
        let selection = TabSelection()
        selection.selectedTab = 0
        selection.isTabBarHidden = true
        selection.popToRootAndGoHome()
        XCTAssertFalse(selection.isTabBarHidden,
                      "A workout pushed from Home is torn down by the Home stack reset")
    }
}
