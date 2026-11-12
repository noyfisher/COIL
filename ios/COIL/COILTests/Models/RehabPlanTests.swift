import XCTest
@testable import COIL

// MARK: - RehabPlan Tests

final class RehabPlanTests: XCTestCase {

    func testRehabExerciseDifficultyCases() {
        XCTAssertEqual(RehabExercise.Difficulty.allCases.count, 3)
        XCTAssertEqual(RehabExercise.Difficulty.beginner.rawValue, "beginner")
        XCTAssertEqual(RehabExercise.Difficulty.intermediate.rawValue, "intermediate")
        XCTAssertEqual(RehabExercise.Difficulty.advanced.rawValue, "advanced")
    }

    func testRehabPlanCreation() {
        let exercise = RehabExercise(
            id: UUID(),
            name: "Quad Sets",
            targetArea: "Knee",
            description: "Tighten your quad.",
            sets: 3,
            reps: "10-15",
            restSeconds: 30,
            difficulty: .beginner,
            demonstrationIcon: "figure.flexibility",
            tips: ["Keep leg straight"],
            contraindications: ["Avoid if swollen"]
        )

        let plan = RehabPlan(
            id: UUID(),
            planName: "Knee Rehab",
            conditions: ["Patellofemoral Pain"],
            exercises: [exercise],
            weeklySchedule: [[], ["ex1"], [], ["ex1"], [], ["ex1"], []],
            totalWeeks: 4,
            createdDate: Date(),
            notes: "Start gently"
        )

        XCTAssertEqual(plan.planName, "Knee Rehab")
        XCTAssertEqual(plan.conditions.count, 1)
        XCTAssertEqual(plan.exercises.count, 1)
        XCTAssertEqual(plan.weeklySchedule.count, 7)
        XCTAssertEqual(plan.totalWeeks, 4)
        XCTAssertEqual(plan.notes, "Start gently")
    }

    func testRehabExerciseWithPositionGuide() {
        let exercise = RehabExercise(
            id: UUID(),
            name: "Glute Bridge",
            targetArea: "Back/Glutes",
            description: "Lift hips toward ceiling.",
            sets: 3,
            reps: "12-15",
            restSeconds: 30,
            difficulty: .beginner,
            demonstrationIcon: "figure.strengthtraining.traditional",
            tips: ["Squeeze glutes at top"],
            contraindications: ["Avoid if back spasm"],
            startPosition: "Lie on your back with knees bent, feet flat",
            movement: "Squeeze glutes and lift hips until body forms a straight line",
            endPosition: "Lower hips slowly back to the floor",
            exerciseCategory: "strength"
        )

        XCTAssertEqual(exercise.startPosition, "Lie on your back with knees bent, feet flat")
        XCTAssertEqual(exercise.movement, "Squeeze glutes and lift hips until body forms a straight line")
        XCTAssertEqual(exercise.endPosition, "Lower hips slowly back to the floor")
        XCTAssertEqual(exercise.exerciseCategory, "strength")
    }

    func testRehabExerciseBackwardCompatibility() throws {
        // Old JSON without new fields should decode with nil defaults
        let json = """
        {"id":"12345678-1234-1234-1234-123456789012","name":"Test","targetArea":"Knee","description":"Test exercise","sets":3,"reps":"10","restSeconds":30,"difficulty":"beginner","demonstrationIcon":"figure.flexibility","tips":[],"contraindications":[]}
        """
        let data = json.data(using: .utf8)!
        let exercise = try JSONDecoder().decode(RehabExercise.self, from: data)
        XCTAssertEqual(exercise.name, "Test")
        XCTAssertNil(exercise.startPosition)
        XCTAssertNil(exercise.movement)
        XCTAssertNil(exercise.endPosition)
        XCTAssertNil(exercise.exerciseCategory)
        XCTAssertNil(exercise.imageFileName)
    }

    func testRehabExerciseWithImageFileName() {
        let exercise = RehabExercise(
            id: UUID(),
            name: "Quad Sets",
            targetArea: "Knee",
            description: "Tighten your quad.",
            sets: 3,
            reps: "10-15",
            restSeconds: 30,
            difficulty: .beginner,
            demonstrationIcon: "figure.flexibility",
            tips: ["Keep leg straight"],
            contraindications: ["Avoid if swollen"],
            startPosition: "Sit with leg straight",
            movement: "Press knee into floor",
            endPosition: "Release and repeat",
            exerciseCategory: "strength",
            imageFileName: "quad-sets"
        )

        XCTAssertEqual(exercise.imageFileName, "quad-sets")
        XCTAssertEqual(exercise.name, "Quad Sets")
    }

    func testRehabExerciseImageFileNameNilByDefault() {
        let exercise = RehabExercise(
            id: UUID(),
            name: "Test Exercise",
            targetArea: "Knee",
            description: "Test",
            sets: 3,
            reps: "10",
            restSeconds: 30,
            difficulty: .beginner,
            demonstrationIcon: "figure.flexibility",
            tips: [],
            contraindications: []
        )

        XCTAssertNil(exercise.imageFileName, "imageFileName should be nil by default")
    }

    func testRehabExerciseImageFileNameDecodesFromJSON() throws {
        let json = """
        {"id":"12345678-1234-1234-1234-123456789012","name":"Glute Bridges","targetArea":"Back/Glutes","description":"Lift hips","sets":3,"reps":"12","restSeconds":30,"difficulty":"beginner","demonstrationIcon":"figure.flexibility","tips":[],"contraindications":[],"imageFileName":"glute-bridges"}
        """
        let data = json.data(using: .utf8)!
        let exercise = try JSONDecoder().decode(RehabExercise.self, from: data)
        XCTAssertEqual(exercise.imageFileName, "glute-bridges")
    }

    func testRehabPlanWithNilNotes() {
        let plan = RehabPlan(
            id: UUID(),
            planName: "Test",
            conditions: [],
            exercises: [],
            weeklySchedule: [],
            totalWeeks: 4,
            createdDate: Date(),
            notes: nil
        )
        XCTAssertNil(plan.notes)
    }
}
