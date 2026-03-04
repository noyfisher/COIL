import XCTest
@testable import PT_Helper

// MARK: - ExerciseImageService Tests

final class ExerciseImageServiceTests: XCTestCase {

    @MainActor
    func testExercisesWithoutImages_identifiesMissing() {
        let service = ExerciseImageService.shared

        // "Quad Sets" should be in the mapping (it's one of the 149 exercises)
        let knownExercise = RehabExercise(
            id: UUID(), name: "Quad Sets", targetArea: "Knee",
            description: "Test", sets: 3, reps: "10", restSeconds: 30,
            difficulty: .beginner, demonstrationIcon: "figure.flexibility",
            tips: [], contraindications: [],
            imageFileName: "quad-sets"
        )

        // This exercise should NOT be in the mapping
        let unknownExercise = RehabExercise(
            id: UUID(), name: "Underwater Basket Weaving Stretch", targetArea: "Full Body",
            description: "Test", sets: 1, reps: "5", restSeconds: 10,
            difficulty: .beginner, demonstrationIcon: "figure.flexibility",
            tips: [], contraindications: []
        )

        let missing = service.exercisesWithoutImages(in: [knownExercise, unknownExercise])

        // Only the unknown exercise should be missing
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.name, "Underwater Basket Weaving Stretch")
    }

    @MainActor
    func testExercisesWithoutImages_emptyWhenAllHaveImages() {
        let service = ExerciseImageService.shared

        let exercise = RehabExercise(
            id: UUID(), name: "Glute Bridges", targetArea: "Back/Glutes",
            description: "Test", sets: 3, reps: "12", restSeconds: 30,
            difficulty: .beginner, demonstrationIcon: "figure.flexibility",
            tips: [], contraindications: [],
            imageFileName: "glute-bridges"
        )

        let missing = service.exercisesWithoutImages(in: [exercise])
        XCTAssertTrue(missing.isEmpty, "Should be empty when all exercises have images")
    }

    @MainActor
    func testExercisesWithoutImages_emptyInputReturnsEmpty() {
        let service = ExerciseImageService.shared
        let missing = service.exercisesWithoutImages(in: [])
        XCTAssertTrue(missing.isEmpty)
    }

    @MainActor
    func testNormalizeName() {
        let service = ExerciseImageService.shared
        XCTAssertEqual(service.normalizeName("Quad Sets"), "quad-sets")
        XCTAssertEqual(service.normalizeName("Cat-Cow Stretch"), "cat-cow-stretch")
        XCTAssertEqual(service.normalizeName("Wall Sit's"), "wall-sits")
        XCTAssertEqual(service.normalizeName("single leg deadlift"), "single-leg-deadlift")
    }
}
