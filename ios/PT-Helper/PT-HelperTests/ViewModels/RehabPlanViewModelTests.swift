import XCTest
@testable import PT_Helper

// MARK: - RehabPlanViewModel Tests (non-Firebase, non-API parts)

@MainActor
final class RehabPlanViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = RehabPlanViewModel()
        XCTAssertNil(vm.rehabPlan)
        XCTAssertFalse(vm.isSaving)
        XCTAssertFalse(vm.showSaveSuccess)
        XCTAssertNil(vm.saveError)
        XCTAssertFalse(vm.isGenerating)
        XCTAssertNil(vm.generationError)
    }

    func testSettingRehabPlanDirectly() {
        let vm = RehabPlanViewModel()
        let plan = RehabPlan(
            id: UUID(),
            planName: "Test Plan",
            conditions: ["Test"],
            exercises: [],
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 4,
            createdDate: Date(),
            notes: nil
        )

        vm.rehabPlan = plan
        XCTAssertNotNil(vm.rehabPlan)
        XCTAssertEqual(vm.rehabPlan?.planName, "Test Plan")
    }

    func testRehabPlanWithExercises() {
        let vm = RehabPlanViewModel()
        let exercise = RehabExercise(
            id: UUID(),
            name: "Wall Sits",
            targetArea: "Knee",
            description: "Lean against a wall.",
            sets: 3,
            reps: "30 seconds",
            restSeconds: 45,
            difficulty: .intermediate,
            demonstrationIcon: "figure.cooldown",
            tips: ["Keep knees behind toes."],
            contraindications: ["Avoid deep bending."]
        )

        let plan = RehabPlan(
            id: UUID(),
            planName: "Knee Rehab Plan",
            conditions: ["Patellofemoral Pain Syndrome"],
            exercises: [exercise],
            weeklySchedule: [[], ["id1"], [], ["id1"], [], ["id1"], []],
            totalWeeks: 6,
            createdDate: Date(),
            notes: "Progress gradually."
        )

        vm.rehabPlan = plan
        XCTAssertEqual(vm.rehabPlan?.exercises.count, 1)
        XCTAssertEqual(vm.rehabPlan?.exercises.first?.name, "Wall Sits")
        XCTAssertEqual(vm.rehabPlan?.exercises.first?.difficulty, .intermediate)
        XCTAssertEqual(vm.rehabPlan?.totalWeeks, 6)
        XCTAssertEqual(vm.rehabPlan?.notes, "Progress gradually.")
    }

    func testSavingStateFlags() {
        let vm = RehabPlanViewModel()

        // Simulate saving states
        vm.isSaving = true
        XCTAssertTrue(vm.isSaving)

        vm.isSaving = false
        vm.showSaveSuccess = true
        XCTAssertTrue(vm.showSaveSuccess)

        vm.showSaveSuccess = false
        vm.saveError = "Network error"
        XCTAssertEqual(vm.saveError, "Network error")
    }

    func testGeneratingStateFlags() {
        let vm = RehabPlanViewModel()

        vm.isGenerating = true
        XCTAssertTrue(vm.isGenerating)

        vm.isGenerating = false
        vm.generationError = "API error"
        XCTAssertEqual(vm.generationError, "API error")
    }
}
