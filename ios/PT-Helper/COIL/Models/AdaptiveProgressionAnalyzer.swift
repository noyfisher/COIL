import Foundation

// MARK: - Data Types

/// The analyzed metrics from a set of workout sessions for one plan.
struct ProgressionAnalysis {
    let planId: UUID
    let sessionCount: Int
    let completionRate: Double           // 0.0–1.0 average fraction of plan exercises completed
    let averagePain: Double              // 0–10
    let painTrend: PainTrend
    let painTrendMagnitude: Double       // absolute change in average pain
    let averageDaysBetweenSessions: Double
    let consistencyScore: Double         // 0.0–1.0 regularity of workouts
}

enum PainTrend: String {
    case improving   // pain going down
    case stable      // pain within tolerance
    case worsening   // pain going up
}

/// A progression recommendation produced by the analyzer.
struct ProgressionRecommendation {
    let action: ProgressionAction
    let reason: String
    let detailPoints: [String]
    let confidence: RecommendationConfidence
    let analysis: ProgressionAnalysis
}

enum ProgressionAction: String {
    case advance
    case maintain
    case scaleBack
    case insufficientData
}

enum RecommendationConfidence: String {
    case high
    case moderate
    case low
}

// MARK: - Analyzer

/// Deterministic analysis of workout session data to produce plan progression recommendations.
/// Matches `ProgressionRule` pattern: stateless enum with pure static functions.
enum AdaptiveProgressionAnalyzer {

    // MARK: - Thresholds

    /// Minimum number of sessions linked to a plan before making a recommendation.
    static let minimumSessionCount = 3

    /// Number of recent sessions to compare against earliest for trend analysis.
    static let trendWindowSize = 3

    /// Pain must change by at least this to register as improving/worsening.
    static let painTrendThreshold: Double = 0.5

    /// Completion rate above this is considered "high".
    static let highCompletionThreshold: Double = 0.80

    /// Completion rate below this is considered "low".
    static let lowCompletionThreshold: Double = 0.50

    /// Pain level above which we consider the user is in too much pain to advance.
    static let highPainThreshold: Double = 6.0

    /// Pain level below which we consider pain well-managed.
    static let lowPainThreshold: Double = 3.0

    // MARK: - Public API

    /// Analyze workout sessions for a given plan and return a recommendation.
    static func analyze(
        sessions: [WorkoutSession],
        plan: RehabPlan
    ) -> ProgressionRecommendation {
        let planSessions = sessions
            .filter { $0.planId == plan.id }
            .sorted { $0.date < $1.date }

        guard planSessions.count >= minimumSessionCount else {
            return ProgressionRecommendation(
                action: .insufficientData,
                reason: "Complete at least \(minimumSessionCount) workouts before adjustments are suggested.",
                detailPoints: [
                    "\(planSessions.count) of \(minimumSessionCount) sessions completed",
                    "Keep going \u{2014} your data is building up"
                ],
                confidence: .low,
                analysis: makeAnalysis(planId: plan.id, sessions: planSessions, plan: plan)
            )
        }

        let analysis = makeAnalysis(planId: plan.id, sessions: planSessions, plan: plan)
        return decide(from: analysis)
    }

    /// Generate a brief post-workout insight (one-liner about trajectory).
    /// Returns nil if there isn't enough data or nothing remarkable to report.
    static func postWorkoutInsight(
        sessions: [WorkoutSession],
        plan: RehabPlan,
        latestSession: WorkoutSession
    ) -> String? {
        let planSessions = sessions
            .filter { $0.planId == plan.id }
            .sorted { $0.date < $1.date }

        guard planSessions.count >= 2 else { return nil }

        let previousAvg = planSessions.dropLast().suffix(3).map(\.painLevel).mean
        let current = latestSession.painLevel
        let delta = current - previousAvg

        if delta <= -1.0 {
            return "Your pain is trending down. Great progress!"
        } else if delta >= 1.5 {
            return "Pain was higher this session. Consider taking it easier next time."
        } else {
            let completionRate = Double(latestSession.exercisesPerformed.count) /
                Double(max(plan.exercises.count, 1))
            if completionRate >= 0.9 {
                return "Full workout completed. You're building consistency!"
            }
            return nil
        }
    }

    // MARK: - Analysis Construction

