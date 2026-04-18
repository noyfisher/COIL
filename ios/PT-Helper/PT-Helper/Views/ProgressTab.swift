import SwiftUI
import Charts

/// Tab 2: Progress — "How am I doing?"
/// Wraps progress content with settings access and re-assessment prompt.
struct ProgressTab: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var insightsVM: RecoveryInsightsViewModel
    @State private var showSettings = false
    @State private var showProfileEdit = false

    var body: some View {
        NavigationStack {
            ProgressTabContent(
                tabSelection: tabSelection,
                workoutViewModel: workoutViewModel,
                insightsVM: insightsVM,
                onSettingsTapped: { showSettings = true }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                userName: UserProfileService.shared.profile?.firstName ?? "User",
                onEditProfile: {
                    showSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showProfileEdit = true
                    }
                }
            )
        }
        .fullScreenCover(isPresented: $showProfileEdit) {
            OnboardingEditView()
        }
        .trackScreen("ProgressTab")
    }
}

/// Separate view to isolate complex view hierarchy from the outer NavigationStack + sheet modifiers,
/// preventing SwiftUI toolbar type inference issues.
struct ProgressTabContent: View {
    let tabSelection: TabSelection
    @ObservedObject var workoutViewModel: WorkoutViewModel
    @ObservedObject var insightsVM: RecoveryInsightsViewModel
    @ObservedObject private var streakService = StreakService.shared
    var onSettingsTapped: () -> Void

