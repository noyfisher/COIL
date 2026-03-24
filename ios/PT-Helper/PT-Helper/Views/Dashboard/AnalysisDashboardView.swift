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

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(spacing: AppSpacing.md) {
            DashSectionHeader(title: "Quick Actions")

            NavigationLink(destination: BodyMap3DView()) {
                DashActionButton(
                    icon: "figure.run.circle",
                    title: "New Analysis",
                    subtitle: "Analyze a new injury or pain"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.newAnalysisButton")

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

    // MARK: - Empty State

    private var emptyView: some View {
        VStack {
            Spacer()
            greetingHeader
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)

            DashEmptyStateView(
                icon: "figure.run.circle",
                title: "No Analysis Yet",
                subtitle: "Start by selecting where you feel pain on the 3D body map",
                actionTitle: "Start Analysis"
            ) {
                navigateToBodyMap = true
            }
            .padding(.horizontal, AppSpacing.xl)
            Spacer()
        }
        .navigationDestination(isPresented: $navigateToBodyMap) {
            BodyMap3DView()
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
