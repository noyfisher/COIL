import XCTest
@testable import PT_Helper

final class PoseAnalysisEngineTests: XCTestCase {
    private let engine = PoseAnalysisEngine.shared

    // MARK: - Angle Calculation

    func testAngleBetween_rightAngle_returns90() {
        // Points forming a right angle: A(1,0,0), vertex(0,0,0), C(0,1,0)
        let pointA = JointPoint3D(x: 1, y: 0, z: 0, confidence: 1.0)
        let vertex = JointPoint3D(x: 0, y: 0, z: 0, confidence: 1.0)
        let pointC = JointPoint3D(x: 0, y: 1, z: 0, confidence: 1.0)

        let angle = engine.angleBetween(pointA: pointA, vertex: vertex, pointC: pointC)
        XCTAssertEqual(angle, 90.0, accuracy: 0.1, "Should compute 90° for a right angle")
    }

    func testAngleBetween_straightLine_returns180() {
        // Points in a straight line: A(-1,0,0), vertex(0,0,0), C(1,0,0)
        let pointA = JointPoint3D(x: -1, y: 0, z: 0, confidence: 1.0)
        let vertex = JointPoint3D(x: 0, y: 0, z: 0, confidence: 1.0)
        let pointC = JointPoint3D(x: 1, y: 0, z: 0, confidence: 1.0)

        let angle = engine.angleBetween(pointA: pointA, vertex: vertex, pointC: pointC)
        XCTAssertEqual(angle, 180.0, accuracy: 0.1, "Should compute 180° for a straight line")
    }

    func testAngleBetween_acuteAngle_returns45() {
        // 45-degree angle using known vectors
        let pointA = JointPoint3D(x: 1, y: 0, z: 0, confidence: 1.0)
        let vertex = JointPoint3D(x: 0, y: 0, z: 0, confidence: 1.0)
        let pointC = JointPoint3D(x: 1, y: 1, z: 0, confidence: 1.0)

        let angle = engine.angleBetween(pointA: pointA, vertex: vertex, pointC: pointC)
        XCTAssertEqual(angle, 45.0, accuracy: 0.1, "Should compute 45° for a 45-degree angle")
    }

    func testAngleBetween_3D_computesCorrectly() {
        // 3D angle: A(1,0,0), vertex(0,0,0), C(0,0,1) — should be 90°
        let pointA = JointPoint3D(x: 1, y: 0, z: 0, confidence: 1.0)
        let vertex = JointPoint3D(x: 0, y: 0, z: 0, confidence: 1.0)
        let pointC = JointPoint3D(x: 0, y: 0, z: 1, confidence: 1.0)

        let angle = engine.angleBetween(pointA: pointA, vertex: vertex, pointC: pointC)
        XCTAssertEqual(angle, 90.0, accuracy: 0.1, "Should compute 90° in 3D space")
    }

    func testAngleBetween_coincidentPoints_returns0() {
        // When vertex and a point are the same, should return 0 (degenerate case)
        let pointA = JointPoint3D(x: 0, y: 0, z: 0, confidence: 1.0)
        let vertex = JointPoint3D(x: 0, y: 0, z: 0, confidence: 1.0)
        let pointC = JointPoint3D(x: 1, y: 0, z: 0, confidence: 1.0)

        let angle = engine.angleBetween(pointA: pointA, vertex: vertex, pointC: pointC)
        XCTAssertEqual(angle, 0.0, accuracy: 0.1, "Should handle degenerate case gracefully")
    }

    // MARK: - Frame Angle Computation

    func testComputeAngles_withValidFrame_returnsAngles() {
        let frame = makeSquatFrame(kneeAngle: 90)
        let angles = engine.computeAngles(for: frame)

        XCTAssertFalse(angles.isEmpty, "Should compute at least one angle")
        XCTAssertNotNil(angles["left_knee"], "Should compute left knee angle")
        XCTAssertNotNil(angles["right_knee"], "Should compute right knee angle")
    }

    func testComputeAngles_withLowConfidence_skipsJoint() {
        var frame = makeSquatFrame(kneeAngle: 90)
        // Set one joint to low confidence
        frame = PoseFrame(
            timestamp: 0,
            joints: frame.joints.merging([
                BodyJoint3D.leftKnee.rawValue: JointPoint3D(x: 0, y: 0.5, z: 0, confidence: 0.1)
            ]) { _, new in new },
            bodyHeight: nil
        )

        let angles = engine.computeAngles(for: frame)
        // left_knee may be missing because leftKnee has low confidence
        // but right_knee should still be computed
        XCTAssertNotNil(angles["right_knee"], "Should compute right knee even if left has low confidence")
    }

