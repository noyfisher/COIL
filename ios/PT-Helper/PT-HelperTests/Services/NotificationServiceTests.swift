import XCTest
import UserNotifications
@testable import PT_Helper

@MainActor
final class NotificationServiceTests: XCTestCase {

    var mockCenter: MockNotificationCenter!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mockCenter = MockNotificationCenter()
        testDefaults = UserDefaults(suiteName: "NotificationServiceTests")
        testDefaults.removePersistentDomain(forName: "NotificationServiceTests")
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: "NotificationServiceTests")
        mockCenter = nil
        testDefaults = nil
        super.tearDown()
    }

    private func makeSUT(enabled: Bool = true, authorized: Bool = true) -> NotificationService {
        let sut = NotificationService(center: mockCenter, defaults: testDefaults, skipAuthCheck: true)
        sut.isEnabled = enabled
        sut.isAuthorized = authorized
        return sut
    }

    // MARK: - reminderEligiblePlan

    func testReminderEligiblePlan_twoStartedPlans_picksMostRecentlyStarted() {
        let older = TestFixtures.makePlan(name: "Older", startDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()))
        let newer = TestFixtures.makePlan(name: "Newer", startDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        let result = NotificationService.reminderEligiblePlan(from: [older, newer])
        XCTAssertEqual(result?.planName, "Newer")
    }

    func testReminderEligiblePlan_unstartedAndCompletedPlans_returnsNil() {
        let unstarted = TestFixtures.makePlan(name: "Unstarted")
        let completed = TestFixtures.makePlan(name: "Completed", totalWeeks: 1, startDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()))
        let result = NotificationService.reminderEligiblePlan(from: [unstarted, completed])
        XCTAssertNil(result)
    }

    // MARK: - isCompleted

    func testIsCompleted_startedPastDuration_true() {
        let plan = TestFixtures.makePlan(totalWeeks: 1, startDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()))
        XCTAssertTrue(plan.isCompleted)
    }

    func testIsCompleted_withinDuration_false() {
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()))
        XCTAssertFalse(plan.isCompleted)
    }

    func testIsCompleted_unstarted_false() {
        let plan = TestFixtures.makePlan(totalWeeks: 4)
        XCTAssertFalse(plan.isCompleted)
    }

    // MARK: - syncPlanReminders

    func testSync_startedPlanWithThreeScheduledDays_addsThreeRequestsWithPlanPrefix() async {
        let sut = makeSUT()
        var schedule = Array(repeating: [String](), count: 7)
        schedule[0] = ["Squat"]
        schedule[2] = ["Lunge"]
        schedule[4] = ["Bridge"]
        let plan = TestFixtures.makePlan(startDate: Date(), weeklySchedule: schedule)

        await sut.syncPlanReminders(plans: [plan])

        let planRequests = mockCenter.addedRequests.filter { $0.identifier.hasPrefix("plan-") }
        XCTAssertEqual(planRequests.count, 3)
    }

    func testSync_unstartedPlan_schedulesNothing() async {
        let sut = makeSUT()
        let plan = TestFixtures.makePlan()

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("plan-") }.isEmpty)
    }

    func testSync_masterDisabled_removesStalePlanRequestsAndAddsNone() async {
        let sut = makeSUT(enabled: false)
        let staleRequest = UNNotificationRequest(
            identifier: "plan-stale-day-0",
            content: UNMutableNotificationContent(),
            trigger: nil)
        mockCenter.pendingStub = [staleRequest]
        let plan = TestFixtures.makePlan(startDate: Date(), weeklySchedule: [["Squat"], [], [], [], [], [], []])

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.removedIdentifiers.contains("plan-stale-day-0"))
        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("plan-") }.isEmpty)
    }

    func testSync_workoutToggleOff_schedulesNoWorkoutReminders() async {
        let sut = makeSUT()
        sut.workoutRemindersEnabled = false
        let plan = TestFixtures.makePlan(startDate: Date(), weeklySchedule: [["Squat"], [], [], [], [], [], []])

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("plan-") }.isEmpty)
    }

    func testSync_twoStartedPlans_schedulesOnlyMostRecent() async {
        let sut = makeSUT()
        let older = TestFixtures.makePlan(name: "Older", startDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()), weeklySchedule: [["Squat"], [], [], [], [], [], []])
        let newer = TestFixtures.makePlan(name: "Newer", startDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()), weeklySchedule: [["Lunge"], [], [], [], [], [], []])

        await sut.syncPlanReminders(plans: [older, newer])

        let bodies = Set(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("plan-") }.map { $0.content.body })
        XCTAssertTrue(bodies.contains { $0.contains("Newer") })
        XCTAssertFalse(bodies.contains { $0.contains("Older") })
    }

    func testScheduleReminders_userInfo_routesToPlansTab() async {
        let sut = makeSUT()
        let plan = TestFixtures.makePlan(startDate: Date(), weeklySchedule: [["Squat"], [], [], [], [], [], []])

        await sut.syncPlanReminders(plans: [plan])

        let request = mockCenter.addedRequests.first { $0.identifier.hasPrefix("plan-") }
        XCTAssertEqual(request?.content.userInfo["tab"] as? String, "plans")
    }

    // MARK: - WS2-02: Settings wiring

    func testUpdateReminderTime_persistsHourAndMinute() {
        let sut = makeSUT()
        sut.updateReminderTime(hour: 14, minute: 30)
        XCTAssertEqual(sut.reminderHour, 14)
        XCTAssertEqual(sut.reminderMinute, 30)
        XCTAssertEqual(testDefaults.object(forKey: "notif_reminder_hour") as? Int, 14)
        XCTAssertEqual(testDefaults.object(forKey: "notif_reminder_minute") as? Int, 30)
    }

    func testResync_afterTimeChange_reschedulesActivePlanAtNewTime() async {
        let sut = makeSUT()
        let plan = TestFixtures.makePlan(startDate: Date(), weeklySchedule: [["Squat"], [], [], [], [], [], []])
        await sut.syncPlanReminders(plans: [plan])

        sut.updateReminderTime(hour: 7, minute: 15)
        await sut.resyncReminders()

        let request = mockCenter.addedRequests.last { $0.identifier.hasPrefix("plan-") }
        let trigger = request?.trigger as? UNCalendarNotificationTrigger
        XCTAssertEqual(trigger?.dateComponents.hour, 7)
        XCTAssertEqual(trigger?.dateComponents.minute, 15)
    }

    func testCancelAllReminders_callsRemoveAllOnCenter() {
        let sut = makeSUT()
        sut.cancelAllReminders()
        XCTAssertEqual(mockCenter.removeAllCallCount, 1)
    }

    // MARK: - WS2-03: Re-assessment reminders

    func testReassessment_fourWeekPlanStartedToday_schedulesMidpointAndCompletion() async {
        let sut = makeSUT()
        sut.reminderHour = 23
        sut.reminderMinute = 59
        let start = Date()
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: start)

        await sut.syncPlanReminders(plans: [plan])

        let reassessRequests = mockCenter.addedRequests.filter { $0.identifier.hasPrefix("reassess-") }
        XCTAssertEqual(reassessRequests.count, 2)
        XCTAssertTrue(reassessRequests.contains { $0.identifier.hasSuffix("-midpoint") })
        XCTAssertTrue(reassessRequests.contains { $0.identifier.hasSuffix("-completion") })

        let midpoint = reassessRequests.first { $0.identifier.hasSuffix("-midpoint") }
        let midpointTrigger = midpoint?.trigger as? UNCalendarNotificationTrigger
        let expectedMidpoint = Calendar.current.date(byAdding: .day, value: 7, to: start)!
        XCTAssertEqual(midpointTrigger?.dateComponents.day, Calendar.current.component(.day, from: expectedMidpoint))

        let completion = reassessRequests.first { $0.identifier.hasSuffix("-completion") }
        let completionTrigger = completion?.trigger as? UNCalendarNotificationTrigger
        let expectedCompletion = Calendar.current.date(byAdding: .day, value: 21, to: start)!
        XCTAssertEqual(completionTrigger?.dateComponents.day, Calendar.current.component(.day, from: expectedCompletion))
    }

    func testReassessment_oneWeekPlan_schedulesOnlyCompletion() async {
        let sut = makeSUT()
        sut.reminderHour = 23
        sut.reminderMinute = 59
        let plan = TestFixtures.makePlan(totalWeeks: 1, startDate: Date())

        await sut.syncPlanReminders(plans: [plan])

        let reassessRequests = mockCenter.addedRequests.filter { $0.identifier.hasPrefix("reassess-") }
        XCTAssertEqual(reassessRequests.count, 1)
        XCTAssertTrue(reassessRequests[0].identifier.hasSuffix("-completion"))
    }

    func testReassessment_startedThreeWeeksAgo_skipsPastMidpoint() async {
        let sut = makeSUT()
        sut.reminderHour = 23
        sut.reminderMinute = 59
        let start = Calendar.current.date(byAdding: .day, value: -21, to: Date())!
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: start)

        await sut.syncPlanReminders(plans: [plan])

        let reassessRequests = mockCenter.addedRequests.filter { $0.identifier.hasPrefix("reassess-") }
        XCTAssertEqual(reassessRequests.count, 1)
        XCTAssertTrue(reassessRequests[0].identifier.hasSuffix("-completion"))
    }

    func testReassessment_toggleOff_schedulesNone() async {
        let sut = makeSUT()
        sut.reassessmentRemindersEnabled = false
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: Date())

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("reassess-") }.isEmpty)
    }

    func testSync_completedPlan_schedulesNoReassessmentReminders() async {
        let sut = makeSUT()
        let plan = TestFixtures.makePlan(totalWeeks: 1, startDate: Calendar.current.date(byAdding: .day, value: -30, to: Date()))

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("reassess-") }.isEmpty)
    }

    // MARK: - WS2-04: First-workout activation nudge

    func testActivation_freshlyStartedPlanNoWorkouts_schedulesNudgeTwoDaysOut() async {
        let sut = makeSUT()
        sut.reminderHour = 23
        sut.reminderMinute = 59
        let start = Date()
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: start)

        await sut.syncPlanReminders(plans: [plan])

        let activationRequests = mockCenter.addedRequests.filter { $0.identifier.hasPrefix("activation-") }
        XCTAssertEqual(activationRequests.count, 1)
        let trigger = activationRequests[0].trigger as? UNCalendarNotificationTrigger
        let expected = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        XCTAssertEqual(trigger?.dateComponents.day, Calendar.current.component(.day, from: expected))
    }

    func testActivation_workoutLoggedAfterStart_notScheduled() async {
        let sut = makeSUT()
        let start = Date()
        testDefaults.set(Calendar.current.date(byAdding: .hour, value: 1, to: start)!, forKey: "notif_last_workout_at")
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: start)

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("activation-") }.isEmpty)
    }

    func testActivation_startedThreeDaysAgo_pastFireDateSkipped() async {
        let sut = makeSUT()
        let start = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: start)

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("activation-") }.isEmpty)
    }

    func testActivation_inactivityToggleOff_notScheduled() async {
        let sut = makeSUT()
        sut.inactivityNudgesEnabled = false
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: Date())

        await sut.syncPlanReminders(plans: [plan])

        XCTAssertTrue(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("activation-") }.isEmpty)
    }

    func testNoteWorkoutCompleted_removesPendingActivationNudge() async {
        let sut = makeSUT()
        sut.reminderHour = 23
        sut.reminderMinute = 59
        let plan = TestFixtures.makePlan(totalWeeks: 4, startDate: Date())
        await sut.syncPlanReminders(plans: [plan])
        XCTAssertFalse(mockCenter.addedRequests.filter { $0.identifier.hasPrefix("activation-") }.isEmpty)

        await sut.noteWorkoutCompleted()

        XCTAssertTrue(mockCenter.removedIdentifiers.contains { $0.hasPrefix("activation-") })
        let activationRequestsAfter = mockCenter.addedRequests.filter { $0.identifier.hasPrefix("activation-") }
        XCTAssertEqual(activationRequestsAfter.count, 1, "no NEW activation request should be added after a workout")
    }
}
