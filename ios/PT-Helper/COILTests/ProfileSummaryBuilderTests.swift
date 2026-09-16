import XCTest
@testable import COIL

/// `ProfileSummaryBuilder` is pure: profile + plans + streak + session count in,
/// masthead strings out. Plan and age maths use the model's own clock
/// (`RehabPlan.status`, `UserProfile.age`), so plan fixtures are built relative
/// to `Date()` the way `RehabPlanStatusTests` does.
final class ProfileSummaryBuilderTests: XCTestCase {

    private func build(profile: UserProfile? = TestFixtures.makeProfile(),
                       plans: [RehabPlan] = [],
                       streak: StreakData = StreakData(),
                       sessions: Int = 0) -> ProfileSummary {
        ProfileSummaryBuilder.build(profile: profile, plans: plans,
                                    streak: streak, sessionCount: sessions)
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - Identity

    func testBuild_nilProfile_usesPlaceholders() {
        let summary = build(profile: nil)
        XCTAssertEqual(summary.displayName, "Your profile")
        XCTAssertEqual(summary.initials, "?")
        XCTAssertNil(summary.detailLine)
        XCTAssertEqual(summary.conditionChips, [])
        XCTAssertNil(summary.activePlan)
        XCTAssertNil(summary.stats.planWeek)
    }

    func testBuild_fullProfile_namesInitialsAndDetailLine() {
        let profile = TestFixtures.makeProfile(age: 34, activityLevel: "Moderately Active")
        let summary = build(profile: profile)
        XCTAssertEqual(summary.displayName, "Test User")
        XCTAssertEqual(summary.initials, "TU")
        XCTAssertEqual(summary.detailLine, "34 · Moderately Active")
    }

    func testBuild_blankName_fallsBackToPlaceholder() {
        var profile = TestFixtures.makeProfile()
        profile.firstName = " "
        profile.lastName = ""
        let summary = build(profile: profile)
        XCTAssertEqual(summary.displayName, "Your profile")
        XCTAssertEqual(summary.initials, "?")
    }

    func testBuild_singleName_usesFirstTwoLetters() {
        var profile = TestFixtures.makeProfile()
        profile.firstName = "Alex"
        profile.lastName = ""
        XCTAssertEqual(build(profile: profile).initials, "AL")
    }

    func testBuild_lastNameOnly_usesLastTwoLetters() {
        var profile = TestFixtures.makeProfile()
        profile.firstName = ""
        profile.lastName = "Nguyen"
        XCTAssertEqual(build(profile: profile).initials, "NG")
    }

    func testBuild_ageBelowOne_dropsAgeFromDetailLine() {
        let profile = TestFixtures.makeProfile(age: 0, activityLevel: "Sedentary")
        XCTAssertEqual(build(profile: profile).detailLine, "Sedentary")
    }

    func testBuild_emptyActivityLevel_dropsItFromDetailLine() {
        let profile = TestFixtures.makeProfile(age: 40, activityLevel: "")
        XCTAssertEqual(build(profile: profile).detailLine, "40")
    }

    // MARK: - Condition chips

    func testBuild_chips_currentInjuriesThenConditions_descriptionsTruncated() {
        let injuries = [
            UserProfile.Injury(bodyArea: "Right Knee", description: "Patellar tendinopathy", isCurrent: true),
            UserProfile.Injury(bodyArea: "Left Ankle", description: "Old sprain", isCurrent: false),
            UserProfile.Injury(bodyArea: "Lower Back", description: "Disc irritation from lifting last spring", isCurrent: true),
        ]
        let profile = TestFixtures.makeProfile(medicalConditions: ["Asthma"], injuries: injuries)
        XCTAssertEqual(build(profile: profile).conditionChips, [
            "Right Knee · Patellar tendinopathy",
            "Lower Back · Disc irritation from lif",
            "Asthma",
        ])
    }

    func testBuild_chips_dedupedCaseInsensitivelyAndCappedAtFour() {
        let profile = TestFixtures.makeProfile(
            medicalConditions: ["Asthma", "asthma", "Hypertension", "Diabetes", "Osteoporosis"])
        XCTAssertEqual(build(profile: profile).conditionChips,
                       ["Asthma", "Hypertension", "Diabetes", "Osteoporosis"])
    }

    // MARK: - Plan

    func testBuild_activePlanTenDaysIn_reportsWeekTwoOfSix() {
        let plan = TestFixtures.makePlan(name: "Knee Rehab Plan", totalWeeks: 6, startDate: daysAgo(10))
        let summary = build(plans: [plan])
        XCTAssertEqual(summary.activePlan,
                       ProfileSummary.ActivePlan(name: "Knee Rehab Plan", statusText: "Week 2 of 6", isActive: true))
        XCTAssertEqual(summary.stats.planWeek, ProfileSummary.PlanWeek(current: 2, total: 6))
    }

    func testBuild_onlyNotStartedPlan_hasStatusButNoPlanWeek() {
        let plan = TestFixtures.makePlan(name: "Shoulder Mobility Plan", totalWeeks: 4)
        let summary = build(plans: [plan])
        XCTAssertEqual(summary.activePlan,
                       ProfileSummary.ActivePlan(name: "Shoulder Mobility Plan", statusText: "Not started", isActive: false))
        XCTAssertNil(summary.stats.planWeek)
    }

    func testBuild_completedPlan_reportsCompletedAndNoPlanWeek() {
        let plan = TestFixtures.makePlan(name: "Shoulder Mobility Plan", totalWeeks: 4, startDate: daysAgo(30))
        let summary = build(plans: [plan])
        XCTAssertEqual(summary.activePlan,
                       ProfileSummary.ActivePlan(name: "Shoulder Mobility Plan", statusText: "Completed", isActive: false))
        XCTAssertNil(summary.stats.planWeek)
    }

    func testBuild_prefersActivePlanOverNotStarted() {
        let notStarted = TestFixtures.makePlan(name: "Later", totalWeeks: 4)
        let active = TestFixtures.makePlan(name: "Now", totalWeeks: 4, startDate: daysAgo(3))
        XCTAssertEqual(build(plans: [notStarted, active]).activePlan?.name, "Now")
    }

    // MARK: - Stats passthrough

    func testBuild_streakAndSessions_passThrough() {
        var streak = StreakData()
        streak.currentStreak = 3
        streak.longestStreak = 7
        let summary = build(streak: streak, sessions: 12)
        XCTAssertEqual(summary.stats.streak, 3)
        XCTAssertEqual(summary.stats.sessions, 12)
    }
}
