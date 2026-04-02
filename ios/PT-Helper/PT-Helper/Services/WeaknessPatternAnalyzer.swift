import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PT-Helper", category: "WeaknessPatternAnalyzer")

// MARK: - Muscle Group → Injury Risk Lookup

/// Static lookup mapping target area keys (from `RehabExercise.targetArea`) to canonical
/// muscle group names and their forward-looking injury risks.
private struct MuscleGroupInfo {
    let canonicalName: String
    let linkedRisk: String
    let recommendation: String
    /// Target area keywords that map to this group (lowercased)
    let keywords: [String]
}

private let muscleGroupLookup: [MuscleGroupInfo] = [
    MuscleGroupInfo(
        canonicalName: "Hip Flexors",
        linkedRisk: "Lower back strain and anterior hip pain",
        recommendation: "Hip flexors are key to lumbar health — add a daily hip flexor stretch.",
        keywords: ["hip flexor", "hip", "iliopsoas", "psoas"]
    ),
    MuscleGroupInfo(
        canonicalName: "Glutes",
        linkedRisk: "Knee tracking problems and lower back dysfunction",
        recommendation: "Strong glutes protect your knees and spine — include glute bridges or clamshells.",
        keywords: ["glute", "gluteal", "glutes", "hip abductor", "piriformis"]
    ),
    MuscleGroupInfo(
        canonicalName: "Core",
        linkedRisk: "Lower back instability and disc compression",
        recommendation: "A strong core is your spine's foundation — try adding dead bugs or planks.",
        keywords: ["core", "abdominal", "abdominals", "transverse abdominis", "oblique", "trunk"]
    ),
    MuscleGroupInfo(
        canonicalName: "Hamstrings",
        linkedRisk: "Posterior knee pain and hamstring strain",
        recommendation: "Tight or weak hamstrings strain the posterior chain — add Nordic curls or RDLs.",
        keywords: ["hamstring", "hamstrings", "biceps femoris", "posterior thigh"]
    ),
    MuscleGroupInfo(
        canonicalName: "Rotator Cuff",
        linkedRisk: "Shoulder impingement and rotator cuff tears",
        recommendation: "Internal/external rotation work prevents shoulder injuries — add band pull-aparts.",
        keywords: ["rotator cuff", "rotator", "shoulder stabilizer", "supraspinatus", "infraspinatus"]
    ),
    MuscleGroupInfo(
        canonicalName: "Thoracic Spine",
        linkedRisk: "Neck pain, headaches, and shoulder tension",
        recommendation: "Thoracic mobility counters forward posture — try thoracic rotations daily.",
        keywords: ["thoracic", "upper back", "rhomboid", "mid back", "t-spine"]
    ),
    MuscleGroupInfo(
        canonicalName: "Calves",
        linkedRisk: "Achilles tendinopathy and plantar fasciitis",
        recommendation: "Calf endurance prevents ankle and heel injuries — single-leg calf raises are effective.",
        keywords: ["calf", "calves", "gastrocnemius", "soleus", "ankle"]
    ),
    MuscleGroupInfo(
        canonicalName: "Hip Abductors",
        linkedRisk: "IT band syndrome and lateral knee pain",
        recommendation: "Hip abductor strength reduces lateral knee stress — try side-lying leg raises.",
        keywords: ["hip abductor", "abductor", "it band", "tensor fasciae latae", "tfl", "lateral hip"]
    ),
    MuscleGroupInfo(
        canonicalName: "Wrist & Forearm",
        linkedRisk: "Lateral epicondylitis (tennis elbow) and wrist tendinitis",
        recommendation: "Forearm balance prevents overuse injuries — add wrist flexor and extensor stretches.",
        keywords: ["wrist", "forearm", "grip", "elbow", "extensor", "flexor"]
    ),
    MuscleGroupInfo(
        canonicalName: "Neck & Cervical",
        linkedRisk: "Cervicogenic headaches and forward head posture",
        recommendation: "Cervical strengthening reduces headache risk — add chin tucks and neck isometrics.",
        keywords: ["neck", "cervical", "cervical spine", "sternocleidomastoid", "scalene", "upper trap"]
    ),
    MuscleGroupInfo(
        canonicalName: "Quadriceps",
        linkedRisk: "Patellofemoral pain and patellar tendinopathy",
        recommendation: "Quad strength protects your kneecap — wall sits and terminal knee extensions help.",
        keywords: ["quad", "quadricep", "quadriceps", "vastus", "knee extensor", "anterior thigh"]
    ),
]

