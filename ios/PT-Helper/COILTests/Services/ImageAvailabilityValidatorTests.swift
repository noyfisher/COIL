import XCTest
@testable import COIL

/// Covers `ImageAvailabilityValidator` — **step 1 of 9** in `validateRehabPlan`, and
/// previously referenced by no test at all.
///
/// This step does more than pick an illustration: when it cannot resolve an exercise it
/// **renames** it. The knowledge-graph contraindication check is step 3, so a rename here
/// changes the name the safety pipeline later inspects. The implementation carries two
/// explicit guards against that (pass the original through untouched when it trips the
/// hardcoded contraindication checker, or when its name contains a safety keyword) —
/// guards that were entirely unverified.
///
/// Runs against the real bundled catalog: `COILTests` is a hosted target, so
/// `Bundle.main` resolves to the app bundle exactly as it does in production.
final class ImageAvailabilityValidatorTests: XCTestCase {

    private func exercise(
        name: String,
        targetArea: String = "Knee",
        difficulty: RehabExercise.Difficulty = .beginner
    ) -> RehabExercise {
        TestFixtures.makeExercise(name: name, targetArea: targetArea, difficulty: difficulty)
    }

    private func validate(
        _ exercises: [RehabExercise],
        conditions: [String] = [],
        painRegions: [String] = []
    ) -> ImageAvailabilityValidator.Result {
        ImageAvailabilityValidator.validate(
            exercises: exercises,
            userConditions: conditions,
            userPainRegions: painRegions
        )
    }

    // MARK: - Resolvable exercises pass through

    func testResolvableExercise_isLeftUnchanged() {
        let result = validate([exercise(name: "Quad Sets", targetArea: "Knee")])

        XCTAssertEqual(result.substitutionCount, 0)
        XCTAssertEqual(result.rewritten.first?.name, "Quad Sets")
        XCTAssertNil(result.rewritten.first?.originalAIName, "Nothing was substituted, so no original name is recorded")
    }

    func testResolvableExercises_preserveOrderAndCount() {
        let input = [
            exercise(name: "Quad Sets", targetArea: "Knee"),
            exercise(name: "Wall Sits", targetArea: "Knee"),
            exercise(name: "Clamshells", targetArea: "Hip"),
        ]

        let result = validate(input)

        XCTAssertEqual(result.rewritten.count, input.count)
        XCTAssertEqual(result.rewritten.map(\.name), input.map(\.name))
    }

    // MARK: - Substitution

    func testUnresolvableExercise_isSubstitutedAndRecordsOriginalName() {
        let result = validate([exercise(name: "Fictional Quadricep Machine Thing", targetArea: "Knee")])

        guard result.substitutionCount == 1 else {
            return XCTFail("Expected a substitution, got \(result.substitutionCount)")
        }
        let rewritten = result.rewritten[0]
        XCTAssertNotEqual(rewritten.name, "Fictional Quadricep Machine Thing")
        XCTAssertEqual(rewritten.originalAIName, "Fictional Quadricep Machine Thing",
                       "The AI's original name must be retained so the swap is auditable")
        XCTAssertNotNil(rewritten.imageFileName)
    }

    func testSubstitution_emitsAnInfoWarningNamingBothExercises() {
        let result = validate([exercise(name: "Fictional Quadricep Machine Thing", targetArea: "Knee")])

        guard let warning = result.substitutionWarnings.first else {
            return XCTFail("A substitution must be surfaced to the user")
        }
        XCTAssertEqual(warning.severity, .info)
        XCTAssertTrue(warning.message.contains("Fictional Quadricep Machine Thing"),
                      "The warning should name what was replaced")
    }

    // MARK: - Safety guards (the reason this step is dangerous)

