import SwiftUI

/// Dismissible dashboard card surfacing a detected muscle-group blind spot.
/// Appears when `WeaknessPatternAnalyzer` detects a skip rate > 40% for any group.
struct WeaknessInsightCard: View {
    @ObservedObject private var analyzer = WeaknessPatternAnalyzer.shared
    @ObservedObject private var profileService = UserProfileService.shared
    @State private var isDismissing = false

    var body: some View {
        if let insight = analyzer.topInsight, !isDismissing {
            card(insight: insight)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
        }
    }

    private func card(insight: WeaknessInsight) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header row
            HStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppColors.warning.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: insight.displayIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.warning)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("Blind Spot")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppColors.warning)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Text("·")
                            .foregroundColor(AppColors.mutedText)
                        Text("\(insight.skipRatePercent)% skipped")
                            .font(.caption)
                            .foregroundColor(AppColors.mutedText)
                    }
                    Text(insight.muscleGroup)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                }

                Spacer()

                // Dismiss button
                Button {
                    withAnimation(AppAnimations.smooth) {
                        isDismissing = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        analyzer.dismiss(insight)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.mutedText)
                        .padding(AppSpacing.xs)
                        .background(AppColors.elevatedSurface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Dismiss")
            }

            // Risk description
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(AppColors.warning)
                    .padding(.top, 2)
                Text("Often linked to: \(insight.linkedRisk)")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            // Recommendation
            HStack(alignment: .top, spacing: AppSpacing.sm) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption)
                    .foregroundColor(AppColors.accent)
                    .padding(.top, 2)
                Text(insight.recommendation)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            // CTA
            if let profile = profileService.profile {
                NavigationLink(destination: WellnessGoalPickerView(userProfile: profile)) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                        Text("Add to My Plan")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentTint)
                    .cornerRadius(AppCorners.pill)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("weaknessCard.addToPlanButton")
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.warning.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 6, x: 0, y: 2)
        .accessibilityIdentifier("prevention.weaknessInsightCard")
    }
}
