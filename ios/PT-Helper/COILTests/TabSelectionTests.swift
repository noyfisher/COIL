import XCTest
@testable import COIL

@MainActor
final class TabSelectionTests: XCTestCase {

    func testTabBarHidden_defaultsToFalse() {
        XCTAssertFalse(TabSelection().isTabBarHidden)
    }

    func testPopToRootAndGoHome_doesNotTouchTabBarHidden() {
        let selection = TabSelection()
        selection.selectedTab = 2
        selection.isTabBarHidden = true
        selection.popToRootAndGoHome()
        XCTAssertEqual(selection.selectedTab, 0)
        XCTAssertTrue(selection.isTabBarHidden,
                      "Only the workout's onDisappear restores the bar; navigation must not")
    }

    func testPopToRootCurrentTab_doesNotTouchTabBarHidden() {
        let selection = TabSelection()
        selection.selectedTab = 2
        selection.isTabBarHidden = true
        selection.popToRootCurrentTab()
        XCTAssertTrue(selection.isTabBarHidden,
                      "Only the workout's onDisappear restores the bar; navigation must not")
    }
}
