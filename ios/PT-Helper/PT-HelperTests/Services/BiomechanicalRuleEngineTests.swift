import XCTest
@testable import PT_Helper

final class BiomechanicalRuleEngineTests: XCTestCase {
    private let engine = BiomechanicalRuleEngine.shared

    // MARK: - Rule Selection

    func testRules_squat_returnsSquatRules() {
        let exercise = TestFixtures.makeExercise(name: "Bodyweight Squat", targetArea: "Quadriceps")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_knee"), "Squat rules should include knee angles")
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("trunk"), "Squat rules should include trunk angle")
        XCTAssertEqual(rules.minimumRepROM, 15)
    }

    func testRules_bicepCurl_returnsCurlRules() {
        let exercise = TestFixtures.makeExercise(name: "Bicep Curl", targetArea: "Bicep")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_elbow"), "Curl rules should include elbow angles")
        XCTAssertFalse(rules.expectedAngleRanges.keys.contains("left_knee"), "Curl rules should not include knee angles")
        XCTAssertEqual(rules.minimumRepROM, 20)
    }

    func testRules_plank_returnsStaticHoldRules() {
        let exercise = TestFixtures.makeExercise(name: "Plank Hold", targetArea: "Core")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.isEmpty, "Static hold should have no angle ranges")
        XCTAssertEqual(rules.minimumRepROM, 5)
    }

    func testRules_unknownName_fallsBackToTargetArea() {
        let exercise = TestFixtures.makeExercise(name: "Custom Exercise", targetArea: "Quadriceps")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_knee"), "Should fall back to lower body rules for quad target")
    }

    func testRules_unknownNameAndTarget_returnsGenericRules() {
        let exercise = TestFixtures.makeExercise(name: "Mystery Move", targetArea: "Full Body")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.isEmpty, "Generic rules should have no specific angle ranges")
        XCTAssertEqual(rules.minimumRepROM, 10)
    }

    // MARK: - Angle Range Checks

    func testCheck_anglesWithinRange_allPass() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // Knee angles within squat range (86...170)
        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "left_knee": RepMetrics.AngleRange(minDegrees: 90, maxDegrees: 165, rangeOfMotion: 75, atStart: 165, atMid: 90, atEnd: 165),
                "right_knee": RepMetrics.AngleRange(minDegrees: 88, maxDegrees: 168, rangeOfMotion: 80, atStart: 168, atMid: 88, atEnd: 168),
                "trunk": RepMetrics.AngleRange(minDegrees: 145, maxDegrees: 175, rangeOfMotion: 30, atStart: 175, atMid: 145, atEnd: 175),
            ],
            durationSeconds: 2.5, startTimestamp: 0, endTimestamp: 2.5
        )
        let metrics = TestFixtures.makeFormAnalysisData(repMetrics: [rep])
        let results = engine.check(metrics: metrics, exercise: exercise)

        let allPass = results.allSatisfy { result in
            if case .pass = result.result { return true }
            return false
        }
        XCTAssertTrue(allPass, "Angles within expected range should all pass")
    }

    func testCheck_kneeAngleFarBelowRange_danger() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // Knee goes to 60° — that's 26° below the lower bound of 86°, triggering danger (>20° below)
        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "left_knee": RepMetrics.AngleRange(minDegrees: 60, maxDegrees: 170, rangeOfMotion: 110, atStart: 170, atMid: 60, atEnd: 170),
                "right_knee": RepMetrics.AngleRange(minDegrees: 90, maxDegrees: 170, rangeOfMotion: 80, atStart: 170, atMid: 90, atEnd: 170),
            ],
            durationSeconds: 2.5, startTimestamp: 0, endTimestamp: 2.5
        )
        let metrics = TestFixtures.makeFormAnalysisData(repMetrics: [rep])
        let results = engine.check(metrics: metrics, exercise: exercise)

        let hasDanger = results.contains { result in
            if case .danger = result.result { return true }
            return false
        }
        XCTAssertTrue(hasDanger, "Knee angle far below safe range should trigger danger")
    }

    func testCheck_kneeAngleSlightlyBelowRange_caution() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // Knee goes to 74° — 12° below 86° lower bound (between 10 and 20 below → caution)
        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "left_knee": RepMetrics.AngleRange(minDegrees: 74, maxDegrees: 170, rangeOfMotion: 96, atStart: 170, atMid: 74, atEnd: 170),
                "right_knee": RepMetrics.AngleRange(minDegrees: 90, maxDegrees: 170, rangeOfMotion: 80, atStart: 170, atMid: 90, atEnd: 170),
            ],
            durationSeconds: 2.5, startTimestamp: 0, endTimestamp: 2.5
        )
        let metrics = TestFixtures.makeFormAnalysisData(repMetrics: [rep])
        let results = engine.check(metrics: metrics, exercise: exercise)

        let hasCaution = results.contains { result in
            if case .caution = result.result { return true }
            return false
        }
        XCTAssertTrue(hasCaution, "Knee angle slightly below safe range should trigger caution")
    }

    func testCheck_emptyRepMetrics_allPass() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let metrics = TestFixtures.makeFormAnalysisData(repCount: 0, repMetrics: [])

        let results = engine.check(metrics: metrics, exercise: exercise)

        // Angle range checks should pass (guard !angles.isEmpty returns .pass)
        let angleResults = results.filter { $0.ruleName.hasSuffix("_range") }
        let allPass = angleResults.allSatisfy { result in
            if case .pass = result.result { return true }
            return false
        }
        XCTAssertTrue(allPass, "Empty metrics should produce all-pass for angle range checks")
    }

    // MARK: - Safety Constraints

    func testCheck_squatKneeAsymmetry_caution() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let symmetry = FormAnalysisData.SymmetryData(
            leftAvgAngles: ["knee": 90],
            rightAvgAngles: ["knee": 105],
            differencesDegrees: ["knee": 15]  // >12° threshold
        )
        let metrics = TestFixtures.makeFormAnalysisData(symmetry: symmetry)
        let results = engine.check(metrics: metrics, exercise: exercise)

        let hasSymmetryCaution = results.contains { result in
            result.ruleName == "squat_knee_symmetry" && {
                if case .caution = result.result { return true }
                return false
            }()
        }
        XCTAssertTrue(hasSymmetryCaution, "Knee asymmetry >12° should trigger caution")
    }

    func testCheck_curlShoulderCompensation_caution() {
        let exercise = TestFixtures.makeExercise(name: "Bicep Curl", targetArea: "Bicep")
        // Shoulder ROM > 20° indicates momentum/swinging
        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "left_elbow": RepMetrics.AngleRange(minDegrees: 40, maxDegrees: 160, rangeOfMotion: 120, atStart: 160, atMid: 40, atEnd: 160),
                "left_shoulder": RepMetrics.AngleRange(minDegrees: 30, maxDegrees: 60, rangeOfMotion: 30, atStart: 30, atMid: 60, atEnd: 30),
            ],
            durationSeconds: 2.0, startTimestamp: 0, endTimestamp: 2.0
        )
        let metrics = TestFixtures.makeFormAnalysisData(exerciseName: "Bicep Curl", repMetrics: [rep])
        let results = engine.check(metrics: metrics, exercise: exercise)

        let hasCompensation = results.contains { result in
            result.ruleName == "curl_shoulder_compensation" && {
                if case .caution = result.result { return true }
                return false
            }()
        }
        XCTAssertTrue(hasCompensation, "Shoulder ROM >20° during curl should trigger compensation caution")
    }

    func testCheck_hipHingeTrunkDanger() {
        let exercise = TestFixtures.makeExercise(name: "Deadlift", targetArea: "Hip")
        // Trunk angle < 90° → danger
        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "trunk": RepMetrics.AngleRange(minDegrees: 80, maxDegrees: 170, rangeOfMotion: 90, atStart: 170, atMid: 80, atEnd: 170),
            ],
            durationSeconds: 3.0, startTimestamp: 0, endTimestamp: 3.0
        )
        let metrics = TestFixtures.makeFormAnalysisData(exerciseName: "Deadlift", repMetrics: [rep])
        let results = engine.check(metrics: metrics, exercise: exercise)

        let hasTrunkDanger = results.contains { result in
            result.ruleName == "hinge_trunk_angle" && {
                if case .danger = result.result { return true }
                return false
            }()
        }
        XCTAssertTrue(hasTrunkDanger, "Trunk angle <90° during hip hinge should trigger danger")
    }

    func testCheck_hipHingeTrunkCaution() {
        let exercise = TestFixtures.makeExercise(name: "Deadlift", targetArea: "Hip")
        // Trunk angle 105° → between 90 and 110 → caution
        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "trunk": RepMetrics.AngleRange(minDegrees: 105, maxDegrees: 170, rangeOfMotion: 65, atStart: 170, atMid: 105, atEnd: 170),
            ],
            durationSeconds: 3.0, startTimestamp: 0, endTimestamp: 3.0
        )
        let metrics = TestFixtures.makeFormAnalysisData(exerciseName: "Deadlift", repMetrics: [rep])
        let results = engine.check(metrics: metrics, exercise: exercise)

        let hasTrunkCaution = results.contains { result in
            result.ruleName == "hinge_trunk_angle" && {
                if case .caution = result.result { return true }
                return false
            }()
        }
        XCTAssertTrue(hasTrunkCaution, "Trunk angle 90-110° during hip hinge should trigger caution")
    }

    // MARK: - Rep Detection Threshold

    func testRepDetectionThreshold_squat() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        XCTAssertEqual(engine.repDetectionThreshold(for: exercise), 15)
    }

    func testRepDetectionThreshold_bicepCurl() {
        let exercise = TestFixtures.makeExercise(name: "Bicep Curl", targetArea: "Bicep")
        XCTAssertEqual(engine.repDetectionThreshold(for: exercise), 20)
    }

    func testRepDetectionThreshold_staticHold() {
        let exercise = TestFixtures.makeExercise(name: "Plank Hold", targetArea: "Core")
        XCTAssertEqual(engine.repDetectionThreshold(for: exercise), 5)
    }

    // MARK: - Alignment Thresholds

    // MARK: - Missing Rule Sets

    func testRules_lunge_returnsLungeRules() {
        let exercise = TestFixtures.makeExercise(name: "Walking Lunge", targetArea: "Quadriceps")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_knee"))
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("trunk"))
        XCTAssertEqual(rules.minimumRepROM, 15)
    }

    func testRules_bridge_returnsBridgeRules() {
        let exercise = TestFixtures.makeExercise(name: "Glute Bridge", targetArea: "Glutes")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_hip"))
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_knee"))
        XCTAssertEqual(rules.minimumRepROM, 12)
    }

    func testRules_shoulderPress_returnsPressRules() {
        let exercise = TestFixtures.makeExercise(name: "Overhead Press", targetArea: "Shoulder")
        let rules = engine.rules(for: exercise)

        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_shoulder"))
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_elbow"))
        XCTAssertEqual(rules.minimumRepROM, 15)
    }

    func testRules_gluteTarget_fallsBackToBridgeRules() {
        let exercise = TestFixtures.makeExercise(name: "Custom Exercise", targetArea: "Glutes")
        let rules = engine.rules(for: exercise)

        // Should fall back to bridge rules via target area "glute"
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_hip"))
        XCTAssertEqual(rules.minimumRepROM, 12)
    }

    func testCheck_nilSymmetryData_passesSquatSymmetryCheck() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // No symmetry data → symmetry constraint should pass
        let metrics = TestFixtures.makeFormAnalysisData(symmetry: nil)
        let results = engine.check(metrics: metrics, exercise: exercise)

        let symmetryResult = results.first { $0.ruleName == "squat_knee_symmetry" }
        XCTAssertNotNil(symmetryResult)
        if case .pass = symmetryResult!.result {
            // expected
        } else {
            XCTFail("Nil symmetry data should produce .pass for symmetry check")
        }
    }

    // MARK: - Alignment Thresholds

    func testAlignmentThresholds_plank_tighterThanDefault() {
        let exercise = TestFixtures.makeExercise(name: "Plank Hold", targetArea: "Core")
        let thresholds = engine.alignmentThresholds(for: exercise)

        XCTAssertEqual(thresholds.trunkLeanMeters, 0.10, "Plank should have tighter trunk lean threshold")
        XCTAssertLessThan(thresholds.trunkLeanMeters, AlignmentThresholds.default.trunkLeanMeters)
    }

    // MARK: - New Exercise Rules

    func testRules_pushUp_matchesByName() {
        let exercise = TestFixtures.makeExercise(name: "Push Up", targetArea: "Chest")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_elbow"))
        XCTAssertTrue(rules.safetyConstraints.contains { $0.name == "pushup_trunk_straightness" })
    }

    func testRules_row_matchesByName() {
        let exercise = TestFixtures.makeExercise(name: "Bent Over Row", targetArea: "Back")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_elbow"))
        XCTAssertTrue(rules.safetyConstraints.contains { $0.name == "row_shoulder_compensation" })
    }

    func testRules_calfRaise_matchesByName() {
        let exercise = TestFixtures.makeExercise(name: "Standing Calf Raise", targetArea: "Calves")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_knee"))
        XCTAssertEqual(rules.minimumRepROM, 8)
    }

    func testRules_birdDog_matchesByName() {
        let exercise = TestFixtures.makeExercise(name: "Bird Dog", targetArea: "Core")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_hip"))
        XCTAssertTrue(rules.safetyConstraints.contains { $0.name == "birddog_trunk_stability" })
    }

    func testRules_clamshell_matchesByName() {
        let exercise = TestFixtures.makeExercise(name: "Clamshell", targetArea: "Glutes")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.expectedAngleRanges.keys.contains("left_hip"))
        XCTAssertTrue(rules.safetyConstraints.contains { $0.name == "clamshell_trunk_rotation" })
    }

    // MARK: - Category-Level Rules

    func testRules_stretchCategory_usesStretchRules() {
        let exercise = TestFixtures.makeExercise(name: "Custom Stretch", targetArea: "Full Body", exerciseCategory: "stretch")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.safetyConstraints.contains { $0.name == "stretch_bouncing" })
        XCTAssertEqual(rules.minimumRepROM, 5)
    }

    func testRules_balanceCategory_usesBalanceRules() {
        let exercise = TestFixtures.makeExercise(name: "Single Leg Stand", targetArea: "Full Body", exerciseCategory: "balance")
        let rules = engine.rules(for: exercise)
        XCTAssertTrue(rules.safetyConstraints.contains { $0.name == "balance_sway" })
        XCTAssertEqual(rules.alignmentThresholds.trunkLeanMeters, 0.08)
    }
}
