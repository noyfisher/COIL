import XCTest
@testable import PT_Helper

final class HomeStripLogicTests: XCTestCase {

    func testHasCompletedSession_completedToday_true() {
        let session = TestFixtures.makeSession(daysAgo: 0, isCompleted: true)
        XCTAssertTrue(HomeStripLogic.hasCompletedSession(on: Date(), in: [session]))
    }

    func testHasCompletedSession_notCompleted_false() {
        let session = TestFixtures.makeSession(daysAgo: 0, isCompleted: false)
        XCTAssertFalse(HomeStripLogic.hasCompletedSession(on: Date(), in: [session]))
    }

    func testHasCompletedSession_completedThreeDaysAgo_trueOnlyForThatDay() {
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let session = TestFixtures.makeSession(daysAgo: 3, isCompleted: true)

        XCTAssertTrue(HomeStripLogic.hasCompletedSession(on: threeDaysAgo, in: [session]))

        let adjacentDay = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        XCTAssertFalse(HomeStripLogic.hasCompletedSession(on: adjacentDay, in: [session]))
    }
}
