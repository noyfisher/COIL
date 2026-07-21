import XCTest
@testable import COIL

final class FormFeedbackValidationPipelineTests: XCTestCase {

    // MARK: - Helpers

    private func validate(
        feedback: FormFeedback? = nil,
        metrics: FormAnalysisData? = nil,
        dataQuality: DataQualityReport? = nil,
        ruleCheckResults: [RuleCheckResult] = [],
        exercise: RehabExercise? = nil,
        userConditions: [String] = []
    ) -> (validatedFeedback: FormFeedback, validation: FormValidationResult) {
        FormFeedbackValidationPipeline.validate(
            feedback: feedback ?? TestFixtures.makeFormFeedback(),
            metrics: metrics ?? TestFixtures.makeFormAnalysisData(),
            dataQuality: dataQuality ?? TestFixtures.makeDataQualityReport(),
            ruleCheckResults: ruleCheckResults,
            exercise: exercise ?? TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps"),
            userConditions: userConditions
        )
    }

    // MARK: - Layer 1: Content Validation

    func testContentValidation_emptyPositivePoints_generatesWarning() {
        let feedback = TestFixtures.makeFormFeedback(positivePoints: [])
        let (_, validation) = validate(feedback: feedback)

        let hasWarning = validation.warnings.contains { $0.message.contains("No positive feedback") }
        XCTAssertTrue(hasWarning, "Empty positive points should generate a warning")
    }

    func testContentValidation_moreThan4Corrections_trimmed() {
        let corrections = (0..<6).map { i in
            FormFeedback.Correction(
                bodyPart: "part\(i)", issue: "Issue \(i)",
                howToFix: "Fix \(i)", severity: .minor
            )
        }
        let feedback = TestFixtures.makeFormFeedback(corrections: corrections)
        let (_, validation) = validate(feedback: feedback)

        let hasTrimFix = validation.appliedFixes.contains { $0.contains("Trimmed corrections") }
        XCTAssertTrue(hasTrimFix, "More than 4 corrections should produce a trim fix note")
    }

    // MARK: - Layer 2: Score Calibration

    func testScoreCalibration_cappedAt90() {
        let feedback = TestFixtures.makeFormFeedback(score: 98, verdict: .excellent)
        let (validated, _) = validate(feedback: feedback)

        XCTAssertLessThanOrEqual(validated.overallScore, 90, "Score should be capped at 90")
    }

