import SwiftUI

/// Displays a progression recommendation card with action buttons.
/// Used in `RehabPlanView` to suggest advancing, maintaining, or scaling back.
struct AdaptiveProgressionBannerView: View {
    let recommendation: ProgressionRecommendation
    let onApply: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Header
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(accentColor.opacity(0.9))
                    .cornerRadius(7)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.subheadline.weight(.semibold))
                    Text(recommendation.reason)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                // Confidence indicator
                Text(recommendation.confidence.rawValue.capitalized)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(accentColor.opacity(0.12))
                    .cornerRadius(AppCorners.small)
            }

            // Detail bullets
            ForEach(recommendation.detailPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Circle()
                        .fill(accentColor.opacity(0.6))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                    Text(point)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            // Action buttons (only for actionable recommendations)
            if recommendation.action == .advance || recommendation.action == .scaleBack {
                HStack(spacing: AppSpacing.md) {
                    Button(action: onApply) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: recommendation.action == .advance
                                  ? "arrow.up.circle" : "arrow.down.circle")
                            Text(recommendation.action == .advance
                                 ? "Advance Plan" : "Scale Back")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.sm)
                        .background(accentColor)
                        .cornerRadius(AppCorners.small)
                    }

                    Button(action: onDismiss) {
                        Text("Not Now")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Computed

    private var iconName: String {
        switch recommendation.action {
        case .advance: return "arrow.up.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .scaleBack: return "arrow.down.circle.fill"
        case .insufficientData: return "chart.bar.doc.horizontal"
        }
    }

    private var titleText: String {
        switch recommendation.action {
        case .advance: return "Ready to Progress"
        case .maintain: return "Stay the Course"
        case .scaleBack: return "Consider Scaling Back"
        case .insufficientData: return "Building Your Data"
        }
    }

    private var accentColor: Color {
        switch recommendation.action {
        case .advance: return AppColors.success
        case .maintain: return AppColors.accent
        case .scaleBack: return AppColors.warning
        case .insufficientData: return AppColors.mutedText
        }
    }
}
