import Foundation

// MARK: - Pose Analysis Engine

/// Computes exercise form metrics from raw 3D pose frames.
/// Pure computation — no network calls. Includes smoothing (One-Euro filter),
/// angle calculation, rep detection, symmetry, and alignment analysis.
class PoseAnalysisEngine {
    static let shared = PoseAnalysisEngine()

    /// Minimum confidence for a joint to be used in angle calculation
    private let minJointConfidence: Double = 0.3

    private init() {}

    // MARK: - Public API

    /// Analyze a sequence of pose frames for a specific exercise.
    func analyze(
        poses: [PoseFrame],
        exercise: RehabExercise,
        videoFPS: Double,
        videoDuration: Double
    ) -> FormAnalysisData {
        guard !poses.isEmpty else {
            return emptyResult(exercise: exercise, fps: videoFPS, duration: videoDuration)
        }

        // Step 1: Smooth joint positions using One-Euro filter
        let smoothedPoses = smoothPoses(poses, fps: videoFPS)

        // Step 2: Compute joint angles for every frame
        let frameAngles = computeAllFrameAngles(smoothedPoses)

        // Step 3: Determine primary angle for rep detection based on exercise
        let primaryAngleName = determinePrimaryAngle(for: exercise)

        // Step 4: Detect reps
        let reps = detectReps(frameAngles: frameAngles, poses: smoothedPoses, primaryAngle: primaryAngleName)

        // Step 5: Compute per-rep metrics
        let repMetrics = computeRepMetrics(reps: reps, frameAngles: frameAngles, poses: smoothedPoses)

        // Step 6: Compute symmetry
        let symmetry = computeSymmetry(frameAngles: frameAngles)

        // Step 7: Check alignment
        let alignment = checkAlignment(poses: smoothedPoses, reps: reps, exercise: exercise)

        // Step 8: Compute tempo
        let (avgTempo, tempoSD) = computeTempo(repMetrics: repMetrics)

        // Step 9: Body height (use median across frames)
        let heights = poses.compactMap { $0.bodyHeight }
        let bodyHeight = heights.isEmpty ? nil : heights.sorted()[heights.count / 2]

        return FormAnalysisData(
            exerciseName: exercise.name,
            exerciseCategory: exercise.exerciseCategory,
            targetArea: exercise.targetArea,
            totalFramesProcessed: poses.count,
            videoFPS: videoFPS,
            videoDurationSeconds: videoDuration,
            detectedRepCount: repMetrics.count,
            repMetrics: repMetrics,
            symmetry: symmetry,
            alignment: alignment,
            averageTempo: avgTempo,
            tempoVariability: tempoSD,
            bodyHeight: bodyHeight
        )
    }

    // MARK: - One-Euro Filter (Ported from Forma)

