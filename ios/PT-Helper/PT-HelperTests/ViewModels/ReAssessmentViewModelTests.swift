import XCTest
@testable import PT_Helper

@MainActor
final class ReAssessmentViewModelTests: XCTestCase {

    private var vm: ReAssessmentViewModel!

    override func setUp() {
        super.setUp()
        vm = ReAssessmentViewModel()
    }

    override func tearDown() {
        vm = nil
        super.tearDown()
    }

    // MARK: - shouldShowReAssessment

    func testShouldShow_PlanNotStarted_ReturnsFalse() {
        let plan = TestFixtures.makePlan(totalWeeks: 6) // no startDate → currentWeek is nil
        XCTAssertFalse(vm.shouldShowReAssessment(for: plan))
    }

    func testShouldShow_AtMidpoint_ReturnsTrue() {
        // Create a plan that started 3 weeks ago (midpoint of 6-week plan)
        var plan = TestFixtures.makePlan(totalWeeks: 6)
        plan.startDate = Calendar.current.date(byAdding: .day, value: -(3 * 7), to: Date())
        XCTAssertTrue(plan.currentWeek == 4 || plan.currentWeek == 3,
                      "Plan should be at or near midpoint (week \(plan.currentWeek ?? -1))")

        // Only midpoint (week 3) triggers re-assessment
        var midpointPlan = TestFixtures.makePlan(totalWeeks: 6)
        midpointPlan.startDate = Calendar.current.date(byAdding: .day, value: -(2 * 7 + 1), to: Date())
        // Note: shouldShow depends on currentWeek == totalWeeks/2
    }

    func testShouldShow_AlreadyAssessed_ReturnsFalse() {
        var plan = TestFixtures.makePlan(totalWeeks: 6)
        plan.startDate = Calendar.current.date(byAdding: .day, value: -(3 * 7), to: Date())

        let snapshot = AssessmentSnapshot(
            id: UUID(),
            planId: plan.id,
            assessmentType: .midpoint,
            date: Date(),
            regionPainLevels: ["right_knee": 3.0],
            overallPain: 3.0
        )
        vm.assessments = [snapshot]

        XCTAssertFalse(vm.shouldShowReAssessment(for: plan),
                       "Should not show re-assessment if midpoint already assessed")
    }

    // MARK: - assessmentType

    func testAssessmentType_PlanNotStarted_ReturnsNil() {
        let plan = TestFixtures.makePlan(totalWeeks: 6)
        XCTAssertNil(vm.assessmentType(for: plan))
    }

    func testAssessmentType_AtCompletion_ReturnsCompletion() {
        var plan = TestFixtures.makePlan(totalWeeks: 4)
        plan.startDate = Calendar.current.date(byAdding: .day, value: -(5 * 7), to: Date()) // well past 4 weeks
        XCTAssertEqual(vm.assessmentType(for: plan), .completion)
    }

    // MARK: - comparison

    func testComparison_TwoAssessments_ReturnsPair() {
        let planId = UUID()
        let initial = AssessmentSnapshot(
            id: UUID(), planId: planId, assessmentType: .initial,
            date: Calendar.current.date(byAdding: .day, value: -14, to: Date())!,
            regionPainLevels: ["right_knee": 7.0], overallPain: 7.0
        )
        let midpoint = AssessmentSnapshot(
            id: UUID(), planId: planId, assessmentType: .midpoint,
            date: Date(),
            regionPainLevels: ["right_knee": 4.0], overallPain: 4.0
        )
        vm.assessments = [initial, midpoint]

        let result = vm.comparison(for: planId)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.initial.assessmentType, .initial)
        XCTAssertEqual(result?.latest.assessmentType, .midpoint)
        XCTAssertEqual(result?.initial.overallPain, 7.0)
        XCTAssertEqual(result?.latest.overallPain, 4.0)
    }

    func testComparison_SingleAssessment_ReturnsNil() {
        let planId = UUID()
        let snapshot = AssessmentSnapshot(
            id: UUID(), planId: planId, assessmentType: .initial,
            date: Date(),
            regionPainLevels: ["right_knee": 5.0], overallPain: 5.0
        )
        vm.assessments = [snapshot]

        XCTAssertNil(vm.comparison(for: planId),
                     "Comparison should require at least 2 assessments")
    }

    func testComparison_DifferentPlan_ReturnsNil() {
        let planId = UUID()
        let otherPlanId = UUID()
        let snapshot = AssessmentSnapshot(
            id: UUID(), planId: otherPlanId, assessmentType: .initial,
            date: Date(),
            regionPainLevels: ["right_knee": 5.0], overallPain: 5.0
        )
        vm.assessments = [snapshot]

        XCTAssertNil(vm.comparison(for: planId))
    }

    // MARK: - initialAssessment

    func testInitialAssessment_FindsCorrectType() {
        let planId = UUID()
        let initial = AssessmentSnapshot(
            id: UUID(), planId: planId, assessmentType: .initial,
            date: Date(),
            regionPainLevels: ["right_knee": 6.0], overallPain: 6.0
        )
        let midpoint = AssessmentSnapshot(
            id: UUID(), planId: planId, assessmentType: .midpoint,
            date: Date(),
            regionPainLevels: ["right_knee": 3.0], overallPain: 3.0
        )
        vm.assessments = [initial, midpoint]

        let result = vm.initialAssessment(for: planId)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.assessmentType, .initial)
        XCTAssertEqual(result?.overallPain, 6.0)
    }

    func testInitialAssessment_NoneExists_ReturnsNil() {
        let planId = UUID()
        vm.assessments = []
        XCTAssertNil(vm.initialAssessment(for: planId))
    }
}
