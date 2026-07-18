import SwiftUI

/// Full list of achievements (earned and locked).
struct AchievementsView: View {
    @ObservedObject var streakService: StreakService

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Streak summary
                    HStack(spacing: AppSpacing.xl) {
                        streakStat(
                            value: "\(streakService.streakData.currentStreak)",
                            label: "Current",
                            icon: "flame.fill",
                            color: AppColors.warning
                        )
                        streakStat(
                            value: "\(streakService.streakData.longestStreak)",
                            label: "Longest",
                            icon: "trophy.fill",
                            color: AppColors.warning
                        )
                        streakStat(
                            value: "\(earnedCount)",
                            label: "Earned",
                            icon: "star.fill",
                            color: AppColors.accent
                        )
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCorners.card)
                            .stroke(AppColors.cardBorder, lineWidth: 1)
                    )
                    .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                    // Achievement list
                    ForEach(streakService.achievements) { achievement in
                        achievementRow(achievement)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
                .floatingTabBarClearance()
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
                .font(AppFonts.title)
            Text(label)
                .font(AppFonts.micro)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Icon
            Image(systemName: achievement.iconName)
                .font(.title3)
                .foregroundColor(achievement.isEarned ? AppColors.warning : AppColors.mutedText)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(achievement.isEarned ? AppColors.warning.opacity(0.15) : AppColors.mutedText.opacity(0.1))
                )

            // Info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(achievement.title)
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(achievement.isEarned ? AppColors.primaryText : AppColors.secondaryText)

                Text(achievement.description)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)

                if let date = achievement.dateEarned {
                    Text("Earned \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.success)
                }
            }

            Spacer()

            if achievement.isEarned {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(AppColors.success)
            } else {
                Image(systemName: "lock.fill")
                    .foregroundColor(AppColors.mutedText.opacity(0.4))
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        .opacity(achievement.isEarned ? 1 : 0.7)
    }

    private var earnedCount: Int {
        streakService.achievements.filter { $0.isEarned }.count
    }
}