    /// Smooth 3D joint positions using the One-Euro filter.
    /// Adapted from forma/pipeline/smoothing.py lines 83-144.
    func smoothPoses(
        _ poses: [PoseFrame],
        fps: Double,
        minCutoff: Double = 1.0,
        beta: Double = 0.05,
        dCutoff: Double = 1.0
    ) -> [PoseFrame] {
        guard poses.count > 1 else { return poses }

        let freq = fps > 0 ? fps : 30.0
        let allJointNames = Array(Set(poses.flatMap { $0.joints.keys }))

        // Per-joint state
        var prevRaw: [String: (x: Double, y: Double, z: Double)] = [:]
        var prevFiltered: [String: (x: Double, y: Double, z: Double)] = [:]
        var dHat: [String: (dx: Double, dy: Double, dz: Double)] = [:]

        // Initialize from first frame
        for name in allJointNames {
            if let joint = poses[0].joints[name] {
                prevRaw[name] = (joint.x, joint.y, joint.z)
                prevFiltered[name] = (joint.x, joint.y, joint.z)
                dHat[name] = (0, 0, 0)
            }
        }

        var smoothed = [poses[0]]  // first frame unchanged

        for t in 1..<poses.count {
            var newJoints: [String: JointPoint3D] = [:]

            for name in allJointNames {
                guard let joint = poses[t].joints[name],
                      let prev = prevRaw[name],
                      let prevF = prevFiltered[name],
                      var dh = dHat[name] else {
                    // Keep original if no previous data
                    if let joint = poses[t].joints[name] {
                        newJoints[name] = joint
                    }
                    continue
                }

                // Compute derivative
                let dx = (joint.x - prev.x) * freq
                let dy = (joint.y - prev.y) * freq
                let dz = (joint.z - prev.z) * freq

                // Low-pass filter the derivative
                let alphaD = lowpassAlpha(cutoff: dCutoff, freq: freq)
                dh.dx = alphaD * dx + (1 - alphaD) * dh.dx
                dh.dy = alphaD * dy + (1 - alphaD) * dh.dy
                dh.dz = alphaD * dz + (1 - alphaD) * dh.dz

                // Adaptive cutoff
                let cutoffX = minCutoff + beta * abs(dh.dx)
                let cutoffY = minCutoff + beta * abs(dh.dy)
                let cutoffZ = minCutoff + beta * abs(dh.dz)

                let alphaX = lowpassAlpha(cutoff: cutoffX, freq: freq)
                let alphaY = lowpassAlpha(cutoff: cutoffY, freq: freq)
                let alphaZ = lowpassAlpha(cutoff: cutoffZ, freq: freq)

                // Filter position
                let filtX = alphaX * joint.x + (1 - alphaX) * prevF.x
                let filtY = alphaY * joint.y + (1 - alphaY) * prevF.y
                let filtZ = alphaZ * joint.z + (1 - alphaZ) * prevF.z

                newJoints[name] = JointPoint3D(
                    x: filtX, y: filtY, z: filtZ,
                    confidence: joint.confidence
                )

                prevRaw[name] = (joint.x, joint.y, joint.z)
                prevFiltered[name] = (filtX, filtY, filtZ)
                dHat[name] = dh
            }

            smoothed.append(PoseFrame(
                timestamp: poses[t].timestamp,
                joints: newJoints,
                bodyHeight: poses[t].bodyHeight
            ))
        }

        return smoothed
    }

    /// Low-pass filter alpha from cutoff frequency.
    /// Ported from Forma's _lowpass_alpha function.
    private func lowpassAlpha(cutoff: Double, freq: Double) -> Double {
        let c = max(cutoff, 1e-3)
        let tau = 1.0 / (2.0 * .pi * c)
        return 1.0 / (1.0 + tau * freq)
    }

    // MARK: - Angle Calculation

    /// Compute the angle (in degrees) at vertex B given points A, B, C in 3D.
    /// Uses dot product formula: angle = acos(BA·BC / |BA||BC|)
    func angleBetween(
        pointA: JointPoint3D,
        vertex: JointPoint3D,
        pointC: JointPoint3D
    ) -> Double {
        let ba = (x: pointA.x - vertex.x, y: pointA.y - vertex.y, z: pointA.z - vertex.z)
        let bc = (x: pointC.x - vertex.x, y: pointC.y - vertex.y, z: pointC.z - vertex.z)

        let dot = ba.x * bc.x + ba.y * bc.y + ba.z * bc.z
        let magBA = sqrt(ba.x * ba.x + ba.y * ba.y + ba.z * ba.z)
        let magBC = sqrt(bc.x * bc.x + bc.y * bc.y + bc.z * bc.z)

        guard magBA > 1e-6, magBC > 1e-6 else { return 0 }

        let cosAngle = max(-1, min(1, dot / (magBA * magBC)))
        return acos(cosAngle) * 180.0 / .pi
    }

