import XCTest
@testable import COIL

/// Covers the `graphVerification` element of `validateRehabPlan`'s return tuple, which no
/// test asserted on — the existing `testValidateRehabPlan_*` cases all discard it with `_`.
///
/// `validateRehabPlan` takes no injectable `KnowledgeGraphService`, so it always uses
/// `.shared` and therefore the real bundled graph. These tests use real condition and
/// exercise names for that reason: they verify the wiring between the pipeline and the
/// production safety data, not a fixture.
final class RehabPlanGraphVerificationTests: XCTestCase {

    /// Real pair from `medical_knowledge_graph.json`: bulgarian-split-squat is listed
    /// unsafe for patellofemoral-pain-syndrome.
    private let unsafeExerciseName = "Bulgarian Split Squat"
    private let matchingCondition = "patellofemoral pain syndrome"

    private func plan(exerciseNames: [String], targetArea: String = "Knee") -> RehabPlan {
        TestFixtures.makePlan(
            exercises: exerciseNames.map {
                TestFixtures.makeExercise(name: $0, targetArea: targetArea)
            }
        )
    }

    private func validate(
        _ plan: RehabPlan,
        conditions: [String],
        profile: UserProfile = TestFixtures.makeProfile()
    ) -> (plan: RehabPlan, warnings: [ValidationWarning], graphVerification: PlanVerificationResult?) {
        ResponseValidationPipeline.validateRehabPlan(plan, conditions: conditions, userProfile: profile)
    }

    // MARK: - graphVerification is populated

    /// Nothing currently distinguishes "the graph step ran" from "it silently started
    /// returning nil", which would disable step 3 without any other visible change.
    func testValidateRehabPlan_populatesGraphVerification() {
        let result = validate(plan(exerciseNames: ["Quad Sets"]), conditions: [matchingCondition])

        XCTAssertNotNil(result.graphVerification, "The knowledge-graph step must report a result")
    }

    func testGraphVerification_reportsKnownConditionAsKnown() throws {
        let result = validate(plan(exerciseNames: ["Quad Sets"]), conditions: [matchingCondition])

        let verification = try XCTUnwrap(result.graphVerification)
        let entry = verification.conditionResults.first { $0.condition == matchingCondition }
        XCTAssertEqual(entry?.isKnown, true, "A condition present in the real graph must report as known")
    }

    func testGraphVerification_reportsUnknownConditionAsUnknown() throws {
        let result = validate(plan(exerciseNames: ["Quad Sets"]), conditions: ["fictional condition qqq"])

        let verification = try XCTUnwrap(result.graphVerification)
        let entry = verification.conditionResults.first { $0.condition == "fictional condition qqq" }
        XCTAssertEqual(entry?.isKnown, false)
    }

    // MARK: - Contraindication detection

    func testGraphVerification_flagsRealContraindicatedPair() throws {
        let result = validate(plan(exerciseNames: [unsafeExerciseName]), conditions: [matchingCondition])

        let verification = try XCTUnwrap(result.graphVerification)
        XCTAssertFalse(verification.contraindicatedExercises.isEmpty,
                       "\(unsafeExerciseName) is listed unsafe for \(matchingCondition) in the real graph")
    }

    /// The two outputs of step 3 are produced independently; if they ever disagree, the
    /// user could see a clean plan while the verification result says otherwise.
    func testContraindicatedExercise_alsoProducesASeriousWarning() throws {
        let result = validate(plan(exerciseNames: [unsafeExerciseName]), conditions: [matchingCondition])

        let verification = try XCTUnwrap(result.graphVerification)
        guard !verification.contraindicatedExercises.isEmpty else {
            return XCTFail("Precondition: expected a contraindicated exercise")
        }
        XCTAssertTrue(result.warnings.contains { $0.severity >= .serious },
                      "A graph contraindication must also surface as a .serious warning to the user")
    }

    /// The end-to-end property that matters: an exercise the graph considers unsafe must
    /// still be present in the returned plan, carrying a warning — not quietly removed or
    /// renamed by an earlier step. `Bulgarian Split Squat` resolves in the image catalog,
    /// so step 1 leaves it alone and step 3 gets to see it.
    func testUnsafeExerciseSurvivesThePipeline_withAWarningAttached() throws {
        let result = validate(plan(exerciseNames: [unsafeExerciseName]), conditions: [matchingCondition])

        let names = result.plan.exercises.map(\.name)
        XCTAssertTrue(names.contains(unsafeExerciseName),
                      "The unsafe exercise must remain visible and flagged, not silently disappear")
        XCTAssertTrue(result.warnings.contains { $0.severity >= .serious })
        XCTAssertFalse(try XCTUnwrap(result.graphVerification).contraindicatedExercises.isEmpty)
    }

    // MARK: - Unverified is not contraindicated

    /// Exercises the graph doesn't know are handed to `CrossModelVerificationService`
    /// (tier 2) rather than blocked. Pinned so nobody "fixes" unknown into unsafe, which
    /// would flood users with false warnings.
    func testExerciseUnknownToGraph_isUnverified_notContraindicated() throws {
        let result = validate(plan(exerciseNames: ["Completely Invented Movement ZZZ"]),
                              conditions: [matchingCondition])

        let verification = try XCTUnwrap(result.graphVerification)
        XCTAssertTrue(verification.contraindicatedExercises.isEmpty,
                      "Unknown must not be treated as unsafe")
        XCTAssertFalse(verification.unverifiedExercises.isEmpty,
                       "Unknown exercises must be routed to the cross-model check")
    }

    func testKnownSafePair_isNotFlagged() throws {
        let result = validate(plan(exerciseNames: ["Quad Sets"]), conditions: [matchingCondition])

        let verification = try XCTUnwrap(result.graphVerification)
        XCTAssertTrue(verification.contraindicatedExercises.isEmpty,
                      "A graph-safe exercise must not be flagged for its own condition")
    }

    func testNoConditions_stillReturnsAVerificationResult() {
        let result = validate(plan(exerciseNames: ["Quad Sets"]), conditions: [])

        XCTAssertNotNil(result.graphVerification)
    }
}
