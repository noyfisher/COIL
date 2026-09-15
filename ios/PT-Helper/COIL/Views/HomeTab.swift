import SwiftUI

// MARK: - Home Tab

/// True iff a completed workout session falls on `day`.
enum HomeStripLogic {
    static func hasCompletedSession(on day: Date, in sessions: [WorkoutSession],
                                     calendar: Calendar = .current) -> Bool {
        sessions.contains { $0.isCompleted && calendar.isDate($0.date, inSameDayAs: day) }
    }
}

/// Pure schedule logic for the Home tab's "Today's Program".
/// `weeklySchedule` is indexed 0 = Sunday … 6 = Saturday (see `RehabPlanView.weeklyCalendar`
/// and `RehabPlanViewModel.createWeeklySchedule`); entries are exercise ids (generator) or
/// exercise names (test seeder), so both are accepted, case-insensitively.
enum HomeProgramLogic {

    /// nil = no usable schedule, OR today's entries resolve to no current exercise (e.g. the
    ///       schedule still names an exercise id that was swapped out) → show every exercise;
    /// []  = a scheduled rest day (today's entry is genuinely empty);
    /// otherwise today's exercises in plan order.
    static func todaysExercises(for plan: RehabPlan, on date: Date,
                                calendar: Calendar = .current) -> [RehabExercise]? {
        let schedule = plan.weeklySchedule
        guard schedule.count == 7, schedule.contains(where: { !$0.isEmpty }) else { return nil }
        let dayIndex = calendar.component(.weekday, from: date) - 1
        let entries = schedule[dayIndex]
        if entries.isEmpty { return [] }
        let resolved = exercises(in: plan, matching: entries)
        return resolved.isEmpty ? nil : resolved
    }

    /// The next scheduled day strictly after `date`, within the following 7 days. Counts
    /// resolved exercises, falling back to the raw entry count when none resolve.
    static func nextSession(for plan: RehabPlan, after date: Date,
                            calendar: Calendar = .current) -> (weekdayName: String, exerciseCount: Int)? {
        let schedule = plan.weeklySchedule
        guard schedule.count == 7 else { return nil }
        let today = calendar.component(.weekday, from: date) - 1
        for offset in 1...7 {
            let index = (today + offset) % 7
            let entries = schedule[index]
            if entries.isEmpty { continue }
            let resolved = exercises(in: plan, matching: entries).count
            return (calendar.shortWeekdaySymbols[index], resolved > 0 ? resolved : entries.count)
        }
        return nil
    }

    /// The plan Home should show: the first active rehab plan, else the first rehab plan, else any plan.
    static func preferredPlan(from plans: [RehabPlan]) -> RehabPlan? {
        let rehab = plans.filter { $0.planType == .rehab }
        if let active = rehab.first(where: { isActive($0) }) { return active }
        return rehab.first ?? plans.first
    }

    private static func isActive(_ plan: RehabPlan) -> Bool {
        if case .active = plan.status { return true }
        return false
    }

    private static func exercises(in plan: RehabPlan, matching entries: [String]) -> [RehabExercise] {
        let keys = Set(entries.map { $0.lowercased() })
        return plan.exercises.filter {
            keys.contains($0.id.uuidString.lowercased()) || keys.contains($0.name.lowercased())
        }
    }
}

struct HomeTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel

    @State private var selectedContentTab: HomeContentTab = .program

    enum HomeContentTab { case program, preventative }

    private var activePlan: RehabPlan? {
        savedPlansViewModel.rehabPlans.first(where: { $0.planType == .rehab })
            ?? savedPlansViewModel.rehabPlans.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Weekly strip — dark, visually extends the nav bar
                    WeekCompletionStrip(sessions: workoutViewModel.sessions)

                    // Program / Preventative picker — only meaningful with an active plan
                    if activePlan != nil {
                        HomeTabPicker(selected: $selectedContentTab)
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, AppSpacing.md)
                            .padding(.bottom, AppSpacing.sm)
                    }

                    // Content
                    ScrollView {
                        VStack(spacing: AppSpacing.md) {
                            if activePlan == nil {
                                ProgramDayView(plan: nil)
                            } else {
                                switch selectedContentTab {
                                case .program:
                                    ProgramDayView(plan: activePlan)
                                case .preventative:
                                    PreventativeTasksView()
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.xs)
                        .floatingTabBarClearance()
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .coilNavBar()
        }
        .trackScreen("HomeTab")
        .onAppear { workoutViewModel.fetchSessions() }
    }
}

