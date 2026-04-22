import SwiftUI

/// Compact streak badge showing flame icon + streak count.
/// Used in the HomeTab stats row.
struct StreakBadgeView: View {
    @ObservedObject var streakService: StreakService

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            ZStack {
                Circle()
                    .fill(streakColor.opacity(0.12))
                    .frame(width: 28, height: 28)

                Image(systemName: streakService.streakData.isActive ? "flame.fill" : "flame")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(streakColor)
            }

            Text("\(streakService.streakData.currentStreak)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)

            Text("Streak")
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    private var streakColor: Color {
        switch streakService.streakData.currentStreak {
        case 0: return AppColors.secondaryText
        case 1...6: return AppColors.warning
        case 7...29: return AppColors.danger
        default: return AppColors.accent
        }
    }
}
