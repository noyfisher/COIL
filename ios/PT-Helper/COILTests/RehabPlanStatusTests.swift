import XCTest
@testable import COIL

final class RehabPlanStatusTests: XCTestCase {

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    func testStatus_noStartDate_notStarted() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: nil)
        XCTAssertEqual(plan.status, .notStarted)
    }

    func testStatus_startedToday_activeWeekOne() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: daysAgo(0))
        XCTAssertEqual(plan.status, .active(week: 1))
    }

    func testStatus_startedTenDaysAgo_activeWeekTwo() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: daysAgo(10))
        XCTAssertEqual(plan.status, .active(week: 2))
    }

    func testStatus_durationElapsed_completed() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: daysAgo(42))
        XCTAssertEqual(plan.status, .completed)
    }
}