    static func makeAnalysis(
        planId: UUID,
        sessions: [WorkoutSession],
        plan: RehabPlan
    ) -> ProgressionAnalysis {
        let painValues = sessions.map(\.painLevel)
        let avgPain = painValues.mean

        // Pain trend: compare first N sessions vs last N sessions
        let windowSize = max(min(trendWindowSize, sessions.count / 2), 1)
        let (trend, magnitude) = calculatePainTrend(
            early: Array(sessions.prefix(windowSize)),
            recent: Array(sessions.suffix(windowSize))
        )

        // Completion rate: per session, fraction of plan exercises performed
        let totalPlanExercises = plan.exercises.count
        let perSessionCompletion: [Double] = sessions.map { session in
            guard totalPlanExercises > 0 else { return 1.0 }
            return Double(session.exercisesPerformed.count) / Double(totalPlanExercises)
        }
        let avgCompletion = perSessionCompletion.mean

        // Session consistency: average days between sessions
        let daysBetween = calculateDaysBetween(sessions: sessions)

        // Consistency score: highest (1.0) at ~2.5-day gap, drops for wider gaps
        let consistency: Double
        if sessions.count < 2 {
            consistency = 0.5
        } else {
            let idealGap = 2.5
            let deviation = abs(daysBetween - idealGap)
            consistency = max(0, 1.0 - (deviation / 7.0))
        }

        return ProgressionAnalysis(
            planId: planId,
            sessionCount: sessions.count,
            completionRate: min(avgCompletion, 1.0),
            averagePain: avgPain,
            painTrend: trend,
            painTrendMagnitude: magnitude,
            averageDaysBetweenSessions: daysBetween,
            consistencyScore: consistency
        )
    }

    // MARK: - Decision Matrix

    static func decide(from analysis: ProgressionAnalysis) -> ProgressionRecommendation {
        let pain = analysis.painTrend
        let completion = analysis.completionRate
        let avgPain = analysis.averagePain

        // RULE 1: High pain always triggers scale-back (unless actively improving)
        if avgPain >= highPainThreshold && pain != .improving {
            return ProgressionRecommendation(
                action: .scaleBack,
                reason: "Your pain levels are high. Scaling back will help recovery.",
                detailPoints: [
                    "Average pain: \(String(format: "%.1f", avgPain))/10",
                    "Consider reducing intensity to allow healing",
                    "Pain trend: \(pain.rawValue)"
                ],
                confidence: .high,
                analysis: analysis
            )
        }

        // RULE 2: Pain worsening significantly
        if pain == .worsening && analysis.painTrendMagnitude >= 2.0 {
            return ProgressionRecommendation(
                action: .scaleBack,
                reason: "Pain has increased significantly over recent sessions.",
                detailPoints: [
                    "Pain increased by \(String(format: "%.1f", analysis.painTrendMagnitude)) points",
                    "Reducing volume to help recovery",
                    "Sessions completed: \(analysis.sessionCount)"
                ],
                confidence: .high,
                analysis: analysis
            )
        }

        // RULE 3: Pain worsening slightly
        if pain == .worsening {
            return ProgressionRecommendation(
                action: .maintain,
                reason: "Pain has slightly increased. Maintaining current level.",
                detailPoints: [
                    "Small pain increase detected",
                    "Holding steady before adjusting",
                    "Continue monitoring how you feel"
                ],
                confidence: .moderate,
                analysis: analysis
            )
        }

        // RULE 4 & 5: Pain improving + high completion
        if pain == .improving && completion >= highCompletionThreshold {
            if avgPain <= lowPainThreshold {
                return ProgressionRecommendation(
                    action: .advance,
                    reason: "Pain is improving and you're completing exercises well. Ready to progress!",
                    detailPoints: [
                        "Pain decreased by \(String(format: "%.1f", analysis.painTrendMagnitude)) points",
                        "Completion rate: \(Int(completion * 100))%",
                        "Average pain: \(String(format: "%.1f", avgPain))/10"
                    ],
                    confidence: .high,
                    analysis: analysis
                )
            } else {
                return ProgressionRecommendation(
                    action: .advance,
                    reason: "Good progress on pain and completion. Time to challenge yourself a bit more.",
                    detailPoints: [
                        "Pain trending down",
                        "Completion rate: \(Int(completion * 100))%",
                        "Moderate pain still present \u{2014} advancing conservatively"
                    ],
                    confidence: .moderate,
                    analysis: analysis
                )
            }
        }

        // RULE 6: Stable low pain + high completion
        if pain == .stable && completion >= highCompletionThreshold && avgPain <= lowPainThreshold {
            return ProgressionRecommendation(
                action: .advance,
                reason: "You're consistently completing workouts with low pain. Ready for the next level.",
                detailPoints: [
                    "Completion rate: \(Int(completion * 100))%",
                    "Pain stable at \(String(format: "%.1f", avgPain))/10",
                    "Good foundation for progression"
                ],
                confidence: .moderate,
                analysis: analysis
            )
        }

        // RULE 7: Low completion rate
        if completion < lowCompletionThreshold {
            return ProgressionRecommendation(
                action: .scaleBack,
                reason: "Completion rate is low. The current plan may be too demanding.",
                detailPoints: [
                    "Only \(Int(completion * 100))% of exercises completed on average",
                    "Reducing volume to improve adherence",
                    "Consistency matters more than intensity"
                ],
                confidence: .moderate,
                analysis: analysis
            )
        }

        // RULE 8: Default — maintain
        return ProgressionRecommendation(
            action: .maintain,
            reason: "You're making steady progress. Keep up the current routine.",
            detailPoints: [
                "Pain: \(analysis.painTrend.rawValue)",
                "Completion: \(Int(completion * 100))%",
                "Continue at current level"
            ],
            confidence: .moderate,
            analysis: analysis
        )
    }

