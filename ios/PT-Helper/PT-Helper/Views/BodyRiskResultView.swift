import SwiftUI

/// Displays the AI-generated body risk assessment result with region cards and a CTA to build a prevention plan.
struct BodyRiskResultView: View {
    let result: BodyRiskResult
    let profile: UserProfile
    @ObservedObject var vm: BodyRiskViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var navigateToPlan = false
    @State private var showReassessConfirm = false

    private var preselectedGoals: Set<GoalCategory> {
        var goals: Set<GoalCategory> = []
        for region in result.riskRegions {
            goals.formUnion(Self.goalsForRegion(region.regionName))
        }
        return goals
    }

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    headerSection
                    riskRegionsSection
                    interpretationSection
                    actionSection
                }
                .padding(AppSpacing.lg)
                .padding(.bottom, AppSpacing.xxxl)
            }
        }
        .navigationTitle("Your Risk Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reassess") {
                    showReassessConfirm = true
                }
                .font(.subheadline)
                .foregroundColor(AppColors.accent)
            }
        }
        .confirmationDialog("Start a new risk assessment? Your current results will be replaced.", isPresented: $showReassessConfirm, titleVisibility: .visible) {
            Button("Reassess", role: .destructive) {
                vm.reset()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationDestination(isPresented: $navigateToPlan) {
            WellnessGoalPickerView(userProfile: profile, preselectedCategories: preselectedGoals)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "leaf.fill")
                    .foregroundColor(AppColors.accent)
                Text("Assessment Complete")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.accent)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)
            .background(AppColors.accentTint)
            .cornerRadius(AppCorners.pill)

            Text("We found \(result.riskRegions.count) area\(result.riskRegions.count == 1 ? "" : "s") to watch")
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.primaryText)

            Text(formattedDate(result.generatedDate))
                .font(.caption)
                .foregroundColor(AppColors.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Risk Regions

    private var riskRegionsSection: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(result.riskRegions) { region in
                riskRegionCard(region)
            }
        }
    }

    private func riskRegionCard(_ region: RiskRegion) -> some View {
        HStack(spacing: 0) {
            // Left risk-level color bar
            Rectangle()
                .fill(riskLevelColor(region.riskLevel))
                .frame(width: 4)
                .cornerRadius(AppCorners.small)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .center) {
                    Text(region.regionName)
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    riskBadge(region.riskLevel)
                }
                Text(region.rationale)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppSpacing.md)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 2)
        .accessibilityIdentifier("prevention.riskRegionCard")
    }

    private func riskBadge(_ level: RiskLevel) -> some View {
        Text(level.shortName)
            .font(.caption.weight(.semibold))
            .foregroundColor(riskLevelColor(level))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 4)
            .background(riskLevelColor(level).opacity(0.12))
            .cornerRadius(AppCorners.pill)
    }

    private func riskLevelColor(_ level: RiskLevel) -> Color {
        switch level {
        case .low: return AppColors.success
        case .moderate: return AppColors.warning
        case .elevated: return AppColors.danger
        }
    }

    // MARK: - Interpretation

    private var interpretationSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(AppColors.accent)
                Text("What This Means")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
            }
            Text("This is not a diagnosis — it's a proactive snapshot of areas that could benefit from targeted movement and habit changes. Elevated risk means now is a great time to start prevention, not that something is already wrong.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
        }
        .padding(AppSpacing.md)
        .background(AppColors.accentTint)
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Action

    private var actionSection: some View {
        VStack(spacing: AppSpacing.md) {
            Button {
                navigateToPlan = true
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "sparkles")
                    Text("Build Prevention Plan")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(AppSpacing.lg)
                .background(AppColors.ctaBackground)
                .foregroundColor(AppColors.ctaText)
                .cornerRadius(AppCorners.large)
            }

            Text("We'll pre-select goals based on your risk areas. You can adjust before generating your plan.")
                .font(.caption)
                .foregroundColor(AppColors.mutedText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Assessed \(formatter.string(from: date))"
    }

    // MARK: - Region → Goal Mapping

    static func goalsForRegion(_ regionName: String) -> [GoalCategory] {
        let lower = regionName.lowercased()
        if lower.contains("lower back") || lower.contains("lumbar") {
            return [.improvePosture, .coreAndBalance, .reduceMorningStiffness]
        } else if lower.contains("neck") || lower.contains("cervical") {
            return [.improvePosture]
        } else if lower.contains("shoulder") {
            return [.improvePosture, .flexibilityAndMobility]
        } else if lower.contains("hip") {
            return [.flexibilityAndMobility, .coreAndBalance, .standLonger]
        } else if lower.contains("knee") {
            return [.sitWithoutPain, .standLonger]
        } else if lower.contains("ankle") || lower.contains("foot") {
            return [.flexibilityAndMobility, .standLonger]
        } else if lower.contains("wrist") || lower.contains("elbow") {
            return [.workWithEquipment]
        } else if lower.contains("core") || lower.contains("abdomen") {
            return [.coreAndBalance]
        } else if lower.contains("upper back") || lower.contains("thoracic") {
            return [.improvePosture, .flexibilityAndMobility]
        } else {
            return [.flexibilityAndMobility]
        }
    }
}
