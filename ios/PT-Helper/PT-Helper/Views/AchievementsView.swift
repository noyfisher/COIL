import SwiftUI

/// Full list of achievements (earned and locked).
struct AchievementsView: View {
    @ObservedObject var streakService: StreakService

    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Streak summary
                    HStack(spacing: AppSpacing.xl) {
                        streakStat(
                            value: "\(streakService.streakData.currentStreak)",
                            label: "Current",
                            icon: "flame.fill",
                            color: .orange
                        )
                        streakStat(
                            value: "\(streakService.streakData.longestStreak)",
                            label: "Longest",
                            icon: "trophy.fill",
                            color: .yellow
                        )
                        streakStat(
                            value: "\(earnedCount)",
                            label: "Earned",
                            icon: "star.fill",
                            color: .purple
                        )
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    // Achievement list
                    ForEach(streakService.achievements) { achievement in
                        achievementRow(achievement)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("Achievements")
    }

    // MARK: - Components

    private func streakStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Icon
            Image(systemName: achievement.iconName)
                .font(.title3)
                .foregroundColor(achievement.isEarned ? .yellow : .gray)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(achievement.isEarned ? Color.yellow.opacity(0.15) : Color.gray.opacity(0.1))
                )

            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(achievement.isEarned ? .primary : .secondary)

                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let date = achievement.dateEarned {
                    Text("Earned \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if achievement.isEarned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(.gray.opacity(0.4))
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .opacity(achievement.isEarned ? 1 : 0.7)
    }

    private var earnedCount: Int {
        streakService.achievements.filter { $0.isEarned }.count
    }
}
