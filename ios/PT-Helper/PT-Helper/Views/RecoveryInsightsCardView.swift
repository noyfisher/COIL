import SwiftUI

/// Compact card showing AI recovery insights, a generate button, or an insufficient-data prompt.
/// Used in ProgressChartView and HomeTab.
struct RecoveryInsightsCardView: View {
    @ObservedObject var vm: RecoveryInsightsViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel

    /// Whether to show the "View Full Digest" navigation link.
    var showDetailLink: Bool = true

    var body: some View {
        Group {
            if vm.isLoading {
                loadingCard
            } else if let insight = vm.insight {
                insightPreviewCard(insight)
            } else if vm.hasEnoughData(sessions: workoutViewModel.sessions) {
                generateCard
            } else {
                insufficientDataCard
            }
        }
        .trackScreen("RecoveryInsightsCard")
    }

    // MARK: - Generate Card

    private var generateCard: some View {
        CardSection(icon: "brain.head.profile", color: AppColors.accent, title: "Recovery Insights") {
            VStack(spacing: AppSpacing.md) {
                Text("Your AI recovery coach can analyze your recent workouts and share personalized insights.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)

                if let error = vm.error {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                Button(action: generate) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "sparkles")
                        Text("Generate Weekly Digest")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        CardSection(icon: "brain.head.profile", color: AppColors.accent, title: "Recovery Insights") {
            HStack(spacing: AppSpacing.md) {
                ProgressView()
                    .scaleEffect(0.9)
                Text("Analyzing your recovery data…")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Insight Preview Card

    private func insightPreviewCard(_ insight: RecoveryInsight) -> some View {
        let content = CardSection(icon: "brain.head.profile", color: AppColors.accent, title: "Recovery Insights") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Headline
                Text(insight.headline)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)

                // Summary
                Text(insight.summary)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(3)

                // Quick stats row
                HStack(spacing: AppSpacing.md) {
                    miniStat(
                        icon: trendIcon(insight.painAnalysis.trendDirection),
                        color: trendColor(insight.painAnalysis.trendDirection),
                        label: "Pain",
                        value: insight.painAnalysis.trendDirection.capitalized
                    )
                    miniStat(
                        icon: "checkmark.circle.fill",
                        color: adherenceColor(insight.adherenceAnalysis.score),
                        label: "Adherence",
                        value: "\(insight.adherenceAnalysis.score)%"
                    )
                    miniStat(
                        icon: "star.fill",
                        color: AppColors.warning,
                        label: "Wins",
                        value: "\(insight.keyWins.count)"
                    )
                }

                if showDetailLink {
                    HStack {
                        Spacer()
                        Text("View Full Digest")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.accent)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }
        }

        return Group {
            if showDetailLink {
                NavigationLink(destination: RecoveryInsightsDetailView(vm: vm)) {
                    content
                }
                .buttonStyle(.plain)
            } else {
                content
            }
        }
    }

    // MARK: - Insufficient Data Card

    private var insufficientDataCard: some View {
        let recent = vm.recentSessions(from: workoutViewModel.sessions)
        let remaining = RecoveryInsightsViewModel.minimumSessionCount - recent.count

        return CardSection(icon: "brain.head.profile", color: AppColors.mutedText, title: "Recovery Insights") {
            VStack(spacing: AppSpacing.sm) {
                Text("Complete \(remaining) more workout\(remaining == 1 ? "" : "s") in the next 2 weeks to unlock AI recovery insights.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)

                // Progress dots
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<RecoveryInsightsViewModel.minimumSessionCount, id: \.self) { index in
                        Circle()
                            .fill(index < recent.count ? AppColors.accent : AppColors.mutedText.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Helpers

    private func generate() {
        Task {
            await vm.generateInsights(
                sessions: workoutViewModel.sessions,
                plans: savedPlansViewModel.rehabPlans,
                profile: UserProfileService.shared.profile
            )
        }
    }

    private func miniStat(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(AppColors.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func trendIcon(_ direction: String) -> String {
        switch direction {
        case "improving": return "arrow.down.right"
        case "worsening": return "arrow.up.right"
        default: return "arrow.right"
        }
    }

    private func trendColor(_ direction: String) -> Color {
        switch direction {
        case "improving": return AppColors.success
        case "worsening": return AppColors.danger
        default: return AppColors.warning
        }
    }

    private func adherenceColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return AppColors.success
        case 50...79: return AppColors.warning
        default: return AppColors.danger
        }
    }
}
