import SwiftUI
import Charts

/// Tab 2: Progress — "How am I doing?"
/// Wraps progress content with settings access and re-assessment prompt.
struct ProgressTab: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var insightsVM: RecoveryInsightsViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @State private var showSettings = false
    @State private var showProfileEdit = false

    var body: some View {
        NavigationStack {
            ProgressTabContent(
                tabSelection: tabSelection,
                workoutViewModel: workoutViewModel,
                insightsVM: insightsVM,
                savedPlansVM: savedPlansVM,
                onSettingsTapped: { showSettings = true }
            )
            .mvvcNavBar()
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
    @ObservedObject var savedPlansVM: SavedPlansViewModel
    @ObservedObject private var streakService = StreakService.shared
    var onSettingsTapped: () -> Void

    @State private var selectedRegion: String? = nil
    @State private var sessionToDelete: WorkoutSession?
    @State private var showDeleteConfirmation = false

    /// Tier 3 PR D + followup: outcome-prompt visibility. Re-evaluated on
    /// every render — when the user submits or dismisses the prompt,
    /// `OutcomePromptView` calls our `onComplete` which bumps this counter
    /// to force re-evaluation of `OutcomeRecorder.shouldShowPrompt`.
    @State private var outcomePromptRefreshTick: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if let loadError = workoutViewModel.loadError {
                    // A fetch failure must not masquerade as "No Data Yet" — that's
                    // the brand-new-user message and makes a longtime user fear their
                    // data vanished (audit #62).
                    Spacer(minLength: 100)
                    ErrorStateView(
                        title: "Couldn't load your progress",
                        message: loadError,
                        onRetry: { workoutViewModel.fetchSessions() }
                    )
                    Spacer(minLength: 100)
                } else if workoutViewModel.sessions.isEmpty {
                    Spacer(minLength: 100)
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No Data Yet",
                        subtitle: "Complete workout sessions to see your progress over time",
                        actionTitle: "Start an Assessment",
                        action: { tabSelection.assessmentRequest = .gateway }
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

                    // Tier 3 PR D: outcome rating prompt — surfaces ≥7 days
                    // after a plan starts, asks the user how accurate the
                    // original AI analysis turned out to be. Hidden when
                    // either no eligible plan exists or the rating's
                    // already in. Re-renders on outcomePromptRefreshTick.
                    if let target = outcomePromptTarget {
                        OutcomePromptView(
                            analysisId: target.analysisId,
                            planId: target.plan.id,
                            planAgeDays: OutcomeRecorder.planAgeDays(planStartDate: target.plan.startDate)
                        ) {
                            outcomePromptRefreshTick &+= 1
                        }
                        .id(outcomePromptRefreshTick)
                    }

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
            .floatingTabBarClearance()
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Outcome Prompt (Tier 3 PR D)

    /// Target plan + analysisId for the outcome prompt. Returns nil when
    /// no plan is eligible (no started plan, or all started plans already
    /// rated). Picks the OLDEST eligible plan so a user with several
    /// active plans gets asked about the most-experienced one first.
    ///
    /// `RehabPlan` doesn't carry a separate analysisId, so we use plan.id
    /// as the rating identity — one rating per plan, deduped by the
    /// `OutcomeRecorder` UserDefaults set.
    private var outcomePromptTarget: (plan: RehabPlan, analysisId: UUID)? {
        // Outcome rating only makes sense for started plans the user has
        // actually been on for ≥ minimumPlanAgeDays (default 7).
        let eligible = savedPlansVM.rehabPlans
            .filter { plan in
                OutcomeRecorder.shared.shouldShowPrompt(
                    planStartDate: plan.startDate,
                    analysisId: plan.id
                )
            }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        guard let oldest = eligible.first else { return nil }
        return (plan: oldest, analysisId: oldest.id)
    }

    // MARK: - Navigation Link Row

    private func navLinkRow(icon: String, iconColor: Color, title: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12))
                .cornerRadius(AppCorners.small)
            Text(title)
                .font(AppFonts.bodySemiBold)
                .foregroundColor(AppColors.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.mutedText)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Recent Workouts

    private var recentWorkouts: [WorkoutSession] {
        Array(workoutViewModel.sessions.prefix(10))
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                MVVCDividerHeader(title: "Recent Workouts")
                Spacer()
                if workoutViewModel.sessions.count > 10 {
                    NavigationLink(destination: WorkoutSessionView()) {
                        Text("See All")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.accent)
                    }
                }
            }

            VStack(spacing: 0) {
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
            .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        }
    }

    private func workoutSessionRow(_ session: WorkoutSession) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Combine the pieces into one spoken element so VoiceOver reads a
            // contextualized "June 12, pain 4 of 10 (moderate), 30 minutes,
            // 5 exercises" instead of a floating color-coded "4" (audit #69).
            HStack(spacing: AppSpacing.md) {
                Circle()
                    .fill(painColor(for: session.painLevel).opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text("\(Int(session.painLevel))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(painColor(for: session.painLevel))
                    )

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text(session.date, style: .date)
                        .font(AppFonts.bodyMedium)
                        .foregroundColor(AppColors.primaryText)
                    Text("\(Int(session.duration / 60)) min")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                if !session.exercisesPerformed.isEmpty {
                    Text("\(session.exercisesPerformed.count) exercises")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(sessionAccessibilityLabel(session))

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

    private var painTrendAccessibilityValue: String {
        let data = filteredChartData
        guard data.count >= 2, let first = data.first, let last = data.last else {
            return "Not enough data yet to show a trend."
        }
        let firstPain = Int(painValueForChart(first))
        let lastPain = Int(painValueForChart(last))
        let direction = lastPain < firstPain ? "down" : (lastPain > firstPain ? "up" : "steady")
        return "Pain trended \(direction), from \(firstPain) to \(lastPain) out of 10 over the last \(data.count) sessions."
    }

    private func sessionAccessibilityLabel(_ session: WorkoutSession) -> String {
        let dateStr = session.date.formatted(date: .abbreviated, time: .omitted)
        let pain = Int(session.painLevel)
        let severity: String
        switch pain {
        case 0...3: severity = "mild"
        case 4...6: severity = "moderate"
        default: severity = "severe"
        }
        let mins = Int(session.duration / 60)
        let count = session.exercisesPerformed.count
        let exercises = count == 1 ? "1 exercise" : "\(count) exercises"
        return "\(dateStr), pain \(pain) of 10 (\(severity)), \(mins) minutes, \(exercises)"
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
                .font(AppFonts.captionMedium)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? AppColors.accent : AppColors.elevatedSurface)
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

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            MVVCDividerHeader(title: chartTitle)
            cardChartContent
        }
    }

    private var cardChartContent: some View {
        VStack(spacing: 0) {
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
            // The pain-over-time story was conveyed only by pixels — give VoiceOver
            // a spoken summary of the trend (audit #66).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pain trend chart")
            .accessibilityValue(painTrendAccessibilityValue)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
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
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                statCard(icon: "number",            color: AppColors.accent,      value: "\(workoutViewModel.sessions.count)",     label: "Sessions")
                statCard(icon: "waveform.path.ecg", color: averagePainColor,      value: String(format: "%.1f", averagePain),      label: "Avg Pain")
                // Promote the day streak — the number users actually build toward —
                // over "Total Min", which nobody opens the app to check (audit #38).
                statCard(icon: streakService.streakData.isActive ? "flame.fill" : "flame",
                         color: .orange,
                         value: "\(streakService.streakData.currentStreak)",
                         label: "Day Streak")
            }
            if let personalBest = personalBestText {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "rosette")
                        .foregroundColor(.orange)
                    Text(personalBest)
                        .font(AppFonts.captionMedium)
                        .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(AppCorners.medium)
            }
        }
    }

    /// Surfaces the personal-best (longest) streak as a callout when the current
    /// streak matches or nears the record (audit #38).
    private var personalBestText: String? {
        let cur = streakService.streakData.currentStreak
        let best = streakService.streakData.longestStreak
        guard best >= 2 else { return nil }
        if cur >= best {
            return "Personal best streak — \(best) days! Keep it going."
        } else if cur >= best - 1 {
            return "1 day from your personal best of \(best) days."
        }
        return "Personal best streak: \(best) days."
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .cornerRadius(AppCorners.small)

            Text(value)
                .font(Font.custom("Industry-Bold", size: 26))
                .foregroundColor(AppColors.primaryText)

            Text(label)
                .font(AppFonts.micro)
                .foregroundColor(AppColors.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
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
                    .font(Font.custom("Industry-Bold", size: 16))
                    .foregroundColor(AppColors.primaryText)
                Spacer()
            }

            Text("Check in on your progress and see how your condition has changed.")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                tabSelection.assessmentRequest = .gateway
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("Re-Assess Now")
                        .font(AppFonts.cardTitle)
                        .textCase(.uppercase)
                        .kerning(0.8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(AppColors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .overlay(Capsule().stroke(AppColors.accent, lineWidth: 1.5))
                // .plain buttons only hit-test rendered pixels — the stroked
                // capsule's interior is dead without an explicit content shape.
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.reassessButton")
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.accent.opacity(0.2), lineWidth: 1))
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
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