    /// Compute all defined angles for a single frame.
    func computeAngles(for frame: PoseFrame) -> [String: JointAngle] {
        var angles: [String: JointAngle] = [:]

        for def in BodyJoint3D.commonAngles {
            guard let pA = frame.joints[def.proximal.rawValue],
                  let pV = frame.joints[def.vertex.rawValue],
                  let pD = frame.joints[def.distal.rawValue] else {
                continue
            }

            let minConf = min(pA.confidence, min(pV.confidence, pD.confidence))
            guard minConf >= minJointConfidence else { continue }

            let angle = angleBetween(pointA: pA, vertex: pV, pointC: pD)
            angles[def.name] = JointAngle(
                jointName: def.name,
                angleDegrees: angle,
                confidence: minConf
            )
        }

        return angles
    }

    /// Compute angles for all frames.
    private func computeAllFrameAngles(_ poses: [PoseFrame]) -> [[String: JointAngle]] {
        return poses.map { computeAngles(for: $0) }
    }

    // MARK: - Rep Detection

    /// Determine which angle to use for rep detection based on exercise properties.
    func determinePrimaryAngle(for exercise: RehabExercise) -> String {
        let target = exercise.targetArea.lowercased()
        let name = exercise.name.lowercased()

        // Match by exercise name first
        if name.contains("squat") || name.contains("lunge") {
            return "left_knee"
        }
        if name.contains("curl") && (name.contains("bicep") || name.contains("arm")) {
            return "left_elbow"
        }
        if name.contains("press") || name.contains("raise") || name.contains("fly") {
            return "left_shoulder"
        }
        if name.contains("deadlift") || name.contains("hinge") || name.contains("bridge") {
            return "left_hip"
        }

        // Fall back to target area
        if target.contains("quad") || target.contains("knee") || target.contains("leg") ||
            target.contains("calf") || target.contains("hamstring") {
            return "left_knee"
        }
        if target.contains("hip") || target.contains("glute") || target.contains("back") {
            return "left_hip"
        }
        if target.contains("bicep") || target.contains("tricep") || target.contains("forearm") {
            return "left_elbow"
        }
        if target.contains("shoulder") || target.contains("chest") || target.contains("delt") {
            return "left_shoulder"
        }

        // Default: knee (most common for rehab exercises)
        return "left_knee"
    }

    /// Detect repetitions using peak detection on the primary angle time series.
    /// Uses a state machine: idle → descending → at_bottom → ascending → idle.
    private func detectReps(
        frameAngles: [[String: JointAngle]],
        poses: [PoseFrame],
        primaryAngle: String
    ) -> [(startFrame: Int, endFrame: Int)] {
        // Extract primary angle time series
        let angleSeries: [(frame: Int, angle: Double, timestamp: Double)] = frameAngles.enumerated().compactMap { (i, angles) in
            guard let angle = angles[primaryAngle] else { return nil }
            return (i, angle.angleDegrees, poses[i].timestamp)
        }

        guard angleSeries.count >= 4 else { return [] }

        // Compute baseline range to set thresholds
        let allAngles = angleSeries.map { $0.angle }
        let minAngle = allAngles.min()!
        let maxAngle = allAngles.max()!
        let range = maxAngle - minAngle

        // Need at least 15° range to detect meaningful reps
        guard range >= 15 else { return [] }

        let threshold = range * 0.2  // 20% of range as hysteresis band
        let midpoint = (maxAngle + minAngle) / 2

        // State machine for rep detection
        enum RepState { case idle, descending, ascending }
        var state: RepState = .idle
        var reps: [(startFrame: Int, endFrame: Int)] = []
        var repStartFrame: Int = 0

        for entry in angleSeries {
            switch state {
            case .idle:
                if entry.angle < midpoint - threshold {
                    // Started descending
                    state = .descending
                    repStartFrame = entry.frame
                } else if entry.angle > midpoint + threshold {
                    // Started from high position
                    state = .ascending
                    repStartFrame = entry.frame
                }

            case .descending:
                if entry.angle > midpoint + threshold {
                    // Completed one full rep (down and back up)
                    reps.append((startFrame: repStartFrame, endFrame: entry.frame))
                    state = .idle
                }

            case .ascending:
                if entry.angle < midpoint - threshold {
                    // Completed one full rep (up and back down)
                    reps.append((startFrame: repStartFrame, endFrame: entry.frame))
                    state = .idle
                }
            }
        }

        return reps
    }

