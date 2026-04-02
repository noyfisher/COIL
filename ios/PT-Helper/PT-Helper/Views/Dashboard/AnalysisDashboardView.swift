import SwiftUI

struct AnalysisDashboardView: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var analysisStore: AnalysisResultStore

    @ObservedObject private var streakService = StreakService.shared
    @ObservedObject private var profileService = UserProfileService.shared
    @ObservedObject private var preventativeStreakVM = PreventativeStreakViewModel.shared
    @ObservedObject private var weaknessAnalyzer = WeaknessPatternAnalyzer.shared

    @State private var animateEntrance = false
    @State private var navigateToBodyMap = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default: return "Good Evening"
        }
    }

    private var firstName: String {
        profileService.firstName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bgGradient.ignoresSafeArea()

                if let result = analysisStore.lastResult {
                    dataView(result: result)
                } else {
                    emptyView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Dashboard")
                        .font(.system(.headline, design: .serif))
                        .foregroundColor(AppColors.primaryText)
                }
            }
        }
        .onAppear {
            withAnimation(AppAnimations.smooth.delay(0.1)) {
                animateEntrance = true
            }
            // Run weakness analysis against current sessions
            weaknessAnalyzer.analyze(sessions: workoutVM.sessions)
        }
        .trackScreen("DashboardTab")
    }

    // MARK: - Data View

    private func dataView(result: AnalysisResult) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Greeting
                greetingHeader
                    .entranceAnimation(animateEntrance, delay: 0)

                // Widget Grid
                widgetGrid(result: result)
                    .entranceAnimation(animateEntrance, delay: 0.1)

                // Daily Movement Snack (when wellness plans exist)
                if !wellnessGoals.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        dashSectionLabel("Today's Movement")
                        DailyMovementSnackCard(wellnessGoals: wellnessGoals)
                    }
                    .entranceAnimation(animateEntrance, delay: 0.15)
                }

                // Preventative streak nudge (compact)
                if preventativeStreakVM.streak.currentStreak > 0 {
                    preventativeStreakNudge
                        .entranceAnimation(animateEntrance, delay: 0.18)
                }

                // Weakness insight card (when a blind spot is detected)
                if weaknessAnalyzer.topInsight != nil {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        dashSectionLabel("Movement Insights")
                        WeaknessInsightCard()
                    }
                    .entranceAnimation(animateEntrance, delay: 0.22)
                }

                // Confidence Chart
                DashConfidenceChart(conditions: result.conditions)
                    .entranceAnimation(animateEntrance, delay: 0.2)

                // Differentials Table
                DashDifferentialsTable(conditions: result.conditions)
                    .entranceAnimation(animateEntrance, delay: 0.3)

                // Quick Actions
                quickActions
                    .entranceAnimation(animateEntrance, delay: 0.4)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .refreshable {
            workoutVM.fetchSessions()
            savedPlansVM.fetchRehabPlans()
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("\(greeting), \(firstName)")
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundColor(AppColors.primaryText)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Widget Grid

    private func widgetGrid(result: AnalysisResult) -> some View {
        let topCondition = result.conditions.first
        let planCount = savedPlansVM.rehabPlans.count
        let streak = streakService.streakData.currentStreak

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md), GridItem(.flexible())], spacing: AppSpacing.md) {
            DashStatWidget(
                icon: "stethoscope",
                iconColor: AppColors.dashAccent,
                value: topCondition?.commonName ?? "—",
                label: "Top Match"
            )

            DashStatWidget(
                icon: "chart.bar.fill",
                iconColor: AppColors.dashAccent,
                value: topCondition.map { "\(Int($0.confidence))%" } ?? "—",
                label: "Confidence"
            )

            DashStatWidget(
                icon: "list.clipboard",
                iconColor: AppColors.dashSuccess,
                value: "\(planCount)",
                label: "Active Plans"
            )

            DashStatWidget(
                icon: "flame.fill",
                iconColor: streak > 0 ? AppColors.dashWarning : AppColors.dashTextSecondary,
                value: "\(streak)",
                label: "Day Streak"
            )
        }
    }

    // MARK: - Quick Actions (Gateway + Secondary)

    private var quickActions: some View {
        VStack(spacing: AppSpacing.md) {
            DashSectionHeader(title: "What Can We Help With?")

            // Gateway cards
            HStack(spacing: AppSpacing.md) {
                // "Something Hurts" gateway
                NavigationLink(destination: BodyMap3DView()) {
                    gatewayCard(
                        icon: "figure.run.circle",
                        title: "Something Hurts",
                        subtitle: "Assess pain and get a recovery plan",
                        accentColor: AppColors.danger
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.somethingHurtsButton")

                // "Improve My Life" gateway
                if let profile = profileService.profile {
                    NavigationLink(destination: WellnessGoalPickerView(userProfile: profile)) {
                        gatewayCard(
                            icon: "sparkles",
                            title: "Improve My Life",
                            subtitle: "Sleep, posture, mobility & more",
                            accentColor: AppColors.accent
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.improveLifeButton")
                }
            }

            // Secondary actions
            Button {
                tabSelection.selectedTab = 1
            } label: {
                DashActionButton(
                    icon: "video.badge.checkmark",
                    title: "Form Check",
                    subtitle: "Verify your exercise form with AI",
                    iconColor: AppColors.warning
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.formCheckButton")

            Button {
                tabSelection.selectedTab = 2
            } label: {
                DashActionButton(
                    icon: "heart.text.clipboard",
                    title: "View Rehab Plans",
                    subtitle: "See your active recovery plans",
                    iconColor: AppColors.success
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Wellness Goals (for snack card)

    private var wellnessGoals: [String] {
        savedPlansVM.rehabPlans
            .filter { $0.planType == .wellness }
            .map(\.planName)
    }

    // MARK: - Preventative Streak Nudge

    private var preventativeStreakNudge: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: preventativeStreakVM.streak.isActive ? "flame.fill" : "flame")
                .font(.system(size: 18))
                .foregroundColor(preventativeStreakVM.streak.isActive ? AppColors.warning : AppColors.mutedText)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(preventativeStreakVM.streak.currentStreak)-Day Prevention Streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                Text(preventativeStreakVM.streak.goalLabel)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            Button {
                tabSelection.selectedTab = 3 // Prevent tab
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card)
            .stroke(AppColors.subtleBorder, lineWidth: 1))
        .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)
    }

    private func dashSectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(AppColors.mutedText)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func gatewayCard(icon: String, title: String, subtitle: String, accentColor: Color) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(accentColor)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(accentColor.opacity(0.10))
                )

            Text(title)
                .font(.system(.subheadline, design: .serif).weight(.bold))
                .foregroundColor(AppColors.primaryText)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.sm)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Empty State

    @State private var navigateToWellness = false

    private var emptyView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            greetingHeader
                .padding(.horizontal, AppSpacing.xl)

            VStack(spacing: AppSpacing.lg) {
                Text("How can we help?")
                    .font(.system(.headline, design: .serif))
                    .foregroundColor(AppColors.primaryText)

                HStack(spacing: AppSpacing.md) {
                    // "Something Hurts" gateway
                    Button { navigateToBodyMap = true } label: {
                        gatewayCard(
                            icon: "figure.run.circle",
                            title: "Something Hurts",
                            subtitle: "Assess pain and get a recovery plan",
                            accentColor: AppColors.danger
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.somethingHurtsButton")

                    // "Improve My Life" gateway
                    Button { navigateToWellness = true } label: {
                        gatewayCard(
                            icon: "sparkles",
                            title: "Improve My Life",
                            subtitle: "Sleep, posture, mobility & more",
                            accentColor: AppColors.accent
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.improveLifeButton")
                }
            }
            .padding(.horizontal, AppSpacing.xl)

            Spacer()
        }
        .navigationDestination(isPresented: $navigateToBodyMap) {
            BodyMap3DView()
        }
        .navigationDestination(isPresented: $navigateToWellness) {
            if let profile = profileService.profile {
                WellnessGoalPickerView(userProfile: profile)
            }
        }
    }
}

// MARK: - Entrance Animation Helper

private struct EntranceAnimationModifier: ViewModifier {
    let isVisible: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .animation(AppAnimations.smooth.delay(delay), value: isVisible)
    }
}

extension View {
    func entranceAnimation(_ isVisible: Bool, delay: Double) -> some View {
        modifier(EntranceAnimationModifier(isVisible: isVisible, delay: delay))
    }
}
