import XCTest
@testable import COIL

/// Covers `WellnessAnalysisValidator.validate` — the wellness counterpart to
/// `validateAnalysis`'s content-bounds step. Previously untested entirely, which is
/// how the recommendation-trim bug below survived.
final class WellnessAnalysisValidatorTests: XCTestCase {

    private func makeResult(recommendationCount: Int) -> WellnessAnalysisResult {
        let recs = (0..<recommendationCount).map { i in
            TestFixtures.makeWellnessRecommendation(title: "Recommendation \(i)")
        }
        return TestFixtures.makeWellnessAnalysisResult(recommendations: recs)
    }

    // MARK: - Content bounds (recommendations 1–5)

    /// Regression: the validator appended a "Trimmed wellness recommendations from N to 5"
    /// fix message but returned the result untouched, so every recommendation the AI
    /// produced reached the user while the pipeline reported a correction it never made.
    func testValidate_moreThanFiveRecommendations_actuallyTrimsToFive() {
        let result = makeResult(recommendationCount: 7)

        let (validated, validation) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertEqual(validated.recommendations.count, 5,
                       "Recommendations must actually be trimmed to the documented 1–5 bound")
        XCTAssertTrue(validation.appliedFixes.contains { $0.contains("Trimmed wellness recommendations from 7 to 5") },
                      "The applied-fix message should report the trim that was performed")
    }

    func testValidate_moreThanFiveRecommendations_keepsHighestPriorityFirstFive() {
        let result = makeResult(recommendationCount: 8)

        let (validated, _) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertEqual(validated.recommendations.map(\.title),
                       ["Recommendation 0", "Recommendation 1", "Recommendation 2",
                        "Recommendation 3", "Recommendation 4"],
                       "Trim keeps the leading five in AI-returned order, not an arbitrary subset")
    }

    func testValidate_exactlyFiveRecommendations_notTrimmedAndNoFixReported() {
        let result = makeResult(recommendationCount: 5)

        let (validated, validation) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertEqual(validated.recommendations.count, 5)
        XCTAssertFalse(validation.appliedFixes.contains { $0.contains("Trimmed") },
                       "Five is within bounds — no trim should be reported")
    }

    func testValidate_underFiveRecommendations_passesThroughUnchanged() {
        let result = makeResult(recommendationCount: 3)

        let (validated, validation) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertEqual(validated.recommendations.count, 3)
        XCTAssertTrue(validation.appliedFixes.isEmpty)
    }

    func testValidate_noRecommendations_warnsCaution() {
        let result = makeResult(recommendationCount: 0)

        let (_, validation) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertTrue(validation.warnings.contains { $0.severity == .caution },
                      "An empty recommendation set should surface a caution warning")
    }

    /// The title/state-assessment content checks must run against the *trimmed* set —
    /// warning about a recommendation the user will never see is noise.
    func testValidate_emptyTitleInTrimmedAwayRecommendation_doesNotWarn() {
        var recs = (0..<5).map { TestFixtures.makeWellnessRecommendation(title: "Recommendation \($0)") }
        recs.append(TestFixtures.makeWellnessRecommendation(title: "   "))
        let result = TestFixtures.makeWellnessAnalysisResult(recommendations: recs)

        let (_, validation) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertFalse(validation.warnings.contains { $0.message.contains("missing a title") },
                       "The untitled recommendation was trimmed away — it should not produce a warning")
    }

    func testValidate_emptyTitleInKeptRecommendation_warnsInfo() {
        let recs = [TestFixtures.makeWellnessRecommendation(title: "  ")]
        let result = TestFixtures.makeWellnessAnalysisResult(recommendations: recs)

        let (_, validation) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertTrue(validation.warnings.contains { $0.message.contains("missing a title") })
    }

    // MARK: - Preserved fields

    func testValidate_trimming_preservesAllOtherFields() {
        let result = makeResult(recommendationCount: 9)

        let (validated, _) = WellnessAnalysisValidator.validate(result, assessments: [])

        XCTAssertEqual(validated.id, result.id)
        XCTAssertEqual(validated.overallSummary, result.overallSummary)
        XCTAssertEqual(validated.disclaimerText, result.disclaimerText)
        XCTAssertEqual(validated.generatedDate, result.generatedDate)
        XCTAssertEqual(validated.assessments.count, result.assessments.count)
    }
}