    func testScoreCalibration_lowDataQuality_cappedAt50() {
        let feedback = TestFixtures.makeFormFeedback(score: 85, verdict: .excellent)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.2)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        XCTAssertLessThanOrEqual(validated.overallScore, 50, "Very low data quality should cap score at 50")
    }

    func testScoreCalibration_mediumDataQuality_cappedAt70() {
        let feedback = TestFixtures.makeFormFeedback(score: 85, verdict: .excellent)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.45)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        XCTAssertLessThanOrEqual(validated.overallScore, 70, "Medium-low data quality should cap score at 70")
    }

    func testScoreCalibration_moderateDataQuality_cappedAt85() {
        let feedback = TestFixtures.makeFormFeedback(score: 90, verdict: .excellent)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.65)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        XCTAssertLessThanOrEqual(validated.overallScore, 85, "Moderate data quality should cap score at 85")
    }

    // MARK: - Layer 2: Verdict Mapping

    func testVerdictMapping_score85_excellent() {
        let feedback = TestFixtures.makeFormFeedback(score: 85, verdict: .excellent)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.95)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        // Score 85 capped at 85 (≤90), quality is high so no further cap → 85 → excellent
        XCTAssertEqual(validated.verdict, .excellent)
    }

    func testVerdictMapping_score75_good() {
        let feedback = TestFixtures.makeFormFeedback(score: 75, verdict: .good)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.95)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        XCTAssertEqual(validated.verdict, .good)
    }

    func testVerdictMapping_score55_needsWork() {
        let feedback = TestFixtures.makeFormFeedback(score: 55, verdict: .needsWork)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.95)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        XCTAssertEqual(validated.verdict, .needsWork)
    }

    func testVerdictMapping_score40_concern() {
        let feedback = TestFixtures.makeFormFeedback(score: 40, verdict: .concern)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.95)
        let (validated, _) = validate(feedback: feedback, dataQuality: quality)

        XCTAssertEqual(validated.verdict, .concern)
    }

    // MARK: - Layer 3: Data-Claim Consistency

    func testConsistency_kneesCaving_removedWhenSymmetryLow() {
        let correction = FormFeedback.Correction(
            bodyPart: "knees", issue: "Knees caving inward during descent",
            howToFix: "Push knees out over toes", severity: .moderate
        )
        let feedback = TestFixtures.makeFormFeedback(corrections: [correction])
        let symmetry = FormAnalysisData.SymmetryData(
            leftAvgAngles: ["knee": 90], rightAvgAngles: ["knee": 91],
            differencesDegrees: ["knee": 1]  // <3° → not supported
        )
        let metrics = TestFixtures.makeFormAnalysisData(symmetry: symmetry)
        let (validated, validation) = validate(feedback: feedback, metrics: metrics)

        XCTAssertTrue(validated.corrections.isEmpty, "Knee caving correction should be removed when symmetry diff < 3°")
        XCTAssertFalse(validation.consistencyIssues.isEmpty, "Should record a consistency issue")
    }

    func testConsistency_limitedRange_removedWhenROMAdequate() {
        let correction = FormFeedback.Correction(
            bodyPart: "knees", issue: "Limited range of motion in squat",
            howToFix: "Go deeper", severity: .moderate
        )
        let feedback = TestFixtures.makeFormFeedback(corrections: [correction])
        // Default makeRepMetrics has ROM of 85° (>60° threshold)
        let (validated, _) = validate(feedback: feedback)

        XCTAssertTrue(validated.corrections.isEmpty, "Limited range correction should be removed when avg ROM > 60°")
    }

    func testConsistency_tooFast_removedWhenTempoControlled() {
        let correction = FormFeedback.Correction(
            bodyPart: "general", issue: "Moving too fast through reps",
            howToFix: "Slow down", severity: .minor
        )
        let feedback = TestFixtures.makeFormFeedback(corrections: [correction])
        let metrics = TestFixtures.makeFormAnalysisData(averageTempo: 3.0)  // >2.0s → controlled
        let (validated, _) = validate(feedback: feedback, metrics: metrics)

        XCTAssertTrue(validated.corrections.isEmpty, "Too-fast correction should be removed when tempo > 2.0s")
    }

    func testConsistency_inconsistentTempo_removedWhenConsistent() {
        let correction = FormFeedback.Correction(
            bodyPart: "general", issue: "Inconsistent tempo between reps",
            howToFix: "Keep pace steady", severity: .minor
        )
        let feedback = TestFixtures.makeFormFeedback(corrections: [correction])
        let metrics = TestFixtures.makeFormAnalysisData(tempoVariability: 0.2)  // <0.5s → consistent
        let (validated, _) = validate(feedback: feedback, metrics: metrics)

        XCTAssertTrue(validated.corrections.isEmpty, "Inconsistent tempo correction should be removed when variability < 0.5s")
    }

    func testConsistency_forwardLean_downgradedWithoutTrunkIssue() {
        let correction = FormFeedback.Correction(
            bodyPart: "trunk", issue: "Excessive forward lean during squat",
            howToFix: "Keep chest up", severity: .major
        )
        let feedback = TestFixtures.makeFormFeedback(corrections: [correction])
        // No alignment issues → should downgrade to minor, not remove
        let (validated, _) = validate(feedback: feedback)

        XCTAssertEqual(validated.corrections.count, 1, "Forward lean correction should be kept but downgraded")
        XCTAssertEqual(validated.corrections.first?.severity, .minor, "Should be downgraded to minor severity")
    }

    // MARK: - Layer 4: Safety Red Flags

    func testSafety_dangerRuleResult_generatesUrgentWarning() {
        let ruleResults = [
            RuleCheckResult(ruleName: "hinge_trunk_angle", result: .danger("Excessive forward bend"))
        ]
        let (_, validation) = validate(ruleCheckResults: ruleResults)

        let hasUrgent = validation.warnings.contains { $0.severity == .urgent }
        XCTAssertTrue(hasUrgent, "Danger rule result should produce an urgent warning")
        XCTAssertFalse(validation.isValid, "isValid should be false when there are urgent warnings")
    }

    func testSafety_cautionRuleResult_generatesCautionWarning() {
        let ruleResults = [
            RuleCheckResult(ruleName: "squat_knee_symmetry", result: .caution("Knee asymmetry"))
        ]
        let (_, validation) = validate(ruleCheckResults: ruleResults)

        let hasCaution = validation.warnings.contains { $0.severity == .caution }
        XCTAssertTrue(hasCaution, "Caution rule result should produce a caution warning")
        XCTAssertTrue(validation.isValid, "isValid should still be true for caution-only warnings")
    }

    // MARK: - Layer 6: Duplicate Detection

    func testDeduplication_duplicateCorrections_removedToOne() {
        let correction1 = FormFeedback.Correction(
            bodyPart: "knees", issue: "Knees caving inward during descent",
            howToFix: "Push knees out", severity: .moderate
        )
        let correction2 = FormFeedback.Correction(
            bodyPart: "knees", issue: "Knees caving inward during descent — especially at the bottom",
            howToFix: "Drive knees over toes", severity: .major
        )
        let feedback = TestFixtures.makeFormFeedback(corrections: [correction1, correction2])
        // Use symmetry with high diff so corrections aren't removed by consistency check
        let symmetry = FormAnalysisData.SymmetryData(
            leftAvgAngles: ["knee": 80], rightAvgAngles: ["knee": 100],
            differencesDegrees: ["knee": 20]
        )
        let metrics = TestFixtures.makeFormAnalysisData(symmetry: symmetry)
        let (validated, validation) = validate(feedback: feedback, metrics: metrics)

        XCTAssertEqual(validated.corrections.count, 1, "Duplicate corrections should be deduplicated")
        let hasDedupFix = validation.appliedFixes.contains { $0.contains("duplicate") }
        XCTAssertTrue(hasDedupFix, "Should note that duplicates were removed")
    }

    // MARK: - Layer 7: Confidence Gating

    func testConfidence_highQualityNoIssues_high() {
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.85)
        let (_, validation) = validate(dataQuality: quality)

        XCTAssertEqual(validation.confidenceLevel, .high)
    }

    func testConfidence_lowQuality_low() {
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.3)
        let (_, validation) = validate(dataQuality: quality)

        XCTAssertEqual(validation.confidenceLevel, .low)
    }

    func testConfidence_thresholdNotMet_insufficient() {
        let quality = TestFixtures.makeDataQualityReport(
            overallScore: 0.2, minimumDataThresholdMet: false
        )
        let (_, validation) = validate(dataQuality: quality)

        XCTAssertEqual(validation.confidenceLevel, .insufficient)
    }

    func testConfidence_moderateQuality_moderate() {
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.6)
        let (_, validation) = validate(dataQuality: quality)

        XCTAssertEqual(validation.confidenceLevel, .moderate)
    }

    func testConfidence_manyConsistencyIssues_low() {
        // Create feedback with corrections that will be removed by consistency checks → 3+ consistency issues
        let corrections = [
            FormFeedback.Correction(bodyPart: "knees", issue: "Knees caving inward", howToFix: "Fix", severity: .moderate),
            FormFeedback.Correction(bodyPart: "general", issue: "Moving too fast", howToFix: "Slow", severity: .minor),
            FormFeedback.Correction(bodyPart: "general", issue: "Asymmetry detected in movement", howToFix: "Balance", severity: .moderate),
        ]
        let feedback = TestFixtures.makeFormFeedback(corrections: corrections)
        // Symmetry < 3° (knees caving removed), tempo > 2s (too fast removed), max diff < 5° (asymmetry removed)
        let symmetry = FormAnalysisData.SymmetryData(
            leftAvgAngles: ["knee": 90], rightAvgAngles: ["knee": 91],
            differencesDegrees: ["knee": 1]
        )
        let metrics = TestFixtures.makeFormAnalysisData(symmetry: symmetry, averageTempo: 3.0)
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.85)
        let (_, validation) = validate(feedback: feedback, metrics: metrics, dataQuality: quality)

        XCTAssertGreaterThanOrEqual(validation.consistencyIssues.count, 3, "Should have 3+ consistency issues")
        XCTAssertEqual(validation.confidenceLevel, .low, "3+ consistency issues should result in low confidence")
    }
}
