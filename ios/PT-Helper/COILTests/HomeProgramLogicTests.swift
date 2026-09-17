import XCTest
@testable import COIL

final class HomeProgramLogicTests: XCTestCase {

    /// Fixed UTC Gregorian calendar so weekday maths does not depend on the runner.
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var monday: Date { date(2026, 9, 14) }   // 2026-09-14 is a Monday
    private var sundayDate: Date { date(2026, 9, 13) }
    private var saturday: Date { date(2026, 9, 12) }

    private let wallSits = TestFixtures.makeExercise(name: "Wall Sits")
    private let legRaises = TestFixtures.makeExercise(name: "Straight Leg Raises")
    private let clamshells = TestFixtures.makeExercise(name: "Clamshells", targetArea: "Hip")

    /// Mirrors TestDataSeeder's Knee plan: names, Sun/Tue/Thu (index 0 = Sunday).
    private func seededPlan() -> RehabPlan {
        TestFixtures.makePlan(
            exercises: [wallSits, legRaises, clamshells],
            weeklySchedule: [["Wall Sits", "Straight Leg Raises"], [], ["Clamshells"], [], ["Wall Sits"], [], []]
        )
    }

    func testTodaysExercises_restDay_empty() {
        XCTAssertEqual(HomeProgramLogic.todaysExercises(for: seededPlan(), on: monday, calendar: calendar)?.map(\.name), [])
    }

    func testTodaysExercises_scheduledDay_matchesByName() {
        let result = HomeProgramLogic.todaysExercises(for: seededPlan(), on: sundayDate, calendar: calendar)
        XCTAssertEqual(result?.map(\.name), ["Wall Sits", "Straight Leg Raises"])
    }

    func testTodaysExercises_matchesByIdCaseInsensitively() {
        let plan = TestFixtures.makePlan(
            exercises: [wallSits, clamshells],
            weeklySchedule: [[clamshells.id.uuidString.lowercased()], [], [], [], [], [], []]
        )
        XCTAssertEqual(HomeProgramLogic.todaysExercises(for: plan, on: sundayDate, calendar: calendar)?.map(\.name), ["Clamshells"])
    }

    func testTodaysExercises_emptySchedule_nil() {
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: Array(repeating: [], count: 7))
        XCTAssertNil(HomeProgramLogic.todaysExercises(for: plan, on: monday, calendar: calendar))
    }

    func testTodaysExercises_malformedScheduleLength_nil() {
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: [["Wall Sits"], [], []])
        XCTAssertNil(HomeProgramLogic.todaysExercises(for: plan, on: monday, calendar: calendar))
    }

    /// After an exercise swap the schedule still holds the OLD exercise id (ExerciseSwapViewModel
    /// never rewrites weeklySchedule), so a scheduled day can resolve to nothing. That must
    /// fall back to "show everything" (nil), never to a false rest day ([]).
    func testTodaysExercises_entriesResolveToNothing_fallsBackToNil() {
        let staleId = UUID().uuidString
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: [[staleId], [], [], [], [], [], []])
        XCTAssertNil(HomeProgramLogic.todaysExercises(for: plan, on: sundayDate, calendar: calendar))
    }

    func testNextSession_unresolvedEntries_countsRawEntries() {
        let staleId = UUID().uuidString
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: [[], [staleId, staleId], [], [], [], [], []])
        let next = HomeProgramLogic.nextSession(for: plan, after: sundayDate, calendar: calendar)
        XCTAssertEqual(next?.weekdayName, "Mon")
        XCTAssertEqual(next?.exerciseCount, 2)
    }

    func testNextSession_fromMonday_isTuesdayWithOneExercise() {
        let next = HomeProgramLogic.nextSession(for: seededPlan(), after: monday, calendar: calendar)
        XCTAssertEqual(next?.weekdayName, "Tue")
        XCTAssertEqual(next?.exerciseCount, 1)
    }

    func testNextSession_fromSaturday_wrapsToSunday() {
        let next = HomeProgramLogic.nextSession(for: seededPlan(), after: saturday, calendar: calendar)
        XCTAssertEqual(next?.weekdayName, "Sun")
        XCTAssertEqual(next?.exerciseCount, 2)
    }

    func testNextSession_noScheduledDays_nil() {
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: Array(repeating: [], count: 7))
        XCTAssertNil(HomeProgramLogic.nextSession(for: plan, after: monday, calendar: calendar))
    }

    func testPreferredPlan_prefersActiveRehabPlan() {
        let notStarted = TestFixtures.makePlan(name: "Later", startDate: nil)
        let active = TestFixtures.makePlan(name: "Now", startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()))
        XCTAssertEqual(HomeProgramLogic.preferredPlan(from: [notStarted, active])?.planName, "Now")
    }

    func testPreferredPlan_noActive_firstRehabPlan() {
        let a = TestFixtures.makePlan(name: "A", startDate: nil)
        let b = TestFixtures.makePlan(name: "B", startDate: nil)
        XCTAssertEqual(HomeProgramLogic.preferredPlan(from: [a, b])?.planName, "A")
    }

    func testPreferredPlan_empty_nil() {
        XCTAssertNil(HomeProgramLogic.preferredPlan(from: []))
    }
}