    // MARK: - Apply Progression

    /// Apply a progression recommendation to a plan, returning a modified copy.
    static func applyProgression(
        _ action: ProgressionAction,
        to plan: RehabPlan
    ) -> RehabPlan {
        var updatedPlan = plan

        switch action {
        case .advance:
            updatedPlan.exercises = plan.exercises.map { exercise in
                var e = exercise
                e.sets = min(exercise.sets + 1, 6)
                e.reps = adjustReps(exercise.reps, increment: 2)
                e.difficulty = nextDifficulty(exercise.difficulty)
                return e
            }
        case .scaleBack:
            updatedPlan.exercises = plan.exercises.map { exercise in
                var e = exercise
                e.sets = max(exercise.sets - 1, 1)
                e.reps = adjustReps(exercise.reps, increment: -2)
                // Don't reduce difficulty — keep exercise type, just lower volume
                return e
            }
        case .maintain, .insufficientData:
            break
        }

        updatedPlan.lastModifiedDate = Date()
        return updatedPlan
    }

    // MARK: - Helpers

    /// Adjust reps string by an increment. Handles "10", "10-12", and passthrough for "30 sec" etc.
    static func adjustReps(_ reps: String, increment: Int) -> String {
        // Simple number: "10"
        if let num = Int(reps) {
            return "\(max(num + increment, 1))"
        }
        // Range: "10-12"
        let parts = reps.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 {
            return "\(max(parts[0] + increment, 1))-\(max(parts[1] + increment, 1))"
        }
        // Duration or other format: return as-is
        return reps
    }

    /// Move difficulty up one level.
    static func nextDifficulty(_ current: RehabExercise.Difficulty) -> RehabExercise.Difficulty {
        switch current {
        case .beginner: return .intermediate
        case .intermediate: return .advanced
        case .advanced: return .advanced
        }
    }

    /// Compare average pain of early sessions vs recent sessions.
    static func calculatePainTrend(
        early: [WorkoutSession],
        recent: [WorkoutSession]
    ) -> (PainTrend, Double) {
        let earlyAvg = early.map(\.painLevel).mean
        let recentAvg = recent.map(\.painLevel).mean
        let delta = recentAvg - earlyAvg  // negative = improving

        if delta <= -painTrendThreshold {
            return (.improving, abs(delta))
        } else if delta >= painTrendThreshold {
            return (.worsening, abs(delta))
        } else {
            return (.stable, abs(delta))
        }
    }

    /// Average number of days between consecutive sessions.
    static func calculateDaysBetween(sessions: [WorkoutSession]) -> Double {
        guard sessions.count >= 2 else { return 0 }
        let sorted = sessions.sorted { $0.date < $1.date }
        var totalDays: Double = 0
        for i in 1..<sorted.count {
            let diff = sorted[i].date.timeIntervalSince(sorted[i - 1].date)
            totalDays += diff / 86400
        }
        return totalDays / Double(sorted.count - 1)
    }
}

// MARK: - Collection Extension

extension Collection where Element == Double {
    /// Arithmetic mean. Returns 0 for empty collections.
    fileprivate var mean: Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
}
