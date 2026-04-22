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

        // Step 3: Determine primary angle for rep detection (selects better-tracked side)
        let primaryAngleName = determinePrimaryAngle(for: exercise, poses: smoothedPoses)

        // Step 4: Detect reps
        let reps = detectReps(frameAngles: frameAngles, poses: smoothedPoses, primaryAngle: primaryAngleName)

        // Step 5: Compute per-rep metrics
        let repMetrics = computeRepMetrics(reps: reps, frameAngles: frameAngles, poses: smoothedPoses)

        // Step 6: Compute symmetry (global + per-rep phase)
        let symmetry = computeSymmetry(frameAngles: frameAngles)
        let perRepSymmetry = computePerRepSymmetry(reps: reps, frameAngles: frameAngles)

        // Step 7: Check alignment (multi-phase)
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
            perRepSymmetry: perRepSymmetry,
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

    /// Determine the base joint name for rep detection based on exercise properties.
    /// Returns a base name like "knee", "elbow", "hip", "shoulder" (without left/right prefix).
    func determinePrimaryJoint(for exercise: RehabExercise) -> String {
        let target = exercise.targetArea.lowercased()
        let name = exercise.name.lowercased()

        // Match by exercise name first
        if name.contains("squat") || name.contains("lunge") { return "knee" }
        if name.contains("curl") && (name.contains("bicep") || name.contains("arm")) { return "elbow" }
        if name.contains("press") || name.contains("raise") || name.contains("fly") { return "shoulder" }
        if name.contains("deadlift") || name.contains("hinge") || name.contains("bridge") { return "hip" }

        // Fall back to target area
        if target.contains("quad") || target.contains("knee") || target.contains("leg") ||
            target.contains("calf") || target.contains("hamstring") { return "knee" }
        if target.contains("hip") || target.contains("glute") || target.contains("back") { return "hip" }
        if target.contains("bicep") || target.contains("tricep") || target.contains("forearm") { return "elbow" }
        if target.contains("shoulder") || target.contains("chest") || target.contains("delt") { return "shoulder" }

        return "knee"
    }

    /// Determine the primary angle for rep detection, selecting the better-tracked side.
    /// Evaluates both left and right angles across all frames and picks the side with
    /// more valid data (higher average confidence, more frames with the joint visible).
    func determinePrimaryAngle(for exercise: RehabExercise, poses: [PoseFrame] = []) -> String {
        let baseJoint = determinePrimaryJoint(for: exercise)

        guard !poses.isEmpty else {
            // No pose data yet — fall back to left (legacy behavior)
            return "left_\(baseJoint)"
        }

        let leftName = "left_\(baseJoint)"
        let rightName = "right_\(baseJoint)"

        // Find the angle definitions for both sides
        let leftDef = BodyJoint3D.commonAngles.first { $0.name == leftName }
        let rightDef = BodyJoint3D.commonAngles.first { $0.name == rightName }

        guard let leftDef = leftDef, let rightDef = rightDef else {
            return leftName
        }

        // Score each side: frames where all 3 joints are present × average confidence
        let leftScore = sideScore(poses: poses, proximal: leftDef.proximal, vertex: leftDef.vertex, distal: leftDef.distal)
        let rightScore = sideScore(poses: poses, proximal: rightDef.proximal, vertex: rightDef.vertex, distal: rightDef.distal)

        return rightScore > leftScore ? rightName : leftName
    }

    /// Compute a quality score for one side's angle joints across all frames.
    private func sideScore(
        poses: [PoseFrame],
        proximal: BodyJoint3D,
        vertex: BodyJoint3D,
        distal: BodyJoint3D
    ) -> Double {
        var totalConfidence = 0.0
        var validFrames = 0

        for frame in poses {
            guard let pA = frame.joints[proximal.rawValue],
                  let pV = frame.joints[vertex.rawValue],
                  let pD = frame.joints[distal.rawValue] else { continue }
            validFrames += 1
            totalConfidence += min(pA.confidence, min(pV.confidence, pD.confidence))
        }

        guard validFrames > 0 else { return 0 }
        let coverage = Double(validFrames) / Double(poses.count)
        let avgConfidence = totalConfidence / Double(validFrames)
        return coverage * avgConfidence
    }

    /// Detect repetitions using peak detection on the primary angle time series.
    /// Uses robust statistics (median/IQR) for thresholds and filters by duration.
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

        // Use robust statistics (percentiles) instead of min/max to resist outliers
        let allAngles = angleSeries.map { $0.angle }.sorted()
        let p10 = allAngles[max(0, allAngles.count / 10)]
        let p90 = allAngles[min(allAngles.count - 1, allAngles.count * 9 / 10)]
        let robustRange = p90 - p10

        // Need at least 15° robust range to detect meaningful reps
        guard robustRange >= 15 else { return [] }

        let threshold = robustRange * 0.2  // 20% of robust range as hysteresis band
        let midpoint = (p10 + p90) / 2

        // State machine for rep detection
        enum RepState { case idle, descending, ascending }
        var state: RepState = .idle
        var rawReps: [(startFrame: Int, endFrame: Int)] = []
        var repStartFrame: Int = 0

        for entry in angleSeries {
            switch state {
            case .idle:
                if entry.angle < midpoint - threshold {
                    state = .descending
                    repStartFrame = entry.frame
                } else if entry.angle > midpoint + threshold {
                    state = .ascending
                    repStartFrame = entry.frame
                }

            case .descending:
                if entry.angle > midpoint + threshold {
                    rawReps.append((startFrame: repStartFrame, endFrame: entry.frame))
                    state = .idle
                }

            case .ascending:
                if entry.angle < midpoint - threshold {
                    rawReps.append((startFrame: repStartFrame, endFrame: entry.frame))
                    state = .idle
                }
            }
        }

        // Filter by duration: reject reps shorter than 0.5s or longer than 10s
        let durationFiltered = rawReps.filter { rep in
            let startTime = poses[rep.startFrame].timestamp
            let endTime = poses[rep.endFrame].timestamp
            let duration = endTime - startTime
            return duration >= 0.5 && duration <= 10.0
        }

        // Filter by quality: reject reps with ROM >2σ from mean (likely artifacts)
        guard durationFiltered.count >= 3 else { return durationFiltered }

        let repROMs = durationFiltered.map { rep -> Double in
            let repAngles = frameAngles[rep.startFrame...rep.endFrame]
                .compactMap { $0[primaryAngle]?.angleDegrees }
            guard let minA = repAngles.min(), let maxA = repAngles.max() else { return 0 }
            return maxA - minA
        }
        let meanROM = repROMs.reduce(0, +) / Double(repROMs.count)
        let romVariance = repROMs.map { ($0 - meanROM) * ($0 - meanROM) }.reduce(0, +) / Double(repROMs.count)
        let romSD = sqrt(romVariance)

        let qualityFiltered = durationFiltered.enumerated().filter { (idx, _) in
            abs(repROMs[idx] - meanROM) <= 2.0 * romSD
        }.map { $0.element }

        return qualityFiltered
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

    // MARK: - Per-Rep Phase Symmetry

    /// Compute left/right symmetry at specific phases (min, mid, max angle) within each rep.
    private func computePerRepSymmetry(
        reps: [(startFrame: Int, endFrame: Int)],
        frameAngles: [[String: JointAngle]]
    ) -> [RepSymmetryData]? {
        guard !reps.isEmpty else { return nil }

        let symmetryPairs = BodyJoint3D.symmetryPairs
        var results: [RepSymmetryData] = []

        for (repIndex, rep) in reps.enumerated() {
            let repAngles = frameAngles[rep.startFrame...rep.endFrame]
            let midFrame = (rep.startFrame + rep.endFrame) / 2

            var atMin: [String: Double] = [:]
            var atMid: [String: Double] = [:]
            var atMax: [String: Double] = [:]

            for pair in symmetryPairs {
                let leftName = "left_\(String(pair.left.rawValue.dropFirst(4)))"  // leftShoulder → left_shoulder
                let rightName = "right_\(String(pair.right.rawValue.dropFirst(5)))"  // rightShoulder → right_shoulder

                // Get the angle name from commonAngles
                let leftAngleName = BodyJoint3D.commonAngles.first { $0.name.hasPrefix("left_") && $0.vertex == pair.left }?.name
                let rightAngleName = BodyJoint3D.commonAngles.first { $0.name.hasPrefix("right_") && $0.vertex == pair.right }?.name

                guard let leftAngleName = leftAngleName, let rightAngleName = rightAngleName else { continue }

                // Find frames where both angles exist
                let leftValues = repAngles.compactMap { $0[leftAngleName]?.angleDegrees }
                let rightValues = repAngles.compactMap { $0[rightAngleName]?.angleDegrees }
                guard !leftValues.isEmpty, !rightValues.isEmpty else { continue }

                let baseName = String(leftAngleName.dropFirst(5))  // "left_knee" → "knee"

                // At min (bottom of movement)
                if let leftMin = leftValues.min(), let rightMin = rightValues.min() {
                    atMin[baseName] = round(abs(leftMin - rightMin) * 10) / 10
                }

                // At mid
                if let leftMidAngle = frameAngles[midFrame][leftAngleName]?.angleDegrees,
                   let rightMidAngle = frameAngles[midFrame][rightAngleName]?.angleDegrees {
                    atMid[baseName] = round(abs(leftMidAngle - rightMidAngle) * 10) / 10
                }

                // At max (top of movement)
                if let leftMax = leftValues.max(), let rightMax = rightValues.max() {
                    atMax[baseName] = round(abs(leftMax - rightMax) * 10) / 10
                }
            }

            results.append(RepSymmetryData(
                repNumber: repIndex + 1,
                atMinAngle: atMin,
                atMidAngle: atMid,
                atMaxAngle: atMax
            ))
        }

        return results.isEmpty ? nil : results
    }

    // MARK: - Alignment Checks

    /// Check alignment at multiple phases within each rep (start, 25%, mid, 75%, end).
    /// Reports the worst alignment values found across all phases.
    private func checkAlignment(
        poses: [PoseFrame],
        reps: [(startFrame: Int, endFrame: Int)],
        exercise: RehabExercise
    ) -> [FormAnalysisData.AlignmentIssue] {
        var issues: [FormAnalysisData.AlignmentIssue] = []
        let totalReps = reps.count

        guard totalReps > 0 else { return issues }

        // Sample frames at 5 phases per rep
        func phaseFrames(for rep: (startFrame: Int, endFrame: Int)) -> [Int] {
            let range = rep.endFrame - rep.startFrame
            guard range > 0 else { return [rep.startFrame] }
            return [0.0, 0.25, 0.5, 0.75, 1.0].map { phase in
                min(rep.startFrame + Int(Double(range) * phase), rep.endFrame)
            }
        }

        // Check: Shoulder alignment across all phases
        var shoulderMisalignedReps = 0
        for rep in reps {
            let hasIssue = phaseFrames(for: rep).contains { frameIdx in
                guard frameIdx < poses.count,
                      let leftS = poses[frameIdx].joints[BodyJoint3D.leftShoulder.rawValue],
                      let rightS = poses[frameIdx].joints[BodyJoint3D.rightShoulder.rawValue] else { return false }
                return abs(leftS.y - rightS.y) > 0.05
            }
            if hasIssue { shoulderMisalignedReps += 1 }
        }
        if shoulderMisalignedReps > 0 {
            issues.append(FormAnalysisData.AlignmentIssue(
                description: "Uneven shoulders detected",
                affectedReps: shoulderMisalignedReps,
                totalReps: totalReps
            ))
        }

        // Check: Hip alignment across all phases
        var hipMisalignedReps = 0
        for rep in reps {
            let hasIssue = phaseFrames(for: rep).contains { frameIdx in
                guard frameIdx < poses.count,
                      let leftH = poses[frameIdx].joints[BodyJoint3D.leftHip.rawValue],
                      let rightH = poses[frameIdx].joints[BodyJoint3D.rightHip.rawValue] else { return false }
                return abs(leftH.y - rightH.y) > 0.04
            }
            if hasIssue { hipMisalignedReps += 1 }
        }
        if hipMisalignedReps > 0 {
            issues.append(FormAnalysisData.AlignmentIssue(
                description: "Uneven hips detected",
                affectedReps: hipMisalignedReps,
                totalReps: totalReps
            ))
        }

        // Check: Trunk lean across all phases (lower body exercises)
        let target = exercise.targetArea.lowercased()
        if target.contains("quad") || target.contains("glute") || target.contains("leg") ||
            target.contains("knee") || target.contains("hip") {
            var excessiveLeanReps = 0
            for rep in reps {
                let hasIssue = phaseFrames(for: rep).contains { frameIdx in
                    guard frameIdx < poses.count,
                          let shoulder = poses[frameIdx].joints[BodyJoint3D.leftShoulder.rawValue],
                          let hip = poses[frameIdx].joints[BodyJoint3D.leftHip.rawValue] else { return false }
                    return abs(shoulder.z - hip.z) > 0.15
                }
                if hasIssue { excessiveLeanReps += 1 }
            }
            if excessiveLeanReps > 0 {
                issues.append(FormAnalysisData.AlignmentIssue(
                    description: "Excessive trunk lean detected",
                    affectedReps: excessiveLeanReps,
                    totalReps: totalReps
                ))
            }
        }

        // Check: Alignment degradation across reps (fatigue indicator)
        if reps.count >= 3 {
            let firstHalfReps = Array(reps.prefix(reps.count / 2))
            let secondHalfReps = Array(reps.suffix(reps.count / 2))

            let firstHalfLean = averageTrunkLean(reps: firstHalfReps, poses: poses)
            let secondHalfLean = averageTrunkLean(reps: secondHalfReps, poses: poses)

            if let first = firstHalfLean, let second = secondHalfLean,
               second > first + 0.03 {  // 3cm degradation
                issues.append(FormAnalysisData.AlignmentIssue(
                    description: "Form degradation detected — alignment worsened in later reps (possible fatigue)",
                    affectedReps: secondHalfReps.count,
                    totalReps: totalReps
                ))
            }
        }

        return issues
    }

    /// Compute average trunk lean magnitude across reps.
    private func averageTrunkLean(
        reps: [(startFrame: Int, endFrame: Int)],
        poses: [PoseFrame]
    ) -> Double? {
        let leans: [Double] = reps.compactMap { rep in
            let midFrame = min((rep.startFrame + rep.endFrame) / 2, poses.count - 1)
            guard let shoulder = poses[midFrame].joints[BodyJoint3D.leftShoulder.rawValue],
                  let hip = poses[midFrame].joints[BodyJoint3D.leftHip.rawValue] else { return nil }
            return abs(shoulder.z - hip.z)
        }
        guard !leans.isEmpty else { return nil }
        return leans.reduce(0, +) / Double(leans.count)
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
            perRepSymmetry: nil,
            alignment: [],
            averageTempo: nil,
            tempoVariability: nil,
            bodyHeight: nil
        )
    }
}
