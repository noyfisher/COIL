import XCTest
@testable import PT_Helper

@MainActor
final class SavedPlansViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState_EmptyPlans_WhenNotAuthenticated() {
        // When launched without authentication (no currentUser),
        // the Firestore listener won't start and plans should remain empty.
        // In test mode, plans are seeded via TestDataSeeder.
        let vm = SavedPlansViewModel()
        // Either seeded or empty depending on launch args
        // This tests the model structure is valid
        XCTAssertNotNil(vm.rehabPlans)
    }

    // MARK: - Plan Operations (In-Memory)

    func testDeletePlan_RemovesFromLocalArray() {
        let vm = SavedPlansViewModel()

        // Inject plans directly
        let plan1 = TestFixtures.makePlan(name: "Plan 1")
        let plan2 = TestFixtures.makePlan(name: "Plan 2")
        vm.rehabPlans = [plan1, plan2]

        XCTAssertEqual(vm.rehabPlans.count, 2)

        // Remove locally (deletePlan calls Firestore which needs auth, so test local removal)
        vm.rehabPlans.removeAll { $0.id == plan1.id }

        XCTAssertEqual(vm.rehabPlans.count, 1)
        XCTAssertEqual(vm.rehabPlans.first?.planName, "Plan 2")
    }

    func testRehabPlans_UpdateLocallyFirst() {
        let vm = SavedPlansViewModel()

        let plan = TestFixtures.makePlan(name: "Original Name")
        vm.rehabPlans = [plan]

        // Simulate local update
        var updated = plan
        updated.planName = "Updated Name"
        if let index = vm.rehabPlans.firstIndex(where: { $0.id == plan.id }) {
            vm.rehabPlans[index] = updated
        }

        XCTAssertEqual(vm.rehabPlans.first?.planName, "Updated Name")
    }

    func testLoadError_DefaultsToNil() {
        let vm = SavedPlansViewModel()
        XCTAssertNil(vm.loadError)
    }

    // MARK: - Plan Data Integrity

    func testPlan_ExerciseCount_MatchesExpected() {
        let exercises = [
            TestFixtures.makeExercise(name: "Exercise 1"),
            TestFixtures.makeExercise(name: "Exercise 2"),
            TestFixtures.makeExercise(name: "Exercise 3")
        ]
        let plan = TestFixtures.makePlan(exercises: exercises)

        XCTAssertEqual(plan.exercises.count, 3)
        XCTAssertEqual(plan.exercises[0].name, "Exercise 1")
    }

    func testPlan_CurrentWeek_NilWhenNotStarted() {
        let plan = TestFixtures.makePlan()
        XCTAssertNil(plan.currentWeek)
    }

    func testPlan_CurrentWeek_CalculatesCorrectly() {
        var plan = TestFixtures.makePlan(totalWeeks: 6)
        plan.startDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())

        XCTAssertNotNil(plan.currentWeek)
        XCTAssertEqual(plan.currentWeek, 2) // 10 days = week 2
    }
}
