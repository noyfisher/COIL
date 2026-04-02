import SwiftUI

/// Displays the user's preventative movement streak — hero metric, weekly calendar dots,
/// milestone progress, and rest-day option. Embedded in PreventativeHomeView.
struct PreventativeStreakView: View {
    @ObservedObject private var vm = PreventativeStreakViewModel.shared

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            heroCard
            weeklyCalendar
            milestonesRow
            restDaySection
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        HStack(spacing: AppSpacing.lg) {
            // Flame icon with active color
            ZStack {
                Circle()
                    .fill(vm.streak.isActive ? AppColors.warning.opacity(0.15) : AppColors.elevatedSurface)
                    .frame(width: 64, height: 64)
                Image(systemName: vm.streak.isActive ? "flame.fill" : "flame")
                    .font(.system(size: 28))
                    .foregroundColor(vm.streak.isActive ? AppColors.warning : AppColors.mutedText)
                    .symbolEffect(.bounce, value: vm.justIncremented)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                    Text("\(vm.streak.currentStreak)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundColor(vm.streak.isActive ? AppColors.primaryText : AppColors.secondaryText)
                        .contentTransition(.numericText())
                    Text(vm.streak.currentStreak == 1 ? "day" : "days")
                        .font(.system(.title3, design: .rounded).weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.bottom, 4)
                }

                Text(vm.streak.goalLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 3)
                    .background(AppColors.accentTint)
                    .cornerRadius(AppCorners.pill)
            }

            Spacer()

            // Longest streak
            VStack(spacing: 2) {
                Text("\(vm.streak.longestStreak)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(AppColors.secondaryText)
                Text("best")
                    .font(.caption2)
                    .foregroundColor(AppColors.mutedText)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 6, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(
                    vm.streak.isActive ? AppColors.warning.opacity(0.3) : AppColors.subtleBorder,
                    lineWidth: 1.5
                )
        )
    }

    // MARK: - Weekly Calendar

    private var weeklyCalendar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Last 7 Days")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.mutedText)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 0) {
                ForEach(weekDayData().indices, id: \.self) { index in
                    let item = weekDayData()[index]
                    VStack(spacing: AppSpacing.xs) {
                        Text(item.label)
                            .font(.caption2)
                            .foregroundColor(AppColors.mutedText)

                        Circle()
                            .fill(item.isActive ? AppColors.accent : AppColors.elevatedSurface)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(item.isToday ? AppColors.accent : Color.clear, lineWidth: 2)
                            )
                            .overlay(
                                Image(systemName: item.isRest ? "moon.zzz.fill" : "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(item.isActive ? .white : AppColors.mutedText.opacity(0.4))
                                    .opacity(item.isActive ? 1 : 0)
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)
    }

    // MARK: - Milestones

    private var milestonesRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Milestones")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.mutedText)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: AppSpacing.sm) {
                ForEach(PreventativeStreak.milestones, id: \.self) { days in
                    milestoneBadge(days: days)
                }
                Spacer()
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)
    }

    private func milestoneBadge(days: Int) -> some View {
        let earned = vm.streak.isMilestoneEarned(days)
        let isCurrent = !earned && vm.streak.currentStreak < days && (vm.streak.currentStreak > (previousMilestone(before: days) ?? 0))
        let progressRatio: Double = {
            guard !earned else { return 1.0 }
            let prev = Double(previousMilestone(before: days) ?? 0)
            let progress = Double(vm.streak.currentStreak) - prev
            let range = Double(days) - prev
            guard range > 0 else { return 0 }
            return min(1.0, progress / range)
        }()

        return VStack(spacing: AppSpacing.xs) {
            ZStack {
                Circle()
                    .stroke(AppColors.elevatedSurface, lineWidth: 3)
                    .frame(width: 44, height: 44)

                // Progress arc for current milestone
                if isCurrent && progressRatio > 0 {
                    Circle()
                        .trim(from: 0, to: progressRatio)
                        .stroke(AppColors.accent.opacity(0.4), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                }

                Circle()
                    .fill(earned ? AppColors.accent : (isCurrent ? AppColors.accentTint : AppColors.elevatedSurface))
                    .frame(width: 36, height: 36)

                Image(systemName: milestoneIcon(days: days, earned: earned))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(earned ? .white : (isCurrent ? AppColors.accent : AppColors.mutedText))
            }

            Text("\(days)d")
                .font(.caption2.weight(.medium))
                .foregroundColor(earned ? AppColors.accent : AppColors.mutedText)
        }
    }

    // MARK: - Rest Day

    private var restDaySection: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest Day")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                    Text(vm.streak.canLogRestDay
                         ? "Log a rest day to keep your streak alive (1/week)"
                         : "Rest day used this week — resets Monday")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                Spacer()
                Button {
                    vm.logRestDay()
                } label: {
                    Text(vm.streak.canLogRestDay ? "Log Rest" : "Used")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(vm.streak.canLogRestDay ? AppColors.accent : AppColors.mutedText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            vm.streak.canLogRestDay ? AppColors.accentTint : AppColors.elevatedSurface
                        )
                        .cornerRadius(AppCorners.pill)
                }
                .disabled(!vm.streak.canLogRestDay)
                .accessibilityIdentifier("prevention.streak.restDayButton")
            }
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)
        }
    }

    // MARK: - Helpers

    private struct WeekDayItem {
        let label: String
        let isActive: Bool
        let isToday: Bool
        let isRest: Bool
    }

    private func weekDayData() -> [WeekDayItem] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dayLabels = ["S", "M", "T", "W", "T", "F", "S"]

        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -(6 - offset), to: Date()) else {
                return WeekDayItem(label: "?", isActive: false, isToday: false, isRest: false)
            }
            let key = formatter.string(from: day)
            let isActive = vm.streak.activityDays.contains(key) || vm.streak.activityDays.contains(key + "_rest")
            let isRest = vm.streak.activityDays.contains(key + "_rest")
            let isToday = calendar.isDateInToday(day)
            let weekdayIndex = calendar.component(.weekday, from: day) - 1 // 0=Sun
            return WeekDayItem(
                label: dayLabels[weekdayIndex],
                isActive: isActive,
                isToday: isToday,
                isRest: isRest
            )
        }
    }

    private func milestoneIcon(days: Int, earned: Bool) -> String {
        if earned { return "checkmark" }
        switch days {
        case 7: return "flame"
        case 14: return "flame.fill"
        case 30: return "star.fill"
        case 60: return "trophy"
        default: return "trophy.fill"
        }
    }

    private func previousMilestone(before days: Int) -> Int? {
        PreventativeStreak.milestones.filter { $0 < days }.last
    }
}

// MARK: - Milestone Celebration Overlay

extension PreventativeStreakView {
    /// Sheet content shown when a new milestone is earned.
    struct MilestoneCelebrationSheet: View {
        let achievement: Achievement
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: AppSpacing.xl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(AppColors.accentTint)
                        .frame(width: 100, height: 100)
                    Image(systemName: achievement.iconName)
                        .font(.system(size: 44))
                        .foregroundColor(AppColors.accent)
                        .symbolEffect(.bounce, value: true)
                }

                VStack(spacing: AppSpacing.sm) {
                    Text("Milestone Unlocked!")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accent)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text(achievement.title)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                        .multilineTextAlignment(.center)

                    Text(achievement.description)
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xl)
                }

                Button(action: { dismiss() }) {
                    Text("Keep Going 🌿")
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.xxl)

                Spacer()
            }
            .padding(AppSpacing.xl)
        }
    }
}
