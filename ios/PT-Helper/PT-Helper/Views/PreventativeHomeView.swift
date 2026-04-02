import SwiftUI

/// The "Prevent" tab — entry point for the proactive prevention side of PT Helper.
struct PreventativeHomeView: View {
    @StateObject private var vm = BodyRiskViewModel()
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @ObservedObject private var streakVM = PreventativeStreakViewModel.shared
    @ObservedObject private var profileService = UserProfileService.shared
    @State private var showMilestoneCelebration = false

    private var profile: UserProfile? {
        profileService.profile
    }

    /// Wellness goal names derived from saved wellness plans — used to seed the snack card.
    private var wellnessGoals: [String] {
        savedPlansVM.rehabPlans
            .filter { $0.planType == .wellness }
            .map(\.planName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bgGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Risk Assessment — entry or result summary
                        if vm.result != nil {
                            resultSummaryCard
                        } else {
                            heroEntryCard
                        }

                        // Daily Movement Snack (live feature)
                        if profile != nil {
                            movementSnackSection
                        }

                        // Preventative Streak (live feature)
                        streakSection

                        // Posture Check-In
                        postureCheckSection

                        // Coming-soon features
                        comingSoonSection
                    }
                    .padding(AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xxxl)
                }
            }
            .navigationTitle("Prevent")
            .navigationBarTitleDisplayMode(.large)
        }
        .trackScreen("PreventativeHome")
        .sheet(isPresented: $showMilestoneCelebration) {
            if let milestone = streakVM.newMilestone {
                PreventativeStreakView.MilestoneCelebrationSheet(achievement: milestone)
                    .onDisappear { streakVM.clearNewMilestone() }
            }
        }
        .onChange(of: streakVM.newMilestone?.id) { _, id in
            if id != nil { showMilestoneCelebration = true }
        }
    }

    // MARK: - Hero Entry Card

    private var heroEntryCard: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 88, height: 88)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.accent)
            }

            VStack(spacing: AppSpacing.sm) {
                Text("Stay Ahead of Pain")
                    .font(AppFonts.sectionTitle)
                    .foregroundColor(AppColors.primaryText)
                Text("Discover which areas of your body are most at risk — and start building habits before problems develop.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let profile {
                NavigationLink {
                    BodyRiskAssessmentView(vm: vm, profile: profile)
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "magnifyingglass.circle.fill")
                        Text("Start Risk Assessment")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.lg)
                    .background(AppColors.ctaBackground)
                    .foregroundColor(AppColors.ctaText)
                    .cornerRadius(AppCorners.large)
                }
                .accessibilityIdentifier("prevention.startRiskAssessmentButton")
            } else {
                ProgressView()
                    .tint(AppColors.accent)
            }
        }
        .padding(AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 6, x: 0, y: 3)
    }

    // MARK: - Result Summary Card

    @ViewBuilder
    private var resultSummaryCard: some View {
        if let result = vm.result {
            VStack(spacing: AppSpacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Your Risk Profile")
                            .font(AppFonts.sectionTitle)
                            .foregroundColor(AppColors.primaryText)
                        Text(formattedDate(result.generatedDate))
                            .font(.caption)
                            .foregroundColor(AppColors.mutedText)
                    }
                    Spacer()
                    if let profile {
                        NavigationLink {
                            BodyRiskResultView(result: result, profile: profile, vm: vm)
                        } label: {
                            Text("View Report")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }

                VStack(spacing: AppSpacing.sm) {
                    ForEach(result.riskRegions) { region in
                        HStack(spacing: AppSpacing.md) {
                            Circle()
                                .fill(riskLevelColor(region.riskLevel))
                                .frame(width: 8, height: 8)
                            Text(region.regionName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(AppColors.primaryText)
                            Spacer()
                            riskBadge(region.riskLevel)
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(AppColors.elevatedSurface.opacity(0.5))
                        .cornerRadius(AppCorners.medium)
                    }
                }

                Button {
                    vm.reset()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                        Text("Reassess")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.elevatedSurface)
                    .cornerRadius(AppCorners.pill)
                }
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .shadow(color: AppColors.cardShadowColor, radius: 6, x: 0, y: 3)
        }
    }

    // MARK: - Movement Snack Section

    private var movementSnackSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(title: "Today's Movement")
            DailyMovementSnackCard(wellnessGoals: wellnessGoals)
        }
    }

    // MARK: - Streak Section

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(title: "Prevention Streak")
            PreventativeStreakView()
        }
    }

    private func sectionHeader(title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(AppColors.mutedText)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Coming Soon Section

    // MARK: - Posture Check Section

    private var postureCheckSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(title: "Posture Check-In")

            NavigationLink(destination: PostureCheckView()) {
                HStack(spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accentTint)
                            .frame(width: 52, height: 52)
                        Image(systemName: "person.fill.viewfinder")
                            .font(.system(size: 22))
                            .foregroundColor(AppColors.accent)
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Check My Posture")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.primaryText)
                        Text("Take a quick photo for AI-powered alignment feedback")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(AppSpacing.md)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prevention.postureCheckButton")
        }
    }

    private var comingSoonSection: some View {
        EmptyView()
    }

    private func comingSoonCard(icon: String, title: String, description: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(AppColors.elevatedSurface)
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.mutedText)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.secondaryText)
                    Text("Soon")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.mutedText)
                        .padding(.horizontal, AppSpacing.xs)
                        .padding(.vertical, 2)
                        .background(AppColors.elevatedSurface)
                        .cornerRadius(AppCorners.small)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(AppColors.mutedText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground.opacity(0.6))
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.subtleBorder, lineWidth: 1))
    }

    // MARK: - Helpers

    private func riskBadge(_ level: RiskLevel) -> some View {
        Text(level.shortName)
            .font(.caption.weight(.semibold))
            .foregroundColor(riskLevelColor(level))
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 3)
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

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Assessed \(formatter.string(from: date))"
    }
}
