import XCTest
@testable import COIL

final class DataQualityScorerTests: XCTestCase {
    private let scorer = DataQualityScorer.shared

    // MARK: - Link-Length Consistency

    func testLinkLengthConsistency_stableBoneLengths_highScore() {
        // Create 10 frames with consistent joint positions
        let poses = (0..<10).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033)
        }
        let score = scorer.computeLinkLengthConsistency(poses: poses)
        XCTAssertGreaterThanOrEqual(score, 0.9, "Consistent bone lengths should produce a high score")
    }

    func testLinkLengthConsistency_jitteryPositions_lowScore() {
        // Create 10 frames where bone segment lengths change dramatically per frame.
        // Each frame places joints at completely different relative positions so
        // the distance between connected joints varies wildly across frames.
        let poses = (0..<10).map { i -> PoseFrame in
            var joints: [String: JointPoint3D] = [:]
            let scale = Double(i % 2 == 0 ? 1 : 5)  // alternate between compact and spread out
            for (j, joint) in BodyJoint3D.allCases.enumerated() {
                joints[joint.rawValue] = JointPoint3D(
                    x: Double(j) * 0.05 * scale,
                    y: Double(j) * 0.1 * scale,
                    z: 0, confidence: 0.9
                )
            }
            return TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033, joints: joints)
        }
        let score = scorer.computeLinkLengthConsistency(poses: poses)
        XCTAssertLessThan(score, 0.9, "Jittery bone lengths should produce a lower score")
    }

    func testLinkLengthConsistency_fewerThan5Frames_returns1() {
        let poses = (0..<3).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033)
        }
        let score = scorer.computeLinkLengthConsistency(poses: poses)
        XCTAssertEqual(score, 1.0, "Too few frames should return 1.0 (not enough to assess)")
    }

    // MARK: - Temporal Outlier Detection

    func testTemporalOutliers_stableSequence_zeroOutliers() {
        // 20 frames with identical joint positions → no outliers
        let poses = (0..<20).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033)
        }
        let count = scorer.detectTemporalOutliers(poses: poses)
        XCTAssertEqual(count, 0, "Stable sequence should have zero outliers")
    }

    func testTemporalOutliers_suddenJump_detected() {
        // Create 20 stable frames, then inject a large jump at frame 12
        var poses = (0..<20).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033)
        }
        // Replace frame 12 with drastically different positions
        var jumpJoints: [String: JointPoint3D] = [:]
        for joint in BodyJoint3D.allCases {
            jumpJoints[joint.rawValue] = JointPoint3D(x: 5.0, y: 5.0, z: 5.0, confidence: 0.9)
        }
        poses[12] = TestFixtures.makePoseFrame(timestamp: 12 * 0.033, joints: jumpJoints)

        let count = scorer.detectTemporalOutliers(poses: poses)
        XCTAssertGreaterThan(count, 0, "A sudden joint jump should be detected as an outlier")
    }

    func testTemporalOutliers_tooFewFrames_returnsZero() {
        let poses = (0..<5).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033)
        }
        let count = scorer.detectTemporalOutliers(poses: poses)
        XCTAssertEqual(count, 0, "Too few frames for rolling window should return 0")
    }

    // MARK: - Full Score Pipeline

    func testScore_highQualityData_highOverallScore() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // Create 90 frames over 3 seconds with all joints → high quality
        // Need ≥30 frames with primary joints AND ≥2s duration for minimum threshold
        let poses = (0..<90).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) / 30.0)
        }
        let report = scorer.score(poses: poses, totalVideoFrames: 90, exercise: exercise)

        XCTAssertGreaterThan(report.overallScore, 0.5, "High quality data should produce a good overall score")
        XCTAssertTrue(report.minimumDataThresholdMet, "90 frames over 3s should meet minimum threshold")
        XCTAssertEqual(report.framesWithPose, 90)
        XCTAssertEqual(report.totalVideoFrames, 90)
    }

    func testScore_emptyPoses_lowScore() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let report = scorer.score(poses: [], totalVideoFrames: 100, exercise: exercise)

        XCTAssertEqual(report.framesWithPose, 0)
        XCTAssertFalse(report.minimumDataThresholdMet, "Empty poses should not meet minimum threshold")
        XCTAssertFalse(report.warnings.isEmpty, "Empty poses should produce warnings")
    }

    func testScore_lowFrameCoverage_generatesWarning() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // Only 20 frames out of 100 total (20% coverage, below 50% threshold)
        let poses = (0..<20).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) / 10.0)
        }
        let report = scorer.score(poses: poses, totalVideoFrames: 100, exercise: exercise)

        XCTAssertLessThan(report.frameCoverage, 0.5)
        let hasCoverageWarning = report.warnings.contains { $0.contains("less than half") }
        XCTAssertTrue(hasCoverageWarning, "Low frame coverage should produce a warning")
    }

    func testScore_sparseJoints_generatesWarning() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // 60 frames but only 5 joints each (below 12 joint threshold)
        let poses = (0..<60).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) / 30.0, jointCount: 5)
        }
        let report = scorer.score(poses: poses, totalVideoFrames: 60, exercise: exercise)

        XCTAssertLessThan(report.averageJointCount, 12)
        let hasJointWarning = report.warnings.contains { $0.contains("joints were not consistently") }
        XCTAssertTrue(hasJointWarning, "Sparse joints should produce a warning")
    }

    func testScore_shortDuration_minimumThresholdNotMet() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        // 10 frames over 0.3 seconds (below 2s duration threshold)
        let poses = (0..<10).map { i in
            TestFixtures.makePoseFrame(timestamp: Double(i) * 0.033)
        }
        let report = scorer.score(poses: poses, totalVideoFrames: 10, exercise: exercise)

        XCTAssertFalse(report.minimumDataThresholdMet, "Short duration should not meet minimum threshold")
    }
}
