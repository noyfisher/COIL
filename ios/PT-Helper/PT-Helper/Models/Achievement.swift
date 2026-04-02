import Foundation

/// Represents a user achievement/milestone
struct Achievement: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let requirement: Int
    var dateEarned: Date?

    var isEarned: Bool { dateEarned != nil }

    /// All available achievements in the app
    static let catalog: [Achievement] = [
        Achievement(id: "first_workout", title: "First Steps", description: "Complete your first workout", iconName: "figure.walk", requirement: 1),
        Achievement(id: "streak_3", title: "Getting Going", description: "Maintain a 3-day streak", iconName: "flame", requirement: 3),
        Achievement(id: "streak_7", title: "Week Warrior", description: "Maintain a 7-day streak", iconName: "flame.fill", requirement: 7),
        Achievement(id: "streak_30", title: "Monthly Champion", description: "Maintain a 30-day streak", iconName: "trophy.fill", requirement: 30),
        Achievement(id: "sessions_10", title: "Dedicated", description: "Complete 10 workout sessions", iconName: "star", requirement: 10),
        Achievement(id: "sessions_50", title: "Committed", description: "Complete 50 workout sessions", iconName: "star.fill", requirement: 50),
        Achievement(id: "pain_improved", title: "Progress!", description: "Average pain decreased over 2 weeks", iconName: "arrow.down.heart", requirement: 1),

        // MARK: Preventative Streak Milestones
        Achievement(id: "prevent_streak_7",  title: "Seven Days Strong",   description: "Complete 7 days of preventative movement", iconName: "flame",        requirement: 7),
        Achievement(id: "prevent_streak_14", title: "Two-Week Habit",       description: "Complete 14 days of preventative movement", iconName: "flame.fill",   requirement: 14),
        Achievement(id: "prevent_streak_30", title: "Monthly Mover",        description: "Complete 30 days of preventative movement", iconName: "star.fill",    requirement: 30),
        Achievement(id: "prevent_streak_60", title: "Consistency Champion", description: "Complete 60 days of preventative movement", iconName: "trophy",       requirement: 60),
        Achievement(id: "prevent_streak_90", title: "Prevention Pro",       description: "Complete 90 days of preventative movement", iconName: "trophy.fill",  requirement: 90),
    ]
}

/// Tracks the user's workout streak
struct StreakData: Codable {
    var currentStreak: Int = 0
    var longestStreak: Int = 0
    var lastWorkoutDate: Date?

    /// Check if the streak is still active (last workout was today or yesterday)
    var isActive: Bool {
        guard let last = lastWorkoutDate else { return false }
        let calendar = Calendar.current
        return calendar.isDateInToday(last) || calendar.isDateInYesterday(last)
    }
}
