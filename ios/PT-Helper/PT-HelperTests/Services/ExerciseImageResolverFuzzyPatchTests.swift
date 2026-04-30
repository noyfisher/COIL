import XCTest
@testable import PT_Helper

/// Regression coverage for the two resolver fixes shipped alongside the shuffled
/// stockpile discovery (commit Apr 2026): bidirectional prefix/suffix matching and
/// the imageFileName-fuzzy retry. Each named pattern below was a real shuffle
/// discovery that returned `nil` from the pre-patch resolver despite an obviously
/// similar canonical entry being present in the bundled mapping.
final class ExerciseImageResolverFuzzyPatchTests: XCTestCase {

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
    private func assertResolves(
        _ name: String,
        imageFileName: String? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let svc = ExerciseImageService.shared
        let key = svc.imageKey(for: makeExercise(name: name, imageFileName: imageFileName))
        XCTAssertNotNil(
            key,
            "expected resolution for name=\(name.debugDescription) imageFileName=\(imageFileName ?? "nil")",
            file: file, line: line
        )
    }

    // MARK: - imageFileName-fuzzy retry (Layer 4b)

    /// The AI's verbose name normalises to garbage but its imageFileName guess is one
    /// transformation away from canonical. Pre-patch the resolver discarded the
    /// imageFileName the moment exact lookup failed.
    @MainActor
    func testImageFileNamePluralToggle_ResolvesToCanonical() {
        // canonical: pelvic-floor-kegel (singular)
        // AI imageFileName: pelvic-floor-kegels (plural)
        assertResolves(
            "Pelvic Floor Muscle Contractions (Kegels)",
            imageFileName: "pelvic-floor-kegels"
        )
    }

    @MainActor
    func testImageFileNameSuffixMatch_ResolvesViaImageFileName() {
        // canonical: seated-neck-rolls (longer)
        // AI imageFileName: neck-rolls (suffix), AI verbose name unrelated
        assertResolves(
            "Neck Mobility - Slow Neck Rolls",
            imageFileName: "neck-rolls"
        )
    }

    // MARK: - Bidirectional prefix matching (name ⊂ key)

    @MainActor
    func testReversePrefix_ShorterNameMatchesLongerCanonical() {
        // canonical: wall-pushups-modified
        // AI gave: wall-pushups (prefix)
        assertResolves("Wall Pushups", imageFileName: "wall-pushups")
    }

    @MainActor
    func testReversePrefix_SeatedCatCowMatchesStretch() {
        // canonical: seated-cat-cow-stretch
        // AI gave: seated-cat-cow
        assertResolves("Seated Cat-Cow", imageFileName: "seated-cat-cow")
    }

    @MainActor
    func testReversePrefix_StandingDumbbellRowsMatchesStability() {
        // canonical: standing-dumbbell-rows-stability
        // AI gave: standing-dumbbell-rows
        assertResolves("Standing Dumbbell Rows", imageFileName: "standing-dumbbell-rows")
    }

    // MARK: - Bidirectional suffix matching (key ⊂ name, prefix added by AI)

    @MainActor
    func testReverseSuffix_AIAddedPrefixModifier() {
        // canonical: clamshells
        // AI gave: supine-clamshells (added "supine-" prefix)
        assertResolves("Supine Clamshells", imageFileName: "supine-clamshells")
    }

    @MainActor
    func testReverseSuffix_BandAssistedFallsBackToCanonical() {
        // canonical: thoracic-extension
        // AI gave: band-assisted-thoracic-extension
        assertResolves(
            "Band-Assisted Thoracic Extension",
            imageFileName: "band-assisted-thoracic-extension"
        )
    }

    // MARK: - Forward direction must still work (no regression)

    @MainActor
    func testForwardPrefix_QualifierTackedOnto() {
        // canonical: cat-cow-stretch (existing forward-prefix case from comments)
        assertResolves(
            "Cat-Cow Stretch Modified For Lower Back Relief",
            imageFileName: "cat-cow-stretch-modified-for-lower-back-relief"
        )
    }

    @MainActor
    func testForwardSuffix_AIOmittedPositionPrefix() {
        // canonical: seated-calf-raises (or similar)
        // AI gave: calf-raises (omitted position)
        assertResolves("Calf Raises", imageFileName: "calf-raises")
    }
}