    @State private var selectedRegion: String? = nil
    @State private var sessionToDelete: WorkoutSession?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if workoutViewModel.sessions.isEmpty {
                    Spacer(minLength: 100)
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No Data Yet",
                        subtitle: "Complete workout sessions to see your progress over time"
                    )
                    Spacer(minLength: 100)
                } else {
                    // Region filter picker
                    regionFilterPicker

                    // Pain trend chart
                    painTrendChart

                    // Summary stats + streak
                    summaryStats

                    // AI Recovery Insights
                    RecoveryInsightsCardView(vm: insightsVM)

                    // Recent Workouts
                    recentWorkoutsSection
                }

                // Log Workout card
                NavigationLink(destination: WorkoutSessionView()) {
                    navLinkRow(icon: "figure.strengthtraining.traditional",
                               iconColor: .purple,
                               title: "Log Workout")
                }
                .buttonStyle(.plain)

                // Re-assessment prompt
                reassessmentCard

                // Notes link
                NavigationLink(destination: NotesView()) {
                    navLinkRow(icon: "note.text",
                               iconColor: AppColors.accent,
                               title: "Recovery Notes")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .background(AppColors.pageBackground)
        .alert("Delete Session", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                sessionToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    withAnimation {
                        workoutViewModel.deleteSession(session)
                    }
                    sessionToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this workout session? This cannot be undone.")
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: AppSpacing.sm) {
                    NavigationLink(destination: AchievementsView(streakService: streakService)) {
                        StreakToolbarBadge(streakService: streakService)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress.streakBadge")

                    Button(action: onSettingsTapped) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(AppColors.accent)
                    }
                    .accessibilityIdentifier("progress.settingsButton")
                }
            }
        }
    }

    // MARK: - Navigation Link Row

    private func navLinkRow(icon: String, iconColor: Color, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(AppColors.mutedText)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Recent Workouts

    private var recentWorkouts: [WorkoutSession] {
        Array(workoutViewModel.sessions.prefix(10))
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(AppColors.accent)
                    .font(.system(size: 16, weight: .semibold))
                Text("Recent Workouts")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                if workoutViewModel.sessions.count > 10 {
                    NavigationLink(destination: WorkoutSessionView()) {
                        Text("See All")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.accent)
                    }
                }
            }

            ForEach(recentWorkouts, id: \.id) { session in
                workoutSessionRow(session)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(role: .destructive) {
                            sessionToDelete = session
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
    }

    private func workoutSessionRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(painColor(for: session.painLevel).opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("\(Int(session.painLevel))")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(painColor(for: session.painLevel))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.date, style: .date)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.primaryText)
                Text("\(Int(session.duration / 60)) min")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            if !session.exercisesPerformed.isEmpty {
                Text("\(session.exercisesPerformed.count) exercises")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Button {
                sessionToDelete = session
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.danger.opacity(0.6))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete session")
            .accessibilityIdentifier("progress.deleteSession")
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func painColor(for level: Double) -> Color {
        switch Int(level) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    // MARK: - Region Filter

    private var regionFilterPicker: some View {
        let regions = availableRegions
        if regions.isEmpty {
            return AnyView(EmptyView())
        }
        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    filterChip(label: "Overall", isSelected: selectedRegion == nil) {
                        selectedRegion = nil
                    }
                    ForEach(regions, id: \.self) { region in
                        filterChip(
                            label: RegionPainInputView.displayName(for: region),
                            isSelected: selectedRegion == region
                        ) {
                            selectedRegion = region
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
            }
        )
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? AppColors.accent : Color(.systemGray5))
                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
                .cornerRadius(AppCorners.medium)
        }
    }

    private var availableRegions: [String] {
        var regions = Set<String>()
        for session in workoutViewModel.sessions {
            if let regionPain = session.regionPainLevels {
                regions.formUnion(regionPain.keys)
            }
        }
        return regions.sorted()
    }

    // MARK: - Pain Trend Chart

    private var painTrendChart: some View {
        let chartTitle = selectedRegion != nil
            ? "\(RegionPainInputView.displayName(for: selectedRegion!)) Pain"
            : "Pain Trend"

        return CardSection(icon: "chart.line.uptrend.xyaxis", color: AppColors.accent, title: chartTitle) {
            Chart(filteredChartData, id: \.id) { session in
                let painValue = painValueForChart(session)
                LineMark(
                    x: .value("Date", session.date),
                    y: .value("Pain", painValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accent.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                AreaMark(
                    x: .value("Date", session.date),
                    y: .value("Pain", painValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.2), AppColors.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                PointMark(
                    x: .value("Date", session.date),
                    y: .value("Pain", painValue)
                )
                .foregroundStyle(AppColors.accent)
                .symbolSize(30)
            }
            .chartYScale(domain: 0...10)
            .chartYAxis {
                AxisMarks(values: [0, 2, 4, 6, 8, 10]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(AppColors.mutedText.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
        }
    }

    private var filteredChartData: [WorkoutSession] {
        guard let region = selectedRegion else {
            return workoutViewModel.sessions
        }
        return workoutViewModel.sessions.filter { $0.regionPainLevels?[region] != nil }
    }

    private func painValueForChart(_ session: WorkoutSession) -> Double {
        if let region = selectedRegion, let regionPain = session.regionPainLevels?[region] {
            return regionPain
        }
        return session.painLevel
    }

    // MARK: - Summary Stats

    private var summaryStats: some View {
        HStack(spacing: AppSpacing.md) {
            statCard(
                icon: "number",
                color: AppColors.accent,
                value: "\(workoutViewModel.sessions.count)",
                label: "Sessions"
            )

            statCard(
                icon: "waveform.path.ecg",
                color: averagePainColor,
                value: String(format: "%.1f", averagePain),
                label: "Avg Pain"
            )

            statCard(
                icon: "clock",
                color: AppColors.warning,
                value: "\(totalMinutes)",
                label: "Total Min"
            )
        }
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .cornerRadius(AppCorners.small)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)

            Text(label)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Computed Properties

    private var averagePain: Double {
        guard !workoutViewModel.sessions.isEmpty else { return 0 }
        let total = workoutViewModel.sessions.reduce(0.0) { $0 + $1.painLevel }
        return total / Double(workoutViewModel.sessions.count)
    }

    private var averagePainColor: Color {
        switch Int(averagePain) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    private var totalMinutes: Int {
        Int(workoutViewModel.sessions.reduce(0.0) { $0 + $1.duration } / 60)
    }

    // MARK: - Re-Assessment Card

    private var reassessmentCard: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(AppColors.accent)
                    .font(.system(size: 16, weight: .semibold))
                Text("Time for a Re-Assessment?")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
            }

            Text("Check in on your progress and see how your condition has changed.")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            Button {
                tabSelection.selectedTab = 0
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("Re-Assess Now")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(AppColors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCorners.large)
                        .stroke(AppColors.accent, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.reassessButton")
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Streak Toolbar Badge

/// Compact streak indicator for the toolbar — shows flame icon + count inline.
private struct StreakToolbarBadge: View {
    @ObservedObject var streakService: StreakService

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: streakService.streakData.isActive ? "flame.fill" : "flame")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(streakColor)
            Text("\(streakService.streakData.currentStreak)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(streakColor)
        }
    }

    private var streakColor: Color {
        switch streakService.streakData.currentStreak {
        case 0: return AppColors.secondaryText
        case 1...6: return AppColors.warning
        case 7...29: return AppColors.danger
        default: return AppColors.accent
        }
    }
}