    // MARK: - Primary Angle Determination

    func testDeterminePrimaryAngle_squat_returnsKnee() {
        let exercise = TestFixtures.makeExercise(name: "Bodyweight Squat", targetArea: "Quadriceps")
        let angle = engine.determinePrimaryAngle(for: exercise)
        XCTAssertEqual(angle, "left_knee")
    }

    func testDeterminePrimaryAngle_curl_returnsElbow() {
        let exercise = TestFixtures.makeExercise(name: "Bicep Curl", targetArea: "Biceps")
        let angle = engine.determinePrimaryAngle(for: exercise)
        XCTAssertEqual(angle, "left_elbow")
    }

    func testDeterminePrimaryAngle_bridge_returnsHip() {
        let exercise = TestFixtures.makeExercise(name: "Glute Bridge", targetArea: "Glutes")
        let angle = engine.determinePrimaryAngle(for: exercise)
        XCTAssertEqual(angle, "left_hip")
    }

    func testDeterminePrimaryAngle_shoulderPress_returnsShoulder() {
        let exercise = TestFixtures.makeExercise(name: "Overhead Press", targetArea: "Shoulders")
        let angle = engine.determinePrimaryAngle(for: exercise)
        XCTAssertEqual(angle, "left_shoulder")
    }

    // MARK: - Smoothing (One-Euro Filter)

    func testSmoothPoses_singleFrame_returnsUnchanged() {
        let frame = makeSquatFrame(kneeAngle: 90)
        let smoothed = engine.smoothPoses([frame], fps: 30.0)
        XCTAssertEqual(smoothed.count, 1)
        XCTAssertEqual(smoothed[0].joints.count, frame.joints.count)
    }

    func testSmoothPoses_multipleFrames_reducesJitter() {
        // Create frames with jittery knee position
        var frames: [PoseFrame] = []
        for i in 0..<10 {
            let jitter = Double(i % 2 == 0 ? 1 : -1) * 0.02  // 2cm jitter
            var joints = makeSquatJoints(kneeAngle: 90)
            if let knee = joints[BodyJoint3D.leftKnee.rawValue] {
                joints[BodyJoint3D.leftKnee.rawValue] = JointPoint3D(
                    x: knee.x + jitter, y: knee.y, z: knee.z,
                    confidence: knee.confidence
                )
            }
            frames.append(PoseFrame(timestamp: Double(i) / 30.0, joints: joints, bodyHeight: nil))
        }

        let smoothed = engine.smoothPoses(frames, fps: 30.0)

        // Smoothed positions should have less variance than original
        let originalXPositions = frames.compactMap { $0.joints[BodyJoint3D.leftKnee.rawValue]?.x }
        let smoothedXPositions = smoothed.compactMap { $0.joints[BodyJoint3D.leftKnee.rawValue]?.x }

        let originalVariance = variance(of: originalXPositions)
        let smoothedVariance = variance(of: smoothedXPositions)

        XCTAssertLessThan(smoothedVariance, originalVariance,
                          "Smoothed positions should have less variance than jittery originals")
    }

    // MARK: - Full Analysis Pipeline

    func testAnalyze_emptyPoses_returnsZeroReps() {
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let result = engine.analyze(poses: [], exercise: exercise, videoFPS: 30, videoDuration: 10)

        XCTAssertEqual(result.detectedRepCount, 0)
        XCTAssertTrue(result.repMetrics.isEmpty)
        XCTAssertEqual(result.exerciseName, "Squat")
    }

    func testAnalyze_squatSequence_detectsReps() {
        let exercise = TestFixtures.makeExercise(name: "Bodyweight Squat", targetArea: "Quadriceps")
        let frames = makeSquatRepSequence(repCount: 3, framesPerRep: 30, fps: 30.0)

        let result = engine.analyze(poses: frames, exercise: exercise, videoFPS: 30, videoDuration: 3.0)

        // Should detect approximately 3 reps (±1 due to detection thresholds)
        XCTAssertGreaterThanOrEqual(result.detectedRepCount, 2, "Should detect at least 2 of 3 reps")
        XCTAssertLessThanOrEqual(result.detectedRepCount, 4, "Should not over-detect reps")
        XCTAssertEqual(result.exerciseName, "Bodyweight Squat")
        XCTAssertEqual(result.targetArea, "Quadriceps")
    }

