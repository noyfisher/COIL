import Foundation

// MARK: - Data Quality Scorer

/// Evaluates pose detection data quality BEFORE sending to Claude.
/// Produces a DataQualityReport that travels with the metrics and informs
/// both the AI prompt and the post-analysis validation pipeline.
class DataQualityScorer {
    static let shared = DataQualityScorer()

    /// Bone segment pairs for link-length consistency checking.
    /// These distances should be nearly constant across frames (same person).
    private static let boneSegments: [(name: String, from: BodyJoint3D, to: BodyJoint3D)] = [
        ("left_upper_arm", .leftShoulder, .leftElbow),
        ("right_upper_arm", .rightShoulder, .rightElbow),
        ("left_forearm", .leftElbow, .leftWrist),
        ("right_forearm", .rightElbow, .rightWrist),
        ("left_thigh", .leftHip, .leftKnee),
        ("right_thigh", .rightHip, .rightKnee),
        ("left_shin", .leftKnee, .leftAnkle),
        ("right_shin", .rightKnee, .rightAnkle),
        ("torso", .neck, .root),
    ]

    private init() {}

    // MARK: - Public API

    /// Score the quality of pose detection data.
    /// - Parameters:
    ///   - poses: Detected pose frames
    ///   - totalVideoFrames: Total frames in the original video (including undetected)
    ///   - exercise: The exercise being analyzed (for primary angle checking)
    ///   - analysisEngine: Engine to determine primary angle
    func score(
        poses: [PoseFrame],
        totalVideoFrames: Int,
        exercise: RehabExercise,
        fps: Double = 30.0,
        analysisEngine: PoseAnalysisEngine = .shared
    ) -> DataQualityReport {
        var warnings: [String] = []

        // 1. Frame coverage
        let frameCoverage = totalVideoFrames > 0
            ? Double(poses.count) / Double(totalVideoFrames)
            : 0
        if frameCoverage < 0.5 {
            warnings.append("Body was detected in less than half of the video frames. Try recording with better visibility.")
        }

        // 2. Joint completeness
        let avgJointCount: Double = poses.isEmpty ? 0 : {
            let totalJoints = poses.map { Double($0.joints.count) }.reduce(0, +)
            return totalJoints / Double(poses.count)
        }()
        if avgJointCount < 12 {
            warnings.append("Some body joints were not consistently detected. Ensure your full body is visible.")
        }

        // Check primary angle joints availability
        let primaryAngle = analysisEngine.determinePrimaryAngle(for: exercise)
        let primaryJoints = primaryAngleJoints(for: primaryAngle)
        let framesWithPrimaryJoints = poses.filter { frame in
            primaryJoints.allSatisfy { frame.joints[$0] != nil }
        }.count
        let primaryJointCoverage = poses.isEmpty ? 0 : Double(framesWithPrimaryJoints) / Double(poses.count)
        if primaryJointCoverage < 0.7 {
            warnings.append("Key joints for this exercise were not visible in \(Int((1 - primaryJointCoverage) * 100))% of frames.")
        }

        // 3. Link-length consistency
        let linkConsistency = computeLinkLengthConsistency(poses: poses)
        if linkConsistency < 0.7 {
            warnings.append("Body measurement consistency is low, which may affect angle accuracy.")
        }

        // 4. Temporal outlier detection
        let outlierCount = detectTemporalOutliers(poses: poses, fps: fps)
        if outlierCount > poses.count / 5 {
            warnings.append("\(outlierCount) frames had sudden joint position jumps (possible detection noise).")
        }

        // 5. Minimum data threshold
        let hasEnoughDuration = poses.count >= 2 &&
            (poses.last?.timestamp ?? 0) - (poses.first?.timestamp ?? 0) >= 2.0
        let hasEnoughPrimaryFrames = framesWithPrimaryJoints >= 30
        let minimumMet = hasEnoughDuration && hasEnoughPrimaryFrames

        if !minimumMet {
            if !hasEnoughDuration {
                warnings.append("Video is too short for reliable analysis. Record at least 3 seconds.")
            }
            if !hasEnoughPrimaryFrames {
                warnings.append("Not enough frames with key joints visible. Try better lighting or camera angle.")
            }
        }

        // Compute overall score (weighted average)
        let overallScore = computeOverallScore(
            frameCoverage: frameCoverage,
            avgJointCount: avgJointCount,
            linkConsistency: linkConsistency,
            outlierRate: poses.isEmpty ? 1 : Double(outlierCount) / Double(poses.count),
            primaryJointCoverage: primaryJointCoverage,
            minimumMet: minimumMet
        )

        return DataQualityReport(
            overallScore: overallScore,
            frameCoverage: frameCoverage,
            averageJointCount: avgJointCount,
            linkLengthConsistency: linkConsistency,
            temporalOutlierCount: outlierCount,
            totalVideoFrames: totalVideoFrames,
            framesWithPose: poses.count,
            minimumDataThresholdMet: minimumMet,
            warnings: warnings
        )
    }

    // MARK: - Link-Length Consistency