// MARK: - Week Completion Strip

private struct WeekCompletionStrip: View {
    let sessions: [WorkoutSession]

    /// Fixed rolling 7-day window ending today (today at the trailing edge).
    /// Every cell is today-or-past, so a missing dot unambiguously means
    /// "no completed session that day" — no future cell can ever carry a dot.
    private var weekDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-6...0).compactMap { offset -> Date? in
            cal.date(byAdding: .day, value: offset, to: today)
        }
    }

    private var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: Date()).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(monthLabel)
                .font(AppFonts.cardTitle)
                .kerning(0.5)
                .foregroundColor(Color.white.opacity(0.55))
                .padding(.horizontal, AppSpacing.lg)

            HStack(spacing: AppSpacing.xs) {
                ForEach(weekDays, id: \.self) { day in
                    DayCell(
                        date: day,
                        isToday: Calendar.current.isDateInToday(day),
                        isCompleted: HomeStripLogic.hasCompletedSession(on: day, in: sessions)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.md)
        .background(AppColors.navBackground)
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isCompleted: Bool

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let numFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()
    private static let fullDayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()

    var body: some View {
        VStack(spacing: 3) {
            Text(Self.dayFmt.string(from: date).uppercased())
                .font(AppFonts.micro)
                .foregroundColor(Color.white.opacity(0.40))

            Text(Self.numFmt.string(from: date))
                .font(AppFonts.sectionTitle)
                .foregroundColor(isToday ? AppColors.accent : Color.white.opacity(0.55))

            if isCompleted {
                Circle().fill(AppColors.success).frame(width: 6, height: 6)
            } else {
                // The week strip sits on the fixed-dark navBackground, where the
                // adaptive hairline resolves to black in light mode and the
                // "no session" marker vanishes entirely.
                Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: 6, height: 6)
            }
        }
        .frame(width: 44, height: 66)
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppCorners.small + 2))
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.small + 2)
                .stroke(
                    isToday ? AppColors.accent.opacity(0.55) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Self.fullDayFmt.string(from: date)) \(Self.numFmt.string(from: date)), "
            + (isCompleted ? "workout completed" : "no workout")
        )
    }
}

// MARK: - Tab Picker (Program | Preventative)

private struct HomeTabPicker: View {
    @Binding var selected: HomeTab.HomeContentTab

    var body: some View {
        HStack(spacing: 0) {
            pickerButton("Program", tab: .program)
            pickerButton("Preventative", tab: .preventative)
        }
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCorners.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func pickerButton(_ label: String, tab: HomeTab.HomeContentTab) -> some View {
        let active = selected == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = tab }
        } label: {
            Text(label)
                .font(AppFonts.cardTitle)
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundColor(active ? .white : AppColors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm + 2)
                .background(active ? AppColors.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: AppCorners.card - 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Day View

struct ProgramDayView: View {
    let plan: RehabPlan?

    @EnvironmentObject private var tabSelection: TabSelection

    var body: some View {
        if let plan = plan {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                CoilDividerHeader(title: "Today's Program")

                // Plan name badge
                HStack(spacing: AppSpacing.sm) {
                    CoilBadge(text: "Active Plan")
                    Text(plan.planName)
                        .font(AppFonts.smallSemiBold)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Text("\(plan.exercises.count) exercises")
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.mutedText)
                }

                // Exercise rows
                ForEach(plan.exercises.prefix(8)) { exercise in
                    ExerciseProgramRow(exercise: exercise)
                }

                if plan.exercises.count > 8 {
                    Text("+ \(plan.exercises.count - 8) more exercises")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.mutedText)
                        .padding(.leading, AppSpacing.xs)
                }

                // Start workout CTA
                NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Start Guided Workout")
                            .font(AppFonts.cardTitle)
                            .textCase(.uppercase)
                            .kerning(1.0)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.ctaBackground)
                    .clipShape(Capsule())
                    .shadow(color: AppColors.ctaBackground.opacity(0.30), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.top, AppSpacing.xs)
                .accessibilityIdentifier("home.startWorkoutButton")
            }
        } else {
            noPlanState
        }
    }

    private var noPlanState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: AppSpacing.xxl)
            EmptyStateView(
                icon: "list.clipboard",
                title: "No Active Program",
                subtitle: "Complete an assessment to get a personalized rehab program",
                actionTitle: "Start Assessment",
                action: { tabSelection.assessmentRequest = .gateway }
            )
            Spacer(minLength: AppSpacing.xl)
        }
    }
}

