import SwiftUI

/// Personalized, adaptive daily injury-prevention loop — the top-level
/// content for Home's "Prevention" segment. Replaces the old static
/// checklist as the primary experience; the checklist survives as the
/// collapsible "General wellness habits" section at the bottom.
struct TodaysPreventionView: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @ObservedObject private var profileService = UserProfileService.shared
    @StateObject private var viewModel = PreventionViewModel()

    @State private var routineState: RoutineCardState = .notStarted
    @State private var completedExerciseIds: Set<UUID> = []
    @State private var expandedExerciseId: UUID?
    @State private var isGeneralHabitsExpanded = false

    private enum RoutineCardState { case notStarted, active, completed }

    private var activePlan: RehabPlan? {
        savedPlansViewModel.rehabPlans.first(where: { $0.planType == .rehab })
            ?? savedPlansViewModel.rehabPlans.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            switch viewModel.stage {
            case .needsCheckIn:
                header(subtitle: "Let's see what today looks like.", minutesText: nil)
                needsCheckInCard
            case .safetyHold:
                header(subtitle: "Safety pause for today.", minutesText: nil)
                SafetyGuidanceCard { tabSelection.assessmentRequest = .pain }
                changeCheckInButton
            case .routine(let routine):
                header(subtitle: routine.rationale, minutesText: "\(routine.length.rawValue) min")
                essentialRoutineCard(routine)
                if let micro = routine.microAction {
                    microActionCard(micro)
                }
                progressSection
            }

            generalHabitsSection
        }
        .onAppear {
            viewModel.refresh(activePlan: activePlan, healthProfile: profileService.profile)
        }
        .onChange(of: savedPlansViewModel.rehabPlans.count) { _, _ in
            viewModel.refresh(activePlan: activePlan, healthProfile: profileService.profile)
        }
        .sheet(isPresented: $viewModel.showCheckInSheet) {
            PreventionCheckInSheet(viewModel: viewModel, activePlan: activePlan, healthProfile: profileService.profile)
        }
        .sheet(isPresented: $viewModel.showProfileSetup) {
            PreventionProfileSetupView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showWeeklyReview) {
            PreventionWeeklyReviewView(viewModel: viewModel)
        }
        .sheet(item: $viewModel.pendingFeedbackFor) { _ in
            PreventionFeedbackSheet(viewModel: viewModel)
        }
        .trackScreen("TodaysPrevention")
    }

    // MARK: - Header

    private func header(subtitle: String, minutesText: String?) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .top) {
                CoilDividerHeader(title: "Today's Prevention")
                Spacer()
                Button("Personalize") { viewModel.showProfileSetup = true }
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.accentText)
                    .accessibilityIdentifier("prevention.personalizeButton")
                    .accessibilityHint("Set your prevention focus, typical day, equipment and routine length.")
            }

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(subtitle)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                if let minutesText {
                    Text(minutesText)
                        .font(AppFonts.captionSemiBold)
                        .foregroundColor(AppColors.accentText)
                        .accessibilityIdentifier("prevention.estimatedTime")
                }
            }

            if !isNeedsCheckInStage {
                changeCheckInButton
            }
        }
    }

    private var isNeedsCheckInStage: Bool {
        if case .needsCheckIn = viewModel.stage { return true }
        return false
    }

    private var changeCheckInButton: some View {
        Button("Change") { viewModel.showCheckInSheet = true }
            .font(AppFonts.caption)
            .foregroundColor(AppColors.accentText)
            .accessibilityIdentifier("prevention.changeCheckInButton")
            .accessibilityHint("Redo today's check-in — what today looks like, symptoms, and time available.")
    }

    // MARK: - Needs Check-In

    @ViewBuilder
    private var needsCheckInCard: some View {
        if !viewModel.profile.hasCompletedSetup && activePlan == nil {
            EmptyStateView(
                icon: "shield.checkerboard",
                title: "Set Your Prevention Goals",
                subtitle: "A few quick preferences help build a short daily routine that fits your day — desk comfort, workout warm-ups, balance, and more.",
                actionTitle: "Get Started",
                action: { viewModel.showProfileSetup = true }
            )
            .accessibilityIdentifier("prevention.emptyState")
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("A quick 3-question check-in tailors today's routine to how you're feeling.")
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
                Button("Start Daily Check-In") { viewModel.showCheckInSheet = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("prevention.startCheckInButton")
            }
            .cardStyle()
        }
    }

    // MARK: - Essential Routine Card

    private func essentialRoutineCard(_ routine: DailyPreventionRoutine) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text(routine.categoryEmphasis.displayName)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                CoilBadge(text: "\(routine.length.rawValue) MIN")
            }

            if routine.wasRegressed {
                Label("Eased off based on your last feedback", systemImage: "arrow.down.right.circle.fill")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.warning)
            } else if routine.wasAdvanced {
                Label("Stepped up based on your recent progress", systemImage: "arrow.up.right.circle.fill")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.success)
            }

            ForEach(routine.essentialExercises) { item in
                PreventionExerciseRow(
                    item: item,
                    showsCheckbox: routineState != .notStarted,
                    isExpanded: expandedExerciseId == item.id,
                    isChecked: routineState == .completed || completedExerciseIds.contains(item.id),
                    onToggleExpand: {
                        withAnimation(AppAnimations.smooth) {
                            expandedExerciseId = expandedExerciseId == item.id ? nil : item.id
                        }
                    },
                    onToggleCheck: {
                        guard routineState == .active else { return }
                        withAnimation(AppAnimations.springy) {
                            if completedExerciseIds.contains(item.id) {
                                completedExerciseIds.remove(item.id)
                            } else {
                                completedExerciseIds.insert(item.id)
                            }
                        }
                    }
                )
            }

            routineActions(routine)
        }
        .cardStyle()
        .onChange(of: routine.dateKey) { _, _ in
            routineState = .notStarted
            completedExerciseIds = []
            expandedExerciseId = nil
        }
    }

    @ViewBuilder
    private func routineActions(_ routine: DailyPreventionRoutine) -> some View {
        switch routineState {
        case .notStarted:
            HStack(spacing: AppSpacing.sm) {
                Button("Start \(routine.length.rawValue) min") {
                    AnalyticsService.shared.log(.preventionRoutineStarted, parameters: [
                        "category": routine.categoryEmphasis.rawValue,
                        "minutes": routine.length.rawValue
                    ])
                    withAnimation(AppAnimations.smooth) { routineState = .active }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("prevention.startRoutineButton")

                Button("Too much today") {
                    viewModel.tooMuchToday(routine)
                    withAnimation(AppAnimations.smooth) { routineState = .completed }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("prevention.tooMuchTodayButton")
                .accessibilityHint("Skips today's routine and eases off tomorrow's.")
            }
        case .active:
            Button("Mark Routine Complete") {
                viewModel.completeRoutine(routine)
                withAnimation(AppAnimations.smooth) { routineState = .completed }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("prevention.markCompleteButton")
            .accessibilityHint("Marks today's routine as complete and asks a quick feedback question.")
        case .completed:
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(AppColors.success)
                Text("Done for today")
                    .font(AppFonts.captionSemiBold)
                    .foregroundColor(AppColors.success)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("prevention.completedBadge")
        }
    }

    // MARK: - Micro-Action Card

    private func microActionCard(_ item: PreventionExercise) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundColor(AppColors.accent)
                Text("Optional · \(item.exercise.name)")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                Text("~1 min")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.mutedText)
            }
            Text(item.exercise.description)
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prevention.microActionCard")
        .accessibilityLabel("Optional micro-action: \(item.exercise.name), about 1 minute. \(item.exercise.description)")
    }

    // MARK: - Progress

    private var progressSection: some View {
        let review = viewModel.currentWeekProgress()
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("This Week")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                Button("Weekly Review") { viewModel.showWeeklyReview = true }
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.accentText)
                    .accessibilityIdentifier("prevention.openWeeklyReviewButton")
            }

            if review.completionsByCategory.isEmpty {
                Text("Complete a routine to start building your weekly progress.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.mutedText)
            } else {
                HStack(spacing: AppSpacing.md) {
                    ForEach(PreventionCategory.allCases) { category in
                        let count = review.completionsByCategory[category] ?? 0
                        VStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .foregroundColor(count > 0 ? AppColors.accent : AppColors.mutedText)
                            Text("\(count)")
                                .font(AppFonts.bodySemiBold)
                                .foregroundColor(AppColors.primaryText)
                            Text(category.displayName)
                                .font(AppFonts.micro)
                                .foregroundColor(AppColors.mutedText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(category.displayName): \(count) this week")
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - General Wellness Habits (legacy checklist, kept secondary)

    private var generalHabitsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Button {
                withAnimation(AppAnimations.smooth) { isGeneralHabitsExpanded.toggle() }
            } label: {
                HStack {
                    Text("General Wellness Habits")
                        .font(AppFonts.smallSemiBold)
                        .foregroundColor(AppColors.secondaryText)
                    Spacer()
                    Image(systemName: isGeneralHabitsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.mutedText)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("prevention.generalHabitsToggle")
            .accessibilityHint(isGeneralHabitsExpanded ? "Collapses the general wellness habits checklist." : "Expands the general wellness habits checklist.")

            if isGeneralHabitsExpanded {
                PreventativeTasksView()
                    .transition(.opacity)
            }
        }
        .padding(.top, AppSpacing.sm)
    }
}

// MARK: - Exercise Row

private struct PreventionExerciseRow: View {
    let item: PreventionExercise
    let showsCheckbox: Bool
    let isExpanded: Bool
    let isChecked: Bool
    let onToggleExpand: () -> Void
    let onToggleCheck: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.md) {
                if showsCheckbox {
                    Button(action: onToggleCheck) {
                        ZStack {
                            Circle()
                                .stroke(isChecked ? AppColors.accent : AppColors.cardBorder, lineWidth: 1.5)
                                .frame(width: 26, height: 26)
                            if isChecked {
                                Circle().fill(AppColors.accent).frame(width: 26, height: 26)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isChecked ? "Mark \(item.exercise.name) as not done" : "Mark \(item.exercise.name) as done")
                    .accessibilityIdentifier("prevention.exerciseCheck.\(item.catalogKey)")
                }

                ExerciseImageView(exercise: item.exercise, isCompact: true)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text(item.exercise.name)
                        .font(AppFonts.smallSemiBold)
                        .foregroundColor(isChecked ? AppColors.mutedText : AppColors.primaryText)
                        .strikethrough(isChecked, color: AppColors.mutedText)
                        .lineLimit(1)

                    Text(item.durationSeconds != nil ? item.exercise.reps : "\(item.exercise.sets) sets · \(item.exercise.reps)")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppColors.mutedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Hide instructions for \(item.exercise.name)" : "Show instructions for \(item.exercise.name)")
                .accessibilityIdentifier("prevention.exerciseExpand.\(item.catalogKey)")
            }

            ExercisePhaseStepperView(
                startPosition: item.exercise.startPosition,
                movement: item.exercise.movement,
                endPosition: item.exercise.endPosition,
                exerciseDescription: item.exercise.description,
                isExpanded: .constant(isExpanded)
            )
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
