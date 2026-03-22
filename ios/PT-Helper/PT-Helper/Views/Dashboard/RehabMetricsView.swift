import SwiftUI

struct RehabMetricsView: View {
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutVM: WorkoutViewModel
    @EnvironmentObject private var insightsVM: RecoveryInsightsViewModel

    @ObservedObject private var streakService = StreakService.shared

    @State private var animateEntrance = false

    // MARK: - Computed Metrics

    private var adherenceScore: Int {
        insightsVM.insight?.adherenceAnalysis.score ?? computedAdherence
    }

    private var computedAdherence: Int {
        let recentSessions = workoutVM.sessions.filter {
            $0.date >= Calendar.current.date(byAdding: .day, value: -RecoveryInsightsViewModel.lookbackDays, to: Date()) ?? Date()
        }
        guard !recentSessions.isEmpty else { return 0 }
        // Derive expected sessions from plan schedules (2 weeks worth), fall back to 5
        let weeklyExpected = savedPlansVM.rehabPlans.reduce(0) { sum, plan in
            sum + plan.weeklySchedule.filter { !$0.isEmpty }.count
        }
        let target = Double(weeklyExpected > 0 ? weeklyExpected * 2 : 5)
        return min(Int(Double(recentSessions.count) / target * 100), 100)
    }

    private var avgPain: Double {
        let recent = workoutVM.sessions.filter {
            $0.date >= Calendar.current.date(byAdding: .day, value: -RecoveryInsightsViewModel.lookbackDays, to: Date()) ?? Date()
        }
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.painLevel } / Double(recent.count)
    }

    private var painTrendIcon: String {
        guard let trend = insightsVM.insight?.painAnalysis.trendDirection else { return "minus" }
        switch trend {
        case "improving": return "arrow.down.right"
        case "worsening": return "arrow.up.right"
        default: return "minus"
        }
    }

    private var planProgress: String {
        guard let plan = savedPlansVM.rehabPlans.first,
              let week = plan.currentWeek,
              plan.totalWeeks > 0 else { return "—" }
        return "Wk \(week)/\(plan.totalWeeks)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.dashBackground.ignoresSafeArea()

                if workoutVM.sessions.isEmpty && savedPlansVM.rehabPlans.isEmpty {
                    DashEmptyStateView(
                        icon: "heart.text.clipboard",
                        title: "No Rehab Data",
                        subtitle: "Complete an analysis and start a workout to see your rehab metrics"
                    )
                    .padding(.horizontal, AppSpacing.xl)
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.lg) {
                            // Metrics Grid
                            metricsGrid
                                .entranceAnimation(animateEntrance, delay: 0)

                            // Pain Chart
                            DashPainTrendChart(sessions: workoutVM.sessions)
                                .entranceAnimation(animateEntrance, delay: 0.1)

                            // Plans
                            DashActivePlansList(plans: savedPlansVM.rehabPlans)
                                .entranceAnimation(animateEntrance, delay: 0.2)

                            // Exercise table
                            DashExercisePerformanceTable(sessions: workoutVM.sessions)
                                .entranceAnimation(animateEntrance, delay: 0.3)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                    }
                    .refreshable {
                        workoutVM.fetchSessions()
                        savedPlansVM.fetchRehabPlans()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Rehab")
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
        .trackScreen("RehabMetrics")
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: AppSpacing.md), GridItem(.flexible())], spacing: AppSpacing.md) {
            DashStatWidget(
                icon: "checkmark.circle.fill",
                iconColor: AppColors.dashSuccess,
                value: "\(adherenceScore)%",
                label: "Adherence"
            )

            DashStatWidget(
                icon: painTrendIcon,
                iconColor: avgPain < 4 ? AppColors.dashSuccess : (avgPain < 7 ? AppColors.dashWarning : AppColors.dashDanger),
                value: String(format: "%.1f", avgPain),
                label: "Avg Pain"
            )

            DashStatWidget(
                icon: "flame.fill",
                iconColor: streakService.streakData.currentStreak > 0 ? AppColors.dashWarning : AppColors.dashTextSecondary,
                value: "\(streakService.streakData.currentStreak)",
                label: "Day Streak"
            )

            DashStatWidget(
                icon: "chart.pie.fill",
                iconColor: AppColors.dashAccent,
                value: planProgress,
                label: "Plan Progress"
            )
        }
    }
}