// MARK: - Exercise Program Row

private struct ExerciseProgramRow: View {
    let exercise: RehabExercise

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            ExerciseImageView(exercise: exercise, isCompact: true)

            VStack(alignment: .leading, spacing: AppSpacing.nano) {
                Text(exercise.name)
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)

                Text(exercise.dosageText)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)

                if !exercise.targetArea.isEmpty {
                    Text(exercise.targetArea)
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.mutedText)
                }
            }

            Spacer()

            // No disclosure chevron: this row has no tap target. A chevron is a
            // promise of navigation, and tapping did nothing — the exercise detail
            // is reached from the plan, not from here.
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCorners.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Preventative Tasks View

struct PreventativeTasksView: View {
    private static let taskDefinitions: [String] = [
        "Morning movement (5 min)",
        "Ice / heat therapy",
        "Posture check",
        "Foam roll",
        "Hydration (8 glasses)",
        "Range of motion work",
        "Deep breathing / recovery",
    ]

    @State private var checkedStates: [Bool] = Array(repeating: false, count: taskDefinitions.count)

    private var dateKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    private var completedCount: Int { checkedStates.filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CoilDividerHeader(title: "Daily Preventative Care")

            // Progress summary
            HStack(spacing: AppSpacing.sm) {
                Text("\(completedCount) / \(Self.taskDefinitions.count) completed")
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.secondaryText)

                Spacer()

                if completedCount == Self.taskDefinitions.count {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                        Text("All done!")
                            .font(AppFonts.captionSemiBold)
                    }
                    .foregroundColor(AppColors.success)
                }
            }
            .padding(.horizontal, AppSpacing.xs)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.cardBorder)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColors.accent)
                        .frame(
                            width: Self.taskDefinitions.isEmpty ? 0
                                : geo.size.width * CGFloat(completedCount) / CGFloat(Self.taskDefinitions.count),
                            height: 4
                        )
                        .animation(.easeInOut(duration: 0.3), value: completedCount)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, AppSpacing.xs)

            // Task rows
            ForEach(Array(Self.taskDefinitions.enumerated()), id: \.offset) { idx, task in
                PreventativeTaskRow(
                    title: task,
                    isChecked: checkedStates[idx]
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        checkedStates[idx].toggle()
                    }
                    saveState()
                }
            }
        }
        .onAppear { loadState() }
    }

    private func saveState() {
        let dict = Dictionary(uniqueKeysWithValues: zip(Self.taskDefinitions, checkedStates))
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: "preventiveTasks_\(dateKey)")
        }
    }

    private func loadState() {
        guard let data = UserDefaults.standard.data(forKey: "preventiveTasks_\(dateKey)"),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data)
        else {
            checkedStates = Array(repeating: false, count: Self.taskDefinitions.count)
            return
        }
        checkedStates = Self.taskDefinitions.map { dict[$0] ?? false }
    }
}

// MARK: - Preventative Task Row

private struct PreventativeTaskRow: View {
    let title: String
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle()
                        .stroke(isChecked ? AppColors.accent : AppColors.cardBorder, lineWidth: 1.5)
                        .frame(width: 26, height: 26)

                    if isChecked {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                Text(title)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(isChecked ? AppColors.mutedText : AppColors.primaryText)
                    .strikethrough(isChecked, color: AppColors.mutedText)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.md)
            .background(AppColors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCorners.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(
                        isChecked ? AppColors.accent.opacity(0.25) : AppColors.cardBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