    // MARK: - Helpers

    /// Create a PoseFrame with all joints positioned for a squat at the given knee angle.
    private func makeSquatFrame(kneeAngle: Double) -> PoseFrame {
        PoseFrame(
            timestamp: 0,
            joints: makeSquatJoints(kneeAngle: kneeAngle),
            bodyHeight: 1.75
        )
    }

    /// Create joint positions for a squat pose at the given knee angle.
    private func makeSquatJoints(kneeAngle: Double) -> [String: JointPoint3D] {
        // Simplified 3D skeleton at a given knee angle
        let hipY: Double = 0.9
        let kneeY = hipY - 0.4
        let ankleY: Double = 0.0

        // Calculate knee position based on angle
        let kneeRad = kneeAngle * .pi / 180.0
        let kneeForwardOffset = 0.4 * sin(.pi - kneeRad)

        return [
            BodyJoint3D.root.rawValue: JointPoint3D(x: 0, y: hipY, z: 0, confidence: 0.9),
            BodyJoint3D.spine.rawValue: JointPoint3D(x: 0, y: hipY + 0.2, z: 0, confidence: 0.9),
            BodyJoint3D.neck.rawValue: JointPoint3D(x: 0, y: hipY + 0.5, z: 0, confidence: 0.9),
            BodyJoint3D.head.rawValue: JointPoint3D(x: 0, y: hipY + 0.6, z: 0, confidence: 0.9),
            BodyJoint3D.topHead.rawValue: JointPoint3D(x: 0, y: hipY + 0.65, z: 0, confidence: 0.9),
            BodyJoint3D.leftShoulder.rawValue: JointPoint3D(x: -0.2, y: hipY + 0.4, z: 0, confidence: 0.9),
            BodyJoint3D.rightShoulder.rawValue: JointPoint3D(x: 0.2, y: hipY + 0.4, z: 0, confidence: 0.9),
            BodyJoint3D.leftElbow.rawValue: JointPoint3D(x: -0.2, y: hipY + 0.15, z: 0.1, confidence: 0.9),
            BodyJoint3D.rightElbow.rawValue: JointPoint3D(x: 0.2, y: hipY + 0.15, z: 0.1, confidence: 0.9),
            BodyJoint3D.leftWrist.rawValue: JointPoint3D(x: -0.2, y: hipY, z: 0.15, confidence: 0.9),
            BodyJoint3D.rightWrist.rawValue: JointPoint3D(x: 0.2, y: hipY, z: 0.15, confidence: 0.9),
            BodyJoint3D.leftHip.rawValue: JointPoint3D(x: -0.12, y: hipY, z: 0, confidence: 0.9),
            BodyJoint3D.rightHip.rawValue: JointPoint3D(x: 0.12, y: hipY, z: 0, confidence: 0.9),
            BodyJoint3D.leftKnee.rawValue: JointPoint3D(x: -0.12, y: kneeY, z: kneeForwardOffset, confidence: 0.9),
            BodyJoint3D.rightKnee.rawValue: JointPoint3D(x: 0.12, y: kneeY, z: kneeForwardOffset, confidence: 0.9),
            BodyJoint3D.leftAnkle.rawValue: JointPoint3D(x: -0.12, y: ankleY, z: 0, confidence: 0.9),
            BodyJoint3D.rightAnkle.rawValue: JointPoint3D(x: 0.12, y: ankleY, z: 0, confidence: 0.9),
        ]
    }

    /// Create a sequence of frames simulating squat reps.
    private func makeSquatRepSequence(repCount: Int, framesPerRep: Int, fps: Double) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        let totalFrames = repCount * framesPerRep

        for i in 0..<totalFrames {
            let phaseInRep = Double(i % framesPerRep) / Double(framesPerRep)
            // Sine wave: goes from 170° (standing) to 80° (squat depth) and back
            let kneeAngle = 125.0 + 45.0 * cos(phaseInRep * 2.0 * .pi)

            let joints = makeSquatJoints(kneeAngle: kneeAngle)
            frames.append(PoseFrame(
                timestamp: Double(i) / fps,
                joints: joints,
                bodyHeight: 1.75
            ))
        }

        return frames
    }

    /// Compute variance of an array of Doubles.
    private func variance(of values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
    }
}