    // MARK: - Per-Rep Metrics

    private func computeRepMetrics(
        reps: [(startFrame: Int, endFrame: Int)],
        frameAngles: [[String: JointAngle]],
        poses: [PoseFrame]
    ) -> [RepMetrics] {
        return reps.enumerated().map { (index, rep) in
            let startTimestamp = poses[rep.startFrame].timestamp
            let endTimestamp = poses[rep.endFrame].timestamp
            let midFrame = (rep.startFrame + rep.endFrame) / 2

            var keyAngles: [String: RepMetrics.AngleRange] = [:]

            // Compute angle ranges for all tracked angles during this rep
            let anglesInRep = frameAngles[rep.startFrame...rep.endFrame]

            // Collect all angle names present in this rep
            let angleNames = Set(anglesInRep.flatMap { $0.keys })

            for angleName in angleNames {
                let values = anglesInRep.compactMap { $0[angleName]?.angleDegrees }
                guard !values.isEmpty else { continue }

                let minVal = values.min()!
                let maxVal = values.max()!
                let atStart = frameAngles[rep.startFrame][angleName]?.angleDegrees ?? 0
                let atMid = frameAngles[midFrame][angleName]?.angleDegrees ?? 0
                let atEnd = frameAngles[rep.endFrame][angleName]?.angleDegrees ?? 0

                keyAngles[angleName] = RepMetrics.AngleRange(
                    minDegrees: round(minVal * 10) / 10,
                    maxDegrees: round(maxVal * 10) / 10,
                    rangeOfMotion: round((maxVal - minVal) * 10) / 10,
                    atStart: round(atStart * 10) / 10,
                    atMid: round(atMid * 10) / 10,
                    atEnd: round(atEnd * 10) / 10
                )
            }

            return RepMetrics(
                repNumber: index + 1,
                keyAngles: keyAngles,
                durationSeconds: round((endTimestamp - startTimestamp) * 10) / 10,
                startTimestamp: startTimestamp,
                endTimestamp: endTimestamp
            )
        }
    }

    // MARK: - Symmetry Analysis

    private func computeSymmetry(frameAngles: [[String: JointAngle]]) -> FormAnalysisData.SymmetryData? {
        var leftAvgs: [String: (sum: Double, count: Int)] = [:]
        var rightAvgs: [String: (sum: Double, count: Int)] = [:]

        for angles in frameAngles {
            for (name, angle) in angles {
                if name.hasPrefix("left_") {
                    leftAvgs[name, default: (0, 0)].sum += angle.angleDegrees
                    leftAvgs[name, default: (0, 0)].count += 1
                } else if name.hasPrefix("right_") {
                    rightAvgs[name, default: (0, 0)].sum += angle.angleDegrees
                    rightAvgs[name, default: (0, 0)].count += 1
                }
            }
        }

        guard !leftAvgs.isEmpty, !rightAvgs.isEmpty else { return nil }

        let leftResults = leftAvgs.mapValues { round(($0.sum / Double($0.count)) * 10) / 10 }
        let rightResults = rightAvgs.mapValues { round(($0.sum / Double($0.count)) * 10) / 10 }

        // Compute differences for paired joints
        var differences: [String: Double] = [:]
        for (leftName, leftAvg) in leftResults {
            let baseName = String(leftName.dropFirst(5))  // Remove "left_"
            let rightName = "right_\(baseName)"
            if let rightAvg = rightResults[rightName] {
                differences[baseName] = round(abs(leftAvg - rightAvg) * 10) / 10
            }
        }

        return FormAnalysisData.SymmetryData(
            leftAvgAngles: leftResults,
            rightAvgAngles: rightResults,
            differencesDegrees: differences
        )
    }

    // MARK: - Alignment Checks

