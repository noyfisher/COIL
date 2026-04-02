import SwiftUI

/// Dashboard card surfacing today's movement snack.
/// Rotates daily based on active wellness goals and time of day.
struct DailyMovementSnackCard: View {
    @ObservedObject private var scheduler = DailySnackScheduler.shared
    @ObservedObject private var profileService = UserProfileService.shared

    let wellnessGoals: [String]

    var body: some View {
        Group {
            if scheduler.isGenerating {
                loadingCard
            } else if let snack = scheduler.currentSnack {
                snackCard(snack)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            guard let profile = profileService.profile else { return }
            Task {
                await scheduler.loadOrGenerate(profile: profile, wellnessGoals: wellnessGoals)
            }
        }
        .accessibilityIdentifier("prevention.snackCard")
    }

    // MARK: - Snack Card

    private func snackCard(_ snack: RehabPlan) -> some View {
        NavigationLink {
            GuidedWorkoutView(plan: snack, snackMode: true)
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Time-of-day icon
                ZStack {
                    Circle()
                        .fill(AppColors.accentTint)
                        .frame(width: 48, height: 48)
                    Image(systemName: scheduler.timeOfDayIcon)
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.accent)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text("\(scheduler.timeOfDayLabel) Snack")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.accent)
                        durationBadge(snack)
                    }
                    Text(snack.planName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(1)
                    Text("\(snack.exercises.count) exercises · bodyweight")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.accent)
            }
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.accent.opacity(0.25), lineWidth: 1.5)
            )
            .shadow(color: AppColors.cardShadowColor, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 48, height: 48)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.accent)
                    .symbolEffect(.pulse)
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Preparing your snack…")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.primaryText)
                Text("Generating your personalized movement routine")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            ProgressView()
                .tint(AppColors.accent)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func durationBadge(_ snack: RehabPlan) -> some View {
        // Estimate: ~1 min per exercise (30-45s hold + 5s rest)
        let minutes = max(3, snack.exercises.count)
        return Text("\(minutes) min")
            .font(.caption2.weight(.medium))
            .foregroundColor(AppColors.accent)
            .padding(.horizontal, AppSpacing.xs)
            .padding(.vertical, 2)
            .background(AppColors.accentTint)
            .cornerRadius(AppCorners.pill)
    }
}
