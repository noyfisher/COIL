import Foundation

/// Tracks a user's preventative movement streak — separate from the rehab workout streak.
/// Increments when any movement snack OR wellness session is completed for the day.
struct PreventativeStreak: Codable, Identifiable {
    var id: UUID = UUID()
    var goalLabel: String = "Prevention"
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastActivityDate: Date?
    /// Rest days used in the current week (resets every Monday). Max 1/week.
    var restDaysUsedThisWeek: Int = 0
    /// ISO date strings ("yyyy-MM-dd") of days with completed activity (last 30 days).
    var activityDays: [String] = []
    /// IDs of prevention milestone achievements already earned.
    var earnedMilestoneIds: [String] = []

    // MARK: - Computed

    var isActive: Bool {
        guard let last = lastActivityDate else { return false }
        let calendar = Calendar.current
        return calendar.isDateInToday(last) || calendar.isDateInYesterday(last)
    }

    var canLogRestDay: Bool {
        restDaysUsedThisWeek < 1
    }

    /// Returns activity status for each of the last 7 days (index 0 = 6 days ago, index 6 = today).
    func weekActivity() -> [Bool] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: Date()) else { return false }
            let key = formatter.string(from: day)
            return activityDays.contains(key) || activityDays.contains(key + "_rest")
        }
    }

    /// Milestone days for the progress display.
    static let milestones: [Int] = [7, 14, 30, 60, 90]

    func isMilestoneEarned(_ days: Int) -> Bool {
        earnedMilestoneIds.contains("prevent_streak_\(days)")
    }
}
