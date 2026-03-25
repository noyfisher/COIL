import SwiftUI

struct AnalysisDashboardView: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var analysisStore: AnalysisResultStore

    @ObservedObject private var streakService = StreakService.shared
    @ObservedObject private var profileService = UserProfileService.shared

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
                AppColors.dashBackground.ignoresSafeArea()

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
                        .font(.headline)
                        .foregroundColor(AppColors.dashTextPrimary)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .onAppear {
            withAnimation(AppAnimations.smooth.delay(0.1)) {
                animateEntrance = true
            }
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
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.dashTextPrimary)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundColor(AppColors.dashTextSecondary)
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
                        gradientColors: [.red, .orange]
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
                            gradientColors: [.teal, .green]
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("dashboard.improveLifeButton")
                }
            }

            // Secondary actions
            NavigationLink(destination: FormCheckTab()) {
                DashActionButton(
                    icon: "video.badge.checkmark",
                    title: "Form Check",
                    subtitle: "Verify your exercise form with AI",
                    iconColor: AppColors.dashWarning
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.formCheckButton")

            Button {
                tabSelection.selectedTab = 1
            } label: {
                DashActionButton(
                    icon: "heart.text.clipboard",
                    title: "View Rehab Plans",
                    subtitle: "See your active recovery plans",
                    iconColor: AppColors.dashSuccess
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func gatewayCard(icon: String, title: String, subtitle: String, gradientColors: [Color]) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(
                    LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(gradientColors[0].opacity(0.15))
                )

            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundColor(AppColors.dashTextPrimary)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(AppColors.dashTextSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.sm)
        .background(AppColors.dashSurface)
        .cornerRadius(AppCorners.card)
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
                    .font(.headline)
                    .foregroundColor(AppColors.dashTextPrimary)

                HStack(spacing: AppSpacing.md) {
                    // "Something Hurts" gateway
                    Button { navigateToBodyMap = true } label: {
                        gatewayCard(
                            icon: "figure.run.circle",
                            title: "Something Hurts",
                            subtitle: "Assess pain and get a recovery plan",
                            gradientColors: [.red, .orange]
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
                            gradientColors: [.teal, .green]
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
