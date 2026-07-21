import XCTest
@testable import COIL

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

    // MARK: - Fuzzy Matching Tests

    private func makeExercise(name: String, imageFileName: String? = nil) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: name, targetArea: "Test",
            description: "Test", sets: 3, reps: "10", restSeconds: 30,
            difficulty: .beginner, demonstrationIcon: "figure.flexibility",
            tips: [], contraindications: [],
            imageFileName: imageFileName
        )
    }

    @MainActor
    func testFuzzyMatch_prefixMatch() {
        let service = ExerciseImageService.shared
        // AI appends modifiers — should match base "cat-cow-stretch"
        let exercise = makeExercise(name: "Cat-Cow Stretch Modified for Lower Back Relief")
        XCTAssertTrue(service.hasImage(for: exercise))
        XCTAssertEqual(service.imageKey(for: exercise), "cat-cow-stretch")
    }

    @MainActor
    func testFuzzyMatch_prefixMatchDeadBug() {
        let service = ExerciseImageService.shared
        let exercise = makeExercise(name: "Dead Bug Modified")
        XCTAssertTrue(service.hasImage(for: exercise))
        XCTAssertEqual(service.imageKey(for: exercise), "dead-bug")
    }

    @MainActor
    func testFuzzyMatch_longestPrefixWins() {
        let service = ExerciseImageService.shared
        // "bird-dog-with-core-stability-focus" is itself a mapping key, should match exactly
        // not fall back to shorter "bird-dog"
        let exercise = makeExercise(name: "Bird Dog with Core Stability Focus")
        XCTAssertEqual(service.imageKey(for: exercise), "bird-dog-with-core-stability-focus")
    }

    @MainActor
    func testFuzzyMatch_prefixBoundary() {
        let service = ExerciseImageService.shared
        // "plank" should NOT match "planking-exercises" — boundary check
        let exercise = makeExercise(name: "Planking Exercises")
        // "plank" + "-" is "plank-" which is NOT a prefix of "planking-exercises"
        // so this should not incorrectly match "plank"
        let key = service.imageKey(for: exercise)
        XCTAssertNotEqual(key, "plank")
    }

    @MainActor
    func testFuzzyMatch_suffixMatch() {
        let service = ExerciseImageService.shared
        // "hamstring-stretch" should match "seated-hamstring-stretch" or "supine-hamstring-stretch"
        let exercise = makeExercise(name: "Hamstring Stretch")
        XCTAssertTrue(service.hasImage(for: exercise))
        let key = service.imageKey(for: exercise)
        XCTAssertNotNil(key)
        XCTAssertTrue(key!.hasSuffix("hamstring-stretch"))
    }

    @MainActor
    func testFuzzyMatch_pluralToggle() {
        let service = ExerciseImageService.shared
        // "band-pull-apart" (singular) should match "band-pull-aparts" (plural in mapping)
        let exercise = makeExercise(name: "Band Pull Apart")
        XCTAssertTrue(service.hasImage(for: exercise))
    }

    @MainActor
    func testFuzzyMatch_synonymExpansion() {
        let service = ExerciseImageService.shared
        // "quadriceps-stretch" → synonym expands to "quad-stretch" → suffix matches "standing-quad-stretch"
        let exercise = makeExercise(name: "Quadriceps Stretch")
        XCTAssertTrue(service.hasImage(for: exercise))
    }

    @MainActor
    func testFuzzyMatch_noFalsePositive() {
        let service = ExerciseImageService.shared
        let exercise = makeExercise(name: "Underwater Basket Weaving")
        XCTAssertFalse(service.hasImage(for: exercise))
        XCTAssertNil(service.imageKey(for: exercise))
    }

    @MainActor
    func testFuzzyMatch_bilateralSuffix() {
        let service = ExerciseImageService.shared
        // "glute-bridges-bilateral" → prefix match on "glute-bridges"
        let exercise = makeExercise(name: "Glute Bridges Bilateral")
        XCTAssertTrue(service.hasImage(for: exercise))
        XCTAssertEqual(service.imageKey(for: exercise), "glute-bridges")
    }

    @MainActor
    func testFuzzyMatch_calfRaises() {
        let service = ExerciseImageService.shared
        // "calf-raises" → suffix match on "standing-calf-raises" or "seated-calf-raises"
        let exercise = makeExercise(name: "Calf Raises")
        XCTAssertTrue(service.hasImage(for: exercise))
    }
}
