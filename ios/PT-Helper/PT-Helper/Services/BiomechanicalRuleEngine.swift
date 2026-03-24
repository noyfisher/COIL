import Foundation

// MARK: - Biomechanical Rule Engine

/// Deterministic exercise-specific rule checks based on biomechanics literature.
/// The form-analysis equivalent of KnowledgeGraphService — no AI involved.
class BiomechanicalRuleEngine {
    static let shared = BiomechanicalRuleEngine()

    private init() {}

    // MARK: - Exercise Form Rules

    /// Get form rules for an exercise based on name pattern matching.
    func rules(for exercise: RehabExercise) -> ExerciseFormRules {
        let name = exercise.name.lowercased()
        let target = exercise.targetArea.lowercased()

        // Match by exercise name first, then fall back to target area
        if name.contains("squat") {
            return squatRules
        }
        if name.contains("lunge") {
            return lungeRules
        }
        if name.contains("curl") && (name.contains("bicep") || name.contains("arm") || target.contains("bicep")) {
            return bicepCurlRules
        }
        if name.contains("deadlift") || name.contains("hinge") {
            return hipHingeRules
        }
        if name.contains("bridge") {
            return bridgeRules
        }
        if name.contains("press") || name.contains("raise") {
            return shoulderPressRules
        }
        if name.contains("plank") || name.contains("hold") {
            return staticHoldRules
        }

        // Fall back to target area
        if target.contains("quad") || target.contains("knee") || target.contains("leg") {
            return genericLowerBodyRules
        }
        if target.contains("hip") || target.contains("glute") {
            return bridgeRules
        }
        if target.contains("shoulder") || target.contains("chest") {
            return shoulderPressRules
        }
        if target.contains("bicep") || target.contains("tricep") || target.contains("arm") {
            return bicepCurlRules
        }

        return genericRules
    }

    /// Run all rules for an exercise against the computed metrics.
    func check(
        metrics: FormAnalysisData,
        exercise: RehabExercise
    ) -> [RuleCheckResult] {
        let exerciseRules = rules(for: exercise)
        var results: [RuleCheckResult] = []

        // Check angle ranges
        for (jointName, expectedRange) in exerciseRules.expectedAngleRanges {
            let result = checkAngleRange(
                jointName: jointName,
                expectedRange: expectedRange,
                metrics: metrics
            )
            results.append(RuleCheckResult(ruleName: "\(jointName)_range", result: result))
        }

        // Check safety constraints
        for constraint in exerciseRules.safetyConstraints {
            let result = constraint.check(metrics)
            results.append(RuleCheckResult(ruleName: constraint.name, result: result))
        }

        return results
    }

    /// Get the exercise-specific rep detection threshold (minimum ROM in degrees).
    func repDetectionThreshold(for exercise: RehabExercise) -> Double {
        rules(for: exercise).minimumRepROM
    }

    /// Get exercise-specific alignment thresholds.
    func alignmentThresholds(for exercise: RehabExercise) -> AlignmentThresholds {
        rules(for: exercise).alignmentThresholds
    }

    // MARK: - Angle Range Checking

    private func checkAngleRange(
        jointName: String,
        expectedRange: ClosedRange<Double>,
        metrics: FormAnalysisData
    ) -> SafetyCheckResult {
        // Check across all reps
        let angles = metrics.repMetrics.compactMap { $0.keyAngles[jointName] }
        guard !angles.isEmpty else { return .pass }

        let minObserved = angles.map { $0.minDegrees }.min() ?? 0
        let maxObserved = angles.map { $0.maxDegrees }.max() ?? 0

        // Check if observed range exceeds safety limits
        if minObserved < expectedRange.lowerBound - 20 {
            return .danger("Excessive range of motion at \(jointName): \(Int(minObserved))° (safe lower limit: \(Int(expectedRange.lowerBound))°)")
        }
        if minObserved < expectedRange.lowerBound - 10 {
            return .caution("Deep range at \(jointName): \(Int(minObserved))° is below the typical \(Int(expectedRange.lowerBound))° threshold")
        }
        if maxObserved > expectedRange.upperBound + 10 {
            return .caution("Limited range at \(jointName): not reaching full extension (\(Int(maxObserved))° vs expected \(Int(expectedRange.upperBound))°)")
        }

        return .pass
    }

    // MARK: - Exercise Rule Sets

