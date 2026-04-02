import Foundation
import FirebaseFirestore
import FirebaseAuth

private let defaultsKey = "PreventativeStreak"
private let isoDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// Manages the user's preventative movement streak.
/// Increments when a movement snack or wellness session is completed.
@MainActor
final class PreventativeStreakViewModel: ObservableObject {
    static let shared = PreventativeStreakViewModel()

    @Published var streak: PreventativeStreak = PreventativeStreak()
    @Published var newMilestone: Achievement?
    @Published var justIncremented: Bool = false

    private let db = Firestore.firestore()

    init(skipLoad: Bool = false) {
        loadFromDefaults()
        if !skipLoad {
            Task { await loadFromFirestore() }
        }
        resetWeeklyRestDaysIfNeeded()
    }

    // MARK: - Public Actions

    /// Call after any movement snack or wellness session is completed.
    func incrementStreak() async {
        let todayKey = isoDateFormatter.string(from: Date())

        // Don't double-count the same calendar day
        guard !streak.activityDays.contains(todayKey) else { return }

        let calendar = Calendar.current

        // Update streak count
        if let last = streak.lastActivityDate {
            let lastDay = calendar.startOfDay(for: last)
            let today = calendar.startOfDay(for: Date())
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
               calendar.isDate(lastDay, inSameDayAs: yesterday) || calendar.isDate(lastDay, inSameDayAs: today) {
                streak.currentStreak += 1
            } else {
                streak.currentStreak = 1
            }
        } else {
            streak.currentStreak = 1
        }

        streak.longestStreak = max(streak.longestStreak, streak.currentStreak)
        streak.lastActivityDate = Date()

        // Track activity day (keep last 30)
        var days = streak.activityDays
        days.append(todayKey)
        if days.count > 30 { days = Array(days.suffix(30)) }
        streak.activityDays = days

        // Celebrations & milestones
        checkMilestones()

        justIncremented = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.justIncremented = false
        }

        saveToDefaults()
        await saveToFirestore()

        SessionLogger.shared.log(.stateUpdated, category: .stateChange,
                                  message: "Preventative streak incremented",
                                  metadata: ["streak": "\(streak.currentStreak)"])
    }

    /// Log a rest day (max 1/week). Keeps the streak alive without activity.
    func logRestDay() {
        guard streak.canLogRestDay else { return }

        let todayKey = isoDateFormatter.string(from: Date())
        guard !streak.activityDays.contains(todayKey),
              !streak.activityDays.contains(todayKey + "_rest") else { return }

        // Extend streak if consecutive
        let calendar = Calendar.current
        if let last = streak.lastActivityDate,
           let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
           calendar.isDate(calendar.startOfDay(for: last), inSameDayAs: calendar.startOfDay(for: yesterday)) {
            streak.currentStreak += 1
            streak.longestStreak = max(streak.longestStreak, streak.currentStreak)
        }

        streak.restDaysUsedThisWeek += 1
        streak.lastActivityDate = Date()
        streak.activityDays.append(todayKey + "_rest")

        saveToDefaults()
        Task { await saveToFirestore() }
    }

    /// Update the goal label shown in the streak view.
    func updateGoalLabel(_ label: String) {
        streak.goalLabel = label
        saveToDefaults()
    }

    func clearNewMilestone() {
        newMilestone = nil
    }

    // MARK: - Milestones

    private func checkMilestones() {
        for days in PreventativeStreak.milestones {
            let milestoneId = "prevent_streak_\(days)"
            guard streak.currentStreak >= days,
                  !streak.earnedMilestoneIds.contains(milestoneId) else { continue }
            streak.earnedMilestoneIds.append(milestoneId)
            if let achievement = Achievement.catalog.first(where: { $0.id == milestoneId }) {
                var earned = achievement
                earned.dateEarned = Date()
                newMilestone = earned
                AnalyticsService.shared.log(.achievementEarned,
                                             parameters: ["achievement_id": milestoneId])
            }
        }
    }

    // MARK: - Weekly Reset

    private func resetWeeklyRestDaysIfNeeded() {
        // Reset rest day count each Monday
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        if weekday == 2 { // Monday
            if let last = streak.lastActivityDate,
               !calendar.isDateInToday(last) {
                streak.restDaysUsedThisWeek = 0
                saveToDefaults()
            }
        }
    }

    // MARK: - UserDefaults Persistence

    private func loadFromDefaults() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode(PreventativeStreak.self, from: data) else { return }
        streak = saved
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(streak) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    // MARK: - Firestore Sync

    func loadFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users").document(uid)
                .collection("preventativeStreaks").document("current").getDocument()
            guard let data = doc.data() else { return }

            streak.currentStreak = data["currentStreak"] as? Int ?? streak.currentStreak
            streak.longestStreak = data["longestStreak"] as? Int ?? streak.longestStreak
            streak.lastActivityDate = (data["lastActivityDate"] as? Timestamp)?.dateValue() ?? streak.lastActivityDate
            streak.restDaysUsedThisWeek = data["restDaysUsedThisWeek"] as? Int ?? streak.restDaysUsedThisWeek
            streak.activityDays = data["activityDays"] as? [String] ?? streak.activityDays
            streak.earnedMilestoneIds = data["earnedMilestoneIds"] as? [String] ?? streak.earnedMilestoneIds
            streak.goalLabel = data["goalLabel"] as? String ?? streak.goalLabel

            saveToDefaults()
        } catch {
            AppLogger.data.error("Error loading preventative streak: \(error.localizedDescription)")
        }
    }

    private func saveToFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var data: [String: Any] = [
            "currentStreak": streak.currentStreak,
            "longestStreak": streak.longestStreak,
            "restDaysUsedThisWeek": streak.restDaysUsedThisWeek,
            "activityDays": streak.activityDays,
            "earnedMilestoneIds": streak.earnedMilestoneIds,
            "goalLabel": streak.goalLabel
        ]
        if let last = streak.lastActivityDate {
            data["lastActivityDate"] = Timestamp(date: last)
        }
        do {
            try await db.collection("users").document(uid)
                .collection("preventativeStreaks").document("current").setData(data)
        } catch {
            AppLogger.data.error("Error saving preventative streak: \(error.localizedDescription)")
        }
    }
}