    /// Compute how stable bone segment lengths are across frames.
    /// Returns 0.0–1.0 where 1.0 means perfectly consistent.
    func computeLinkLengthConsistency(poses: [PoseFrame]) -> Double {
        guard poses.count >= 5 else { return 1.0 }  // too few frames to assess

        var consistencyScores: [Double] = []

        for segment in Self.boneSegments {
            let lengths = poses.compactMap { frame -> Double? in
                guard let from = frame.joints[segment.from.rawValue],
                      let to = frame.joints[segment.to.rawValue] else { return nil }
                return distance(from, to)
            }

            guard lengths.count >= 5 else { continue }

            let mean = lengths.reduce(0, +) / Double(lengths.count)
            guard mean > 0.01 else { continue }  // skip zero-length segments

            let variance = lengths.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lengths.count)
            let sd = sqrt(variance)
            let coeffOfVariation = sd / mean

            // CV < 0.1 (10%) is good; > 0.2 (20%) is bad
            let segmentScore = max(0, min(1, 1.0 - (coeffOfVariation / 0.2)))
            consistencyScores.append(segmentScore)
        }

        guard !consistencyScores.isEmpty else { return 1.0 }
        return consistencyScores.reduce(0, +) / Double(consistencyScores.count)
    }

    // MARK: - Temporal Outlier Detection

    /// Count frames where any joint position jumps more than 3 SD from the rolling mean.
    /// Iterates frames first (outer), joints second (inner) to avoid double-counting.
    func detectTemporalOutliers(poses: [PoseFrame], fps: Double = 30.0) -> Int {
        let windowSize = max(3, Int(fps * 0.15))
        guard poses.count > windowSize * 2 else { return 0 }

        let allJointNames = Array(Set(poses.flatMap { $0.joints.keys }))
        var outlierFrames: Set<Int> = []

        // Pre-extract joint positions indexed by frame for efficient lookup
        var jointPositions: [String: [(frame: Int, x: Double, y: Double, z: Double)]] = [:]
        for jointName in allJointNames {
            jointPositions[jointName] = poses.enumerated().compactMap { (i, frame) in
                guard let joint = frame.joints[jointName] else { return nil }
                return (i, joint.x, joint.y, joint.z)
            }
        }

        // Check each frame: is it an outlier for ANY joint?
        for frameIdx in windowSize..<(poses.count - windowSize) {
            if outlierFrames.contains(frameIdx) { continue }

            for jointName in allJointNames {
                guard let positions = jointPositions[jointName] else { continue }

                // Find this frame and its window in the joint's position array
                guard let posIdx = positions.firstIndex(where: { $0.frame == frameIdx }) else { continue }
                let windowStart = max(0, posIdx - windowSize)
                guard windowStart < posIdx else { continue }

                let window = positions[windowStart..<posIdx]
                guard window.count >= 2 else { continue }
                let wCount = Double(window.count)

                let meanX = window.map { $0.x }.reduce(0, +) / wCount
                let meanY = window.map { $0.y }.reduce(0, +) / wCount
                let meanZ = window.map { $0.z }.reduce(0, +) / wCount

                let sdX = sqrt(window.map { ($0.x - meanX) * ($0.x - meanX) }.reduce(0, +) / wCount)
                let sdY = sqrt(window.map { ($0.y - meanY) * ($0.y - meanY) }.reduce(0, +) / wCount)
                let sdZ = sqrt(window.map { ($0.z - meanZ) * ($0.z - meanZ) }.reduce(0, +) / wCount)

                let current = positions[posIdx]
                let threshold = 3.0
                if abs(current.x - meanX) > threshold * max(sdX, 0.01) ||
                    abs(current.y - meanY) > threshold * max(sdY, 0.01) ||
                    abs(current.z - meanZ) > threshold * max(sdZ, 0.01) {
                    outlierFrames.insert(frameIdx)
                    break  // This frame is an outlier — no need to check more joints
                }
            }
        }

        return outlierFrames.count
    }

    // MARK: - Helpers

    private func distance(_ a: JointPoint3D, _ b: JointPoint3D) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /// Get the joint names needed for a given primary angle.
    private func primaryAngleJoints(for angleName: String) -> [String] {
        guard let angleDef = BodyJoint3D.commonAngles.first(where: { $0.name == angleName }) else {
            return []
        }
        return [angleDef.proximal.rawValue, angleDef.vertex.rawValue, angleDef.distal.rawValue]
    }

    private func computeOverallScore(
        frameCoverage: Double,
        avgJointCount: Double,
        linkConsistency: Double,
        outlierRate: Double,
        primaryJointCoverage: Double,
        minimumMet: Bool
    ) -> Double {
        guard minimumMet else { return max(0.1, frameCoverage * 0.3) }

        let jointScore = min(1.0, avgJointCount / 17.0)
        let outlierScore = max(0, 1.0 - outlierRate * 5)  // penalize heavily

        let score = frameCoverage * 0.2
            + jointScore * 0.2
            + linkConsistency * 0.25
            + outlierScore * 0.15
            + primaryJointCoverage * 0.2

        return min(1.0, max(0, score))
    }
}
