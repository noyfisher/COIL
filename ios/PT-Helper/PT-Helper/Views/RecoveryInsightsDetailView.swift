import SwiftUI

/// Full-screen detail view showing the complete AI recovery digest.
struct RecoveryInsightsDetailView: View {
    @ObservedObject var vm: RecoveryInsightsViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel

    var body: some View {
        ZStack {
            AppColors.pageBackground
                .ignoresSafeArea()

            if let insight = vm.insight {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        headlineSection(insight)
                        painAnalysisSection(insight.painAnalysis)
                        adherenceSection(insight.adherenceAnalysis)
                        keyWinsSection(insight.keyWins)
                        focusAreasSection(insight.focusAreas)
                        recommendationsSection(insight.recommendations)
                        regenerateButton
                        disclaimerText
                        Spacer(minLength: FloatingTabBarMetrics.clearance)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
            } else {
                EmptyStateView(
                    icon: "brain.head.profile",
                    title: "No Insights Yet",
                    subtitle: "Generate your weekly recovery digest from the Progress tab"
                )
                .padding(.horizontal, AppSpacing.xl)
            }
        }
        .navigationTitle("Recovery Digest")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("RecoveryInsightsDetail")
    }

    // MARK: - Headline Section

    private func headlineSection(_ insight: RecoveryInsight) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(insight.headline)
                .font(.system(.title2, design: .serif).weight(.bold))
                .multilineTextAlignment(.center)

            Text(insight.summary)
                .font(AppFonts.body)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            if let date = formattedDate(insight.generatedDate) {
                Text("Generated \(date)")
                    .font(AppFonts.micro)
                    .foregroundColor(AppColors.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }

    // MARK: - Pain Analysis

    private func painAnalysisSection(_ analysis: RecoveryInsight.PainAnalysis) -> some View {
        CardSection(icon: "waveform.path.ecg", color: trendColor(analysis.trendDirection), title: "Pain Analysis") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Trend badge
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: trendIcon(analysis.trendDirection))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(AppColors.ctaText)
                        .frame(width: 28, height: 28)
                        .background(trendColor(analysis.trendDirection))
                        .clipShape(Circle())

                    Text("Pain \(analysis.trendDirection.capitalized)")
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(trendColor(analysis.trendDirection))

                    Spacer()

                    Text("Avg \(String(format: "%.1f", analysis.averagePain))/10")
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                }

                Text(analysis.trendDescription)
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)

                // Per-region breakdown
                if let regions = analysis.regionBreakdown, !regions.isEmpty {
                    Divider()
                    ForEach(regions, id: \.region) { region in
                        HStack {
                            Text(RegionPainInputView.displayName(for: region.region))
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            Image(systemName: trendIcon(region.trend))
                                .font(.caption2.weight(.bold))
                                .foregroundColor(trendColor(region.trend))
                            Text(String(format: "%.1f", region.averagePain))
                                .font(AppFonts.captionSemiBold)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Adherence

    private func adherenceSection(_ adherence: RecoveryInsight.AdherenceAnalysis) -> some View {
        CardSection(icon: "checkmark.circle", color: adherenceColor(adherence.score), title: "Workout Adherence") {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack {
                    Text("\(adherence.score)")
                        .font(AppFonts.display)
                        .foregroundColor(adherenceColor(adherence.score))
                    Text("/ 100")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    VStack(alignment: .trailing, spacing: AppSpacing.nano) {
                        Text("\(adherence.sessionsCompleted) of \(adherence.sessionsExpected)")
                            .font(AppFonts.captionSemiBold)
                        Text("sessions")
                            .font(AppFonts.micro)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColors.mutedText.opacity(0.15))
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(adherenceColor(adherence.score))
                            .frame(width: geometry.size.width * min(CGFloat(adherence.score) / 100.0, 1.0), height: 8)
                    }
                }
                .frame(height: 8)

                Text(adherence.description)
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
    }

    // MARK: - Key Wins

    private func keyWinsSection(_ wins: [String]) -> some View {
        CardSection(icon: "star.fill", color: AppColors.success, title: "Key Wins") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(wins, id: \.self) { win in
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.success)
                            .padding(.top, AppSpacing.nano)
                        Text(win)
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
            }
        }
    }

    // MARK: - Focus Areas

    private func focusAreasSection(_ areas: [String]) -> some View {
        CardSection(icon: "target", color: AppColors.warning, title: "Areas to Focus") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(areas, id: \.self) { area in
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.warning)
                            .padding(.top, AppSpacing.nano)
                        Text(area)
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.primaryText)
                    }
                }
            }
        }
    }

    // MARK: - Recommendations

    private func recommendationsSection(_ recommendations: [RecoveryInsight.Recommendation]) -> some View {
        CardSection(icon: "lightbulb.fill", color: AppColors.accent, title: "Recommendations") {
            VStack(spacing: AppSpacing.md) {
                ForEach(recommendations, id: \.title) { rec in
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Image(systemName: rec.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(AppColors.accent)
                            .frame(width: 32, height: 32)
                            .background(AppColors.accentTint)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(rec.title)
                                .font(AppFonts.bodySemiBold)
                                .foregroundColor(AppColors.primaryText)
                            Text(rec.description)
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Regenerate

    private var regenerateButton: some View {
        Button(action: {
            Task {
                await vm.generateInsights(
                    sessions: workoutViewModel.sessions,
                    plans: savedPlansViewModel.rehabPlans,
                    profile: UserProfileService.shared.profile,
                    forceRegenerate: true
                )
            }
        }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.clockwise")
                Text("Regenerate Insights")
            }
            .font(AppFonts.bodyMedium)
            .foregroundColor(AppColors.accentText)
        }
        .disabled(vm.isLoading)
        .padding(.top, AppSpacing.sm)
    }

    // MARK: - Disclaimer

    private var disclaimerText: some View {
        Text("These insights are educational only and not a substitute for professional medical advice. Always consult your healthcare provider about your recovery.")
            .font(AppFonts.micro)
            .foregroundColor(AppColors.mutedText)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