    /// The core guard: an exercise that trips the hardcoded contraindication checker must
    /// survive step 1 unchanged, so step 2's check still sees the name it needs to flag.
    /// Substituting here would silently erase the contraindication.
    func testContraindicatedOriginal_isNotSubstituted_evenWhenUnresolvable() {
        let unresolvableButContraindicated = exercise(name: "Barbell Deadlift Variation XYZ", targetArea: "Lower Back")

        let result = validate([unresolvableButContraindicated], conditions: ["herniated disc"])

        XCTAssertEqual(result.substitutionCount, 0,
                       "Substituting a contraindicated exercise would hide the downstream warning")
        XCTAssertEqual(result.rewritten.first?.name, "Barbell Deadlift Variation XYZ")
    }

    /// Second guard: the medical-condition safety checks at steps 8/9 key off keywords in
    /// the exercise name, and this stage has no access to the user's profile — so any
    /// flagged keyword blocks substitution regardless of declared conditions.
    func testSafetyKeywordInName_blocksSubstitution_evenWithNoConditions() {
        for name in ["Explosive Jump Lunge XYZ", "Plyometric Bound XYZ", "Single-Leg Hop XYZ"] {
            let result = validate([exercise(name: name, targetArea: "Knee")])

            XCTAssertEqual(result.substitutionCount, 0, "\(name): safety-keyword names must not be renamed")
            XCTAssertEqual(result.rewritten.first?.name, name)
        }
    }

    /// The substitute itself must be safe for the user — verifying the *output*, rather
    /// than trusting the internal candidate filter.
    func testChosenSubstitute_isNotItselfContraindicated() {
        let result = validate([exercise(name: "Nonexistent Knee Movement QQQ", targetArea: "Knee")],
                              conditions: ["patellofemoral pain syndrome"])

        let contraindications = ExerciseContraindicationChecker.validate(
            exercises: result.rewritten,
            conditions: ["patellofemoral pain syndrome"]
        )
        XCTAssertTrue(contraindications.isEmpty,
                      "A substitute must not introduce a contraindication the original didn't have")
    }

    // MARK: - The knowledge-graph blind spot

    /// DOCUMENTS A KNOWN GAP — asserts current behaviour.
    ///
    /// The guards above cover the *hardcoded* contraindication checker and the keyword
    /// list. They do not consult the knowledge graph. `nordic-hamstring-curl` is listed as
    /// unsafe for hamstring-strain in `medical_knowledge_graph.json`, has no catalog image,
    /// and matches none of the safety keywords ("nordic" is not in the list) — so it is
    /// substituted away at step 1 and the graph check at step 3 never sees it. The unsafe
    /// exercise does leave the plan, but by accident of lacking an illustration rather than
    /// because anything recognised the danger, and no warning reaches the user.
    ///
    /// See `KnowledgeGraphCatalogIntegrityTests`, which pins the underlying catalog gap.
    /// Fixing that id will change this behaviour and this test should be revisited.
    func testKnowledgeGraphOnlyContraindication_isSilentlySubstituted_knownGap() {
        let result = validate([exercise(name: "Nordic Hamstring Curl", targetArea: "Hamstrings")],
                              conditions: ["hamstring strain"])

        XCTAssertEqual(result.substitutionCount, 1, """
            Nordic Hamstring Curl is no longer silently substituted — either it gained a \
            catalog entry or the guards now consult the knowledge graph. Re-evaluate this \
            test and the allowlist in KnowledgeGraphCatalogIntegrityTests.
            """)
        XCTAssertTrue(result.substitutionWarnings.allSatisfy { $0.severity == .info },
                      "Today the user is told only that the illustration differs, not that a contraindicated exercise was dropped")
    }

    // MARK: - Empty input

    func testEmptyExerciseList_returnsEmptyResult() {
        let result = validate([])

        XCTAssertTrue(result.rewritten.isEmpty)
        XCTAssertEqual(result.substitutionCount, 0)
        XCTAssertEqual(result.unrepairableCount, 0)
        XCTAssertTrue(result.substitutionWarnings.isEmpty)
    }
}