    private func checkAlignment(
        poses: [PoseFrame],
        reps: [(startFrame: Int, endFrame: Int)],
        exercise: RehabExercise
    ) -> [FormAnalysisData.AlignmentIssue] {
        var issues: [FormAnalysisData.AlignmentIssue] = []
        let totalReps = reps.count

        guard totalReps > 0 else { return issues }

        // Check: Shoulder alignment (shoulders should be level during most exercises)
        var shoulderMisalignedReps = 0
        for rep in reps {
            let midFrame = (rep.startFrame + rep.endFrame) / 2
            let frame = poses[midFrame]
            if let leftS = frame.joints[BodyJoint3D.leftShoulder.rawValue],
               let rightS = frame.joints[BodyJoint3D.rightShoulder.rawValue] {
                let heightDiff = abs(leftS.y - rightS.y)
                if heightDiff > 0.05 {  // > 5cm difference
                    shoulderMisalignedReps += 1
                }
            }
        }
        if shoulderMisalignedReps > 0 {
            issues.append(FormAnalysisData.AlignmentIssue(
                description: "Uneven shoulders detected",
                affectedReps: shoulderMisalignedReps,
                totalReps: totalReps
            ))
        }

        // Check: Hip alignment (hips should be level)
        var hipMisalignedReps = 0
        for rep in reps {
            let midFrame = (rep.startFrame + rep.endFrame) / 2
            let frame = poses[midFrame]
            if let leftH = frame.joints[BodyJoint3D.leftHip.rawValue],
               let rightH = frame.joints[BodyJoint3D.rightHip.rawValue] {
                let heightDiff = abs(leftH.y - rightH.y)
                if heightDiff > 0.04 {  // > 4cm difference
                    hipMisalignedReps += 1
                }
            }
        }
        if hipMisalignedReps > 0 {
            issues.append(FormAnalysisData.AlignmentIssue(
                description: "Uneven hips detected",
                affectedReps: hipMisalignedReps,
                totalReps: totalReps
            ))
        }

        // Check: Trunk lean (excessive forward lean during lower body exercises)
        let target = exercise.targetArea.lowercased()
        if target.contains("quad") || target.contains("glute") || target.contains("leg") ||
            target.contains("knee") || target.contains("hip") {
            var excessiveLeanReps = 0
            for rep in reps {
                let midFrame = (rep.startFrame + rep.endFrame) / 2
                let frame = poses[midFrame]
                if let shoulder = frame.joints[BodyJoint3D.leftShoulder.rawValue],
                   let hip = frame.joints[BodyJoint3D.leftHip.rawValue] {
                    // Check if shoulders are significantly forward of hips (Z axis)
                    let forwardLean = shoulder.z - hip.z
                    if abs(forwardLean) > 0.15 {  // > 15cm forward
                        excessiveLeanReps += 1
                    }
                }
            }
            if excessiveLeanReps > 0 {
                issues.append(FormAnalysisData.AlignmentIssue(
                    description: "Excessive trunk lean detected",
                    affectedReps: excessiveLeanReps,
                    totalReps: totalReps
                ))
            }
        }

        return issues
    }

    // MARK: - Tempo

    private func computeTempo(repMetrics: [RepMetrics]) -> (average: Double?, standardDeviation: Double?) {
        guard repMetrics.count >= 2 else {
            return (repMetrics.first?.durationSeconds, nil)
        }

        let durations = repMetrics.map { $0.durationSeconds }
        let avg = durations.reduce(0, +) / Double(durations.count)
        let variance = durations.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(durations.count)
        let sd = sqrt(variance)

        return (round(avg * 10) / 10, round(sd * 10) / 10)
    }

    // MARK: - Helpers

    private func emptyResult(exercise: RehabExercise, fps: Double, duration: Double) -> FormAnalysisData {
        FormAnalysisData(
            exerciseName: exercise.name,
            exerciseCategory: exercise.exerciseCategory,
            targetArea: exercise.targetArea,
            totalFramesProcessed: 0,
            videoFPS: fps,
            videoDurationSeconds: duration,
            detectedRepCount: 0,
            repMetrics: [],
            symmetry: nil,
            alignment: [],
            averageTempo: nil,
            tempoVariability: nil,
            bodyHeight: nil
        )
    }
}