    private var squatRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_knee": 86...170,
                "right_knee": 86...170,
                "trunk": 140...180,
                "left_hip": 60...170,
                "right_hip": 60...170,
            ],
            safetyConstraints: [
                SafetyConstraint(name: "squat_knee_symmetry") { metrics in
                    guard let sym = metrics.symmetry?.differencesDegrees["knee"], sym > 12 else { return .pass }
                    return .caution("Significant knee asymmetry detected (\(Int(sym))°). This may indicate a strength imbalance.")
                },
                SafetyConstraint(name: "squat_depth_consistency") { metrics in
                    let kneeROMs = metrics.repMetrics.compactMap { $0.keyAngles["left_knee"]?.rangeOfMotion }
                    guard kneeROMs.count >= 2 else { return .pass }
                    let avg = kneeROMs.reduce(0, +) / Double(kneeROMs.count)
                    let maxDeviation = kneeROMs.map { abs($0 - avg) }.max() ?? 0
                    if maxDeviation > 20 {
                        return .caution("Squat depth varies significantly between reps (±\(Int(maxDeviation))°). Aim for consistent depth.")
                    }
                    return .pass
                },
            ],
            minimumRepROM: 15,
            alignmentThresholds: AlignmentThresholds(
                shoulderLevelMeters: 0.05,
                hipLevelMeters: 0.04,
                trunkLeanMeters: 0.15
            )
        )
    }

    private var lungeRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_knee": 80...175,
                "right_knee": 80...175,
                "trunk": 150...180,
            ],
            safetyConstraints: [
                SafetyConstraint(name: "lunge_knee_asymmetry") { metrics in
                    guard let sym = metrics.symmetry?.differencesDegrees["knee"], sym > 20 else { return .pass }
                    return .caution("Large knee angle asymmetry during lunge (\(Int(sym))°). Check stance width and balance.")
                },
            ],
            minimumRepROM: 15,
            alignmentThresholds: .default
        )
    }

    private var bicepCurlRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_elbow": 30...170,
                "right_elbow": 30...170,
            ],
            safetyConstraints: [
                SafetyConstraint(name: "curl_shoulder_compensation") { metrics in
                    // If shoulder ROM > 20° during a curl, user may be swinging
                    let shoulderROMs = metrics.repMetrics.compactMap { $0.keyAngles["left_shoulder"]?.rangeOfMotion }
                    let avgShoulderROM = shoulderROMs.isEmpty ? 0 : shoulderROMs.reduce(0, +) / Double(shoulderROMs.count)
                    if avgShoulderROM > 20 {
                        return .caution("Shoulder movement detected during curls (avg \(Int(avgShoulderROM))° ROM). This suggests momentum is being used.")
                    }
                    return .pass
                },
            ],
            minimumRepROM: 20,
            alignmentThresholds: AlignmentThresholds(
                shoulderLevelMeters: 0.06,
                hipLevelMeters: 0.05,
                trunkLeanMeters: 0.20  // more lenient for upper body exercises
            )
        )
    }

    private var hipHingeRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_hip": 70...170,
                "right_hip": 70...170,
                "trunk": 100...180,
            ],
            safetyConstraints: [
                SafetyConstraint(name: "hinge_trunk_angle") { metrics in
                    let trunkAngles = metrics.repMetrics.compactMap { $0.keyAngles["trunk"]?.minDegrees }
                    let minTrunk = trunkAngles.min() ?? 180
                    if minTrunk < 90 {
                        return .danger("Excessive forward bend detected (trunk angle: \(Int(minTrunk))°). This may stress the lower back.")
                    }
                    if minTrunk < 110 {
                        return .caution("Deep forward bend (trunk: \(Int(minTrunk))°). Ensure neutral spine is maintained.")
                    }
                    return .pass
                },
            ],
            minimumRepROM: 15,
            alignmentThresholds: .default
        )
    }

    private var bridgeRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_hip": 90...180,
                "right_hip": 90...180,
                "left_knee": 70...110,
                "right_knee": 70...110,
            ],
            safetyConstraints: [
                SafetyConstraint(name: "bridge_knee_symmetry") { metrics in
                    guard let sym = metrics.symmetry?.differencesDegrees["knee"], sym > 8 else { return .pass }
                    return .caution("Knee angle asymmetry during bridge (\(Int(sym))°). Keep both knees aligned.")
                },
            ],
            minimumRepROM: 12,
            alignmentThresholds: .default
        )
    }

    private var shoulderPressRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_shoulder": 30...180,
                "right_shoulder": 30...180,
                "left_elbow": 30...180,
                "right_elbow": 30...180,
            ],
            safetyConstraints: [
                SafetyConstraint(name: "press_shoulder_symmetry") { metrics in
                    guard let sym = metrics.symmetry?.differencesDegrees["shoulder"], sym > 15 else { return .pass }
                    return .caution("Significant shoulder asymmetry during press (\(Int(sym))°). One side may be compensating.")
                },
            ],
            minimumRepROM: 15,
            alignmentThresholds: .default
        )
    }

    private var staticHoldRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [:],
            safetyConstraints: [],
            minimumRepROM: 5,  // very low — static holds have minimal ROM
            alignmentThresholds: AlignmentThresholds(
                shoulderLevelMeters: 0.04,
                hipLevelMeters: 0.03,
                trunkLeanMeters: 0.10  // tighter for planks
            )
        )
    }

    private var genericLowerBodyRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [
                "left_knee": 60...175,
                "right_knee": 60...175,
            ],
            safetyConstraints: [],
            minimumRepROM: 12,
            alignmentThresholds: .default
        )
    }

    private var genericRules: ExerciseFormRules {
        ExerciseFormRules(
            expectedAngleRanges: [:],
            safetyConstraints: [],
            minimumRepROM: 10,
            alignmentThresholds: .default
        )
    }
}

// MARK: - Supporting Types

/// Exercise-specific form rules including expected angles and safety constraints.
struct ExerciseFormRules {
    let expectedAngleRanges: [String: ClosedRange<Double>]
    let safetyConstraints: [SafetyConstraint]
    let minimumRepROM: Double
    let alignmentThresholds: AlignmentThresholds
}

/// A named safety constraint that checks form metrics deterministically.
struct SafetyConstraint {
    let name: String
    let check: (FormAnalysisData) -> SafetyCheckResult
}

/// Exercise-specific thresholds for alignment checks in PoseAnalysisEngine.
struct AlignmentThresholds {
    let shoulderLevelMeters: Double
    let hipLevelMeters: Double
    let trunkLeanMeters: Double

    static let `default` = AlignmentThresholds(
        shoulderLevelMeters: 0.05,
        hipLevelMeters: 0.04,
        trunkLeanMeters: 0.15
    )
}