// MARK: - Suppression Cache

private let suppressionKeyPrefix = "WeaknessInsightDismissed_"
private let suppressionDurationDays = 7

// MARK: - Analyzer

/// Singleton that analyzes the last 30 days of `WorkoutSession` records to detect
/// consistently skipped muscle groups and surface them as `WeaknessInsight` cards.
@MainActor
final class WeaknessPatternAnalyzer: ObservableObject {
    static let shared = WeaknessPatternAnalyzer()

    @Published var topInsight: WeaknessInsight?
    @Published var allInsights: [WeaknessInsight] = []

    private init() {}

    // MARK: - Public API

    /// Run analysis against the provided sessions. Safe to call on every app foreground.
    func analyze(sessions: [WorkoutSession]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentSessions = sessions.filter { $0.date >= cutoff && $0.isCompleted }

        guard recentSessions.count >= 3 else {
            // Not enough data yet
            topInsight = nil
            allInsights = []
            return
        }

        var skipCounts: [String: Int] = [:]
        var completionCounts: [String: Int] = [:]

        for session in recentSessions {
            // Count completions by normalizing exercise names to muscle groups
            for name in session.exercisesPerformed {
                if let group = muscleGroup(for: name) {
                    completionCounts[group, default: 0] += 1
                }
            }
            // Count skips
            for name in session.skippedExercises ?? [] {
                if let group = muscleGroup(for: name) {
                    skipCounts[group, default: 0] += 1
                }
            }
        }

        // Build insights for any group with skip rate > 40%
        var insights: [WeaknessInsight] = []

        let allGroups = Set(skipCounts.keys).union(Set(completionCounts.keys))
        for group in allGroups {
            let skips = skipCounts[group] ?? 0
            let completions = completionCounts[group] ?? 0
            let total = skips + completions
            guard total >= 3, skips > 0 else { continue }  // Need at least 3 data points

            let skipRate = Double(skips) / Double(total)
            guard skipRate >= 0.40 else { continue }

            guard let info = muscleGroupLookup.first(where: { $0.canonicalName == group }) else { continue }

            insights.append(WeaknessInsight(
                muscleGroup: info.canonicalName,
                targetAreaKey: group,
                skipRate: skipRate,
                sessionsAnalyzed: recentSessions.count,
                linkedRisk: info.linkedRisk,
                recommendation: info.recommendation
            ))
        }

        // Sort by skip rate descending
        insights.sort { $0.skipRate > $1.skipRate }

        allInsights = insights

        // Surface only non-suppressed insight
        topInsight = insights.first(where: { !isDismissed($0) })

        if let top = topInsight {
            logger.info("Top weakness: \(top.muscleGroup) (\(top.skipRatePercent)% skip rate)")
        }
    }

    // MARK: - Dismissal

    func dismiss(_ insight: WeaknessInsight) {
        let key = suppressionKeyPrefix + insight.muscleGroup
        UserDefaults.standard.set(Date(), forKey: key)
        // Refresh topInsight
        topInsight = allInsights.first(where: { !isDismissed($0) })
        logger.info("Dismissed weakness insight for: \(insight.muscleGroup)")
    }

    func isDismissed(_ insight: WeaknessInsight) -> Bool {
        let key = suppressionKeyPrefix + insight.muscleGroup
        guard let dismissedDate = UserDefaults.standard.object(forKey: key) as? Date else {
            return false
        }
        let days = Calendar.current.dateComponents([.day], from: dismissedDate, to: Date()).day ?? 0
        return days < suppressionDurationDays
    }

    // MARK: - Private Helpers

    /// Maps an exercise name to a canonical muscle group, using keyword matching against `targetArea`.
    private func muscleGroup(for exerciseName: String) -> String? {
        let lower = exerciseName.lowercased()
        // Try each muscle group's keywords
        for info in muscleGroupLookup {
            for keyword in info.keywords {
                if lower.contains(keyword) {
                    return info.canonicalName
                }
            }
        }
        return nil
    }
}

// MARK: - Convenience Extension

extension WeaknessPatternAnalyzer {
    /// Returns the canonical muscle group name for a given `RehabExercise.targetArea` string.
    func canonicalGroup(for targetArea: String) -> String? {
        let lower = targetArea.lowercased()
        for info in muscleGroupLookup {
            for keyword in info.keywords {
                if lower.contains(keyword) {
                    return info.canonicalName
                }
            }
        }
        return nil
    }
}
