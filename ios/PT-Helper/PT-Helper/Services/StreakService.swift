import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Manages workout streaks and achievement tracking.
@MainActor
class StreakService: ObservableObject {
    static let shared = StreakService()

    @Published var streakData: StreakData = StreakData()
    @Published var achievements: [Achievement] = Achievement.catalog
    @Published var newlyEarned: Achievement? = nil

    private let db = Firestore.firestore()

    init(skipFirebaseLoad: Bool = false) {
        if !skipFirebaseLoad {
            Task { await loadFromFirestore() }
        }
    }

    // MARK: - Streak Update

    /// Call after a workout session is saved
    func updateStreak(after session: WorkoutSession) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastDate = streakData.lastWorkoutDate {
            let lastDay = calendar.startOfDay(for: lastDate)

            if calendar.isDate(lastDay, inSameDayAs: today) {
                // Already worked out today — no streak change
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(lastDay, inSameDayAs: yesterday) {
                // Consecutive day — increment streak
                streakData.currentStreak += 1
            } else {
                // Streak broken — reset to 1
                streakData.currentStreak = 1
            }
        } else {
            // First ever workout
            streakData.currentStreak = 1
        }

        streakData.lastWorkoutDate = Date()
        streakData.longestStreak = max(streakData.longestStreak, streakData.currentStreak)

        checkAchievements(totalSessions: nil)
        Task { await saveToFirestore() }
    }

    /// Check all achievements against current data
    func checkAchievements(totalSessions: Int?) {
        for i in achievements.indices {
            guard !achievements[i].isEarned else { continue }

            var earned = false
            switch achievements[i].id {
            case "first_workout":
                earned = (totalSessions ?? 0) >= 1 || streakData.currentStreak >= 1
            case "streak_3":
                earned = streakData.longestStreak >= 3
            case "streak_7":
                earned = streakData.longestStreak >= 7
            case "streak_30":
                earned = streakData.longestStreak >= 30
            case "sessions_10":
                earned = (totalSessions ?? 0) >= 10
            case "sessions_50":
                earned = (totalSessions ?? 0) >= 50
            default:
                break
            }

            if earned {
                achievements[i].dateEarned = Date()
                newlyEarned = achievements[i]
                AnalyticsService.shared.log(.achievementEarned, parameters: ["achievement_id": achievements[i].id])
            }
        }
    }

    /// Awards the "pain_improved" achievement when the trailing 7-day average
    /// post-workout pain is meaningfully lower than the prior 7 days (audit #37 —
    /// previously impossible to earn: checkAchievements had no case for it).
    /// Requires ≥2 sessions in each half so it isn't awarded on noise.
    func evaluatePainImprovement(sessions: [WorkoutSession]) {
        guard let i = achievements.firstIndex(where: { $0.id == "pain_improved" }),
              !achievements[i].isEarned else { return }

        let calendar = Calendar.current
        let now = Date()
        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now),
              let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) else { return }

        let recent = sessions.filter { $0.date > sevenDaysAgo }
        let prior = sessions.filter { $0.date > fourteenDaysAgo && $0.date <= sevenDaysAgo }
        guard recent.count >= 2, prior.count >= 2 else { return }

        let recentAvg = recent.map(\.painLevel).reduce(0, +) / Double(recent.count)
        let priorAvg = prior.map(\.painLevel).reduce(0, +) / Double(prior.count)

        // Require a meaningful decrease (≥0.5 on the 0–10 scale).
        if recentAvg <= priorAvg - 0.5 {
            achievements[i].dateEarned = Date()
            newlyEarned = achievements[i]
            AnalyticsService.shared.log(.achievementEarned, parameters: ["achievement_id": "pain_improved"])
            Task { await saveToFirestore() }
        }
    }

    // MARK: - Firestore

    func loadFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        do {
            let doc = try await db.collection("users").document(uid)
                .collection("streakData").document("current").getDocument()

            if let data = doc.data() {
                streakData.currentStreak = data["currentStreak"] as? Int ?? 0
                streakData.longestStreak = data["longestStreak"] as? Int ?? 0
                streakData.lastWorkoutDate = (data["lastWorkoutDate"] as? Timestamp)?.dateValue()

                // Load earned achievements
                if let earnedList = data["achievements"] as? [[String: Any]] {
                    for earned in earnedList {
                        if let id = earned["id"] as? String,
                           let dateEarned = (earned["dateEarned"] as? Timestamp)?.dateValue(),
                           let index = achievements.firstIndex(where: { $0.id == id }) {
                            achievements[index].dateEarned = dateEarned
                        }
                    }
                }
            }
        } catch {
            AppLogger.data.error("Error loading streak data: \(error.localizedDescription)")
        }
    }

    func saveToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var data: [String: Any] = [
            "currentStreak": streakData.currentStreak,
            "longestStreak": streakData.longestStreak
        ]
        if let lastDate = streakData.lastWorkoutDate {
            data["lastWorkoutDate"] = Timestamp(date: lastDate)
        }

        // Save earned achievements
        let earnedAchievements: [[String: Any]] = achievements
            .filter { $0.isEarned }
            .compactMap { achievement in
                guard let dateEarned = achievement.dateEarned else { return nil }
                return ["id": achievement.id, "dateEarned": Timestamp(date: dateEarned)]
            }
        data["achievements"] = earnedAchievements

        do {
            try await db.collection("users").document(uid)
                .collection("streakData").document("current").setData(data)
        } catch {
            AppLogger.data.error("Error saving streak data: \(error.localizedDescription)")
        }
    }

    /// Reset newly earned flag (call after displaying celebration)
    func clearNewlyEarned() {
        newlyEarned = nil
    }
}
