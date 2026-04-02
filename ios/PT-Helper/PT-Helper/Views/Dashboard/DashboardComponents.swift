import SwiftUI

// MARK: - Dashboard Widget Container

struct DashWidgetContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background(AppColors.dashSurface)
            .cornerRadius(AppCorners.large)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.large)
                    .stroke(AppColors.dashBorder, lineWidth: 1)
            )
    }
}

extension View {
    func dashWidget() -> some View {
        modifier(DashWidgetContainer())
    }
}

// MARK: - Stat Widget

struct DashStatWidget: View {
    let icon: String
    var iconColor: Color = AppColors.dashAccent
    let value: String
    let label: String
    var trend: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(iconColor)
                Spacer()
                if let trend = trend {
                    Text(trend)
                        .font(.caption2)
                        .foregroundColor(trendColor)
                }
            }

            Text(value)
                .font(AppFonts.dataMedium)
                .foregroundColor(AppColors.dashTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label.uppercased())
                .font(AppFonts.dashLabel)
                .foregroundColor(AppColors.dashTextSecondary)
                .tracking(0.8)
        }
        .dashWidget()
    }

    private var trendColor: Color {
        if trend?.contains("↑") == true { return AppColors.dashSuccess }
        if trend?.contains("↓") == true { return AppColors.dashDanger }
        return AppColors.dashTextSecondary
    }
}

// MARK: - Section Header

struct DashSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(AppFonts.dashLabel)
                .foregroundColor(AppColors.dashTextSecondary)
                .tracking(0.8)
            Spacer()
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.dashAccent)
                }
            }
        }
    }
}

// MARK: - Empty State

struct DashEmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.dashAccent.opacity(0.6), AppColors.dashSecondaryAccent.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: AppSpacing.xs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppColors.dashTextPrimary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.dashTextSecondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.ctaText)
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.dashAccentGradient)
                        .cornerRadius(AppCorners.pill)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxxl)
        .dashWidget()
    }
}

// MARK: - Chip Button (Dark)

struct DashChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.dashTextSecondary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? AppColors.dashAccent : AppColors.dashSurface)
                .cornerRadius(AppCorners.small)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCorners.small)
                        .stroke(isSelected ? Color.clear : AppColors.dashBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Dashboard Action Button

struct DashActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    var iconColor: Color = AppColors.dashAccent

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.15))
                .cornerRadius(AppCorners.medium)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.dashTextPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.dashTextSecondary)
        }
        .dashWidget()
    }
}
