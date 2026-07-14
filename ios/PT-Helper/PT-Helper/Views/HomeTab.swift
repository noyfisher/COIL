import SwiftUI

// MARK: - Home Tab

struct HomeTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection

    @State private var selectedDate: Date = Date()
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
                    // Weekly strip — sits directly on the page background
                    WeeklyDateStrip(selectedDate: $selectedDate)

                    // Program / Preventative picker
                    HomeTabPicker(selected: $selectedContentTab)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .padding(.bottom, AppSpacing.sm)

                    // Content
                    ScrollView {
                        VStack(spacing: AppSpacing.md) {
                            switch selectedContentTab {
                            case .program:
                                ProgramDayView(plan: activePlan, date: selectedDate)
                            case .preventative:
                                PreventativeTasksView(date: selectedDate)
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.xs)
                        .floatingTabBarClearance()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .trackScreen("HomeTab")
    }
}

// MARK: - Weekly Date Strip

private struct WeeklyDateStrip: View {
    @Binding var selectedDate: Date

    /// 10 days back → 10 days forward (21 total), centred on today.
    private var scrollableDays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-10...10).compactMap { offset -> Date? in
            cal.date(byAdding: .day, value: offset, to: today)
        }
    }

    private var monthLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: selectedDate).uppercased()
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                // Month + "Today" button row
                HStack {
                    Text(monthLabel)
                        .font(Font.custom("Inter-Bold", size: 13))
                        .kerning(0.5)
                        .foregroundColor(AppColors.mutedText)

                    Spacer()

                    if !Calendar.current.isDateInToday(selectedDate) {
                        Button {
                            let today = Calendar.current.startOfDay(for: Date())
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                selectedDate = Date()
                                proxy.scrollTo(today, anchor: .center)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Today")
                                    .font(AppFonts.captionSemiBold)
                            }
                            .foregroundColor(AppColors.accent)
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .animation(.easeInOut(duration: 0.2), value: Calendar.current.isDateInToday(selectedDate))

                // Day cells — scrollable ±10 days with edge fade
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(scrollableDays, id: \.self) { day in
                            DayCell(
                                date: day,
                                isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                                isToday: Calendar.current.isDateInToday(day)
                            )
                            .id(day)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    selectedDate = day
                                }
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .black, location: 0.12),
                            .init(color: .black, location: 0.88),
                            .init(color: .clear, location: 1.00),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .onAppear {
                    let today = Calendar.current.startOfDay(for: Date())
                    proxy.scrollTo(today, anchor: .center)
                }
            }
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
        }
    }
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE"; return f
    }()
    private static let numFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d"; return f
    }()

    var body: some View {
        VStack(spacing: 3) {
            Text(Self.dayFmt.string(from: date).uppercased())
                .font(AppFonts.micro)
                .foregroundColor(isSelected ? Color.white.opacity(0.75) : AppColors.mutedText)

            Text(Self.numFmt.string(from: date))
                .font(Font.custom("Inter-Bold", size: 20))
                .foregroundColor(
                    isSelected ? .white
                    : isToday  ? AppColors.accent
                    : AppColors.primaryText
                )
        }
        .frame(width: 44, height: 60)
        .background(isSelected ? AppColors.primaryText : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppCorners.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.medium)
                .stroke(
                    isToday && !isSelected ? AppColors.accent.opacity(0.55) : Color.clear,
                    lineWidth: 1.5
                )
        )
        .shadow(
            color: isSelected ? AppColors.primaryText.opacity(0.25) : .clear,
            radius: 6, y: 3
        )
    }
}

// MARK: - Tab Picker (Program | Preventative)

private struct HomeTabPicker: View {
    @Binding var selected: HomeTab.HomeContentTab

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            pickerButton("Program", tab: .program)
            pickerButton("Preventative", tab: .preventative)
        }
        .padding(AppSpacing.xs)
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppCorners.pill))
    }

    @ViewBuilder
    private func pickerButton(_ label: String, tab: HomeTab.HomeContentTab) -> some View {
        let active = selected == tab
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = tab }
        } label: {
            Text(label)
                .font(Font.custom("Inter-SemiBold", size: 14))
                .foregroundColor(active ? AppColors.primaryText : AppColors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm + 2)
                .background(active ? AppColors.cardBackground : Color.clear)
                .clipShape(Capsule())
                .shadow(color: active ? Color.black.opacity(0.08) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Program Day View

struct ProgramDayView: View {
    let plan: RehabPlan?
    let date: Date

    @EnvironmentObject private var tabSelection: TabSelection

    private var dayLabel: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter(); fmt.dateFormat = "EEEE"
        return fmt.string(from: date)
    }

    var body: some View {
        if let plan = plan {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("\(dayLabel)'s Program")
                    .font(AppFonts.sectionTitle)
                    .foregroundColor(AppColors.primaryText)

                // Plan name badge
                HStack(spacing: AppSpacing.sm) {
                    AccentBadge(text: "Active Plan")
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
                            .font(Font.custom("Inter-SemiBold", size: 15))
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
                action: { tabSelection.selectedTab = 0 }
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
            // Icon / image placeholder
            ZStack {
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .fill(AppColors.accentTint)
                    .frame(width: 52, height: 52)
                Image(systemName: exercise.demonstrationIcon.isEmpty ? "figure.strengthtraining.traditional" : exercise.demonstrationIcon)
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.accentDark)
            }

            VStack(alignment: .leading, spacing: AppSpacing.nano) {
                Text(exercise.name)
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)

                Text("\(exercise.sets) sets · \(exercise.reps) reps")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)

                if !exercise.targetArea.isEmpty {
                    Text(exercise.targetArea)
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.mutedText)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.mutedText)
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
    let date: Date

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
        return fmt.string(from: date)
    }

    private var completedCount: Int { checkedStates.filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Daily Preventative Care")
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.primaryText)

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
        .onChange(of: date) { _, _ in loadState() }
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
