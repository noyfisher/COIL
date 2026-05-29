import SwiftUI

/// Exercise-by-exercise guided workout flow with set tracking,
/// rest timers, and haptic feedback.
struct GuidedWorkoutView: View {
    @StateObject private var vm: GuidedWorkoutViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showSwapSheet = false
    @State private var showFormAnalysis = false
    @State private var showEndConfirmation = false
    @State private var showResumePrompt = false
    @State private var savedCheckpoint: GuidedWorkoutViewModel.WorkoutCheckpoint?
    @State private var showInstructions = false
    @State private var justCompletedSet: Int?
    @State private var completedSegmentIndex: Int?

    init(plan: RehabPlan) {
        _vm = StateObject(wrappedValue: GuidedWorkoutViewModel(plan: plan))
    }

    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()

            if vm.totalExercises == 0 {
                emptyExercisesView
            } else {
                switch vm.phase {
                case .exercise:
                    exercisePhaseView
                case .rest:
                    restPhaseView
                case .complete:
                    GuidedWorkoutSummaryView(vm: vm)
                }
            }
        }
        .navigationTitle("Guided Workout")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(vm.phase != .complete)
        .toolbar {
            if vm.phase != .complete {
                ToolbarItem(placement: .topBarLeading) {
                    Button("End") {
                        showEndConfirmation = true
                    }
                    .foregroundColor(AppColors.danger)
                    .accessibilityIdentifier("workout.endButton")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { vm.togglePause() }) {
                        Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                    }
                    .accessibilityIdentifier("workout.pauseButton")
                }
            }
        }
        .trackScreen("GuidedWorkout")
        .onAppear {
            AnalyticsService.shared.log(.workoutStarted, parameters: ["exercise_count": vm.totalExercises])
            if let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: vm.plan.id.uuidString) {
                savedCheckpoint = checkpoint
                showResumePrompt = true
            }
            // Auto-expand instructions for first encounter with exercise
            showInstructions = currentFamiliarity == .new
        }
        .alert("Resume Workout?", isPresented: $showResumePrompt) {
            Button("Resume") {
                if let checkpoint = savedCheckpoint {
                    vm.restoreFromCheckpoint(checkpoint)
                    AnalyticsService.shared.log(.workoutResumed)
                }
            }
            Button("Start Fresh", role: .destructive) {
                vm.clearCheckpoint()
            }
        } message: {
            if let checkpoint = savedCheckpoint {
                Text("You have an incomplete workout with \(checkpoint.completedExercises.count) exercise(s) completed. Would you like to continue where you left off?")
            }
        }
        .alert("End Workout?", isPresented: $showEndConfirmation) {
            Button("End & Save", role: .destructive) {
                vm.endWorkoutEarly()
            }
            Button("Discard Workout") {
                vm.discardWorkout()
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Save your progress, or discard if you started by mistake.")
        }
        .onChange(of: vm.currentExerciseIndex) {
            // Auto-expand instructions for new exercises, collapse for familiar
            showInstructions = currentFamiliarity == .new
            // Pop the just-completed progress segment
            if vm.currentExerciseIndex > 0 {
                let prevIndex = vm.currentExerciseIndex - 1
                withAnimation { completedSegmentIndex = prevIndex }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    completedSegmentIndex = nil
                }
            }
        }
        .sheet(isPresented: $showSwapSheet) {
            if let exercise = vm.currentExercise {
                ExerciseSwapSheet(exercise: exercise, plan: vm.plan) { substitute, updatedPlan in
                    vm.swapCurrentExercise(with: substitute, updatedPlan: updatedPlan)
                    showSwapSheet = false
                }
            }
        }
        .sheet(isPresented: $showFormAnalysis) {
            if let exercise = vm.currentExercise {
                FormAnalysisView(exercise: exercise)
            }
        }
    }

    // MARK: - Exercise Phase

    private var exercisePhaseView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Segmented progress bar
                    progressHeader

                    if let exercise = vm.currentExercise {
                        // Exercise image with mastery badge
                        ExerciseImageView(exercise: exercise, isCompact: false)
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .background(AppColors.elevatedSurface)
                            .cornerRadius(AppCorners.large)
                            .overlay(alignment: .topTrailing) {
                                if currentFamiliarity == .mastered {
                                    Text("Mastered")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, AppSpacing.sm)
                                        .padding(.vertical, 4)
                                        .background(AppColors.accent.opacity(0.9))
                                        .cornerRadius(100)
                                        .padding(AppSpacing.sm)
                                }
                            }

                        // Exercise name + How To toggle
                        HStack {
                            Text(exercise.name)
                                .font(.system(.title3, design: .serif).weight(.bold))
                                .foregroundColor(AppColors.primaryText)
                                .accessibilityIdentifier("workout.exerciseName")

                            Spacer()

                            if exercise.startPosition != nil || exercise.movement != nil || exercise.endPosition != nil || !exercise.description.isEmpty {
                                Button {
                                    withAnimation(AppAnimations.smooth) {
                                        showInstructions.toggle()
                                    }
                                } label: {
                                    HStack(spacing: AppSpacing.xs) {
                                        Image(systemName: "book.fill")
                                            .font(.caption2)
                                        Text(showInstructions ? "Hide" : "How to")
                                            .font(AppFonts.captionSemiBold)
                                    }
                                    .foregroundColor(AppColors.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(AppColors.accentTint)
                                    .cornerRadius(100)
                                }
                                .accessibilityIdentifier("workout.howToButton")
                            }
                        }

                        // Info badges
                        HStack(spacing: AppSpacing.md) {
                            infoBadge(icon: "arrow.triangle.2.circlepath", text: "Set \(vm.currentSet)/\(exercise.sets)")
                            infoBadge(icon: "repeat", text: "\(exercise.reps) reps")
                            infoBadge(icon: "timer", text: "\(exercise.restSeconds)s rest")
                        }

                        // Phase-based instruction stepper
                        ExercisePhaseStepperView(
                            startPosition: exercise.startPosition,
                            movement: exercise.movement,
                            endPosition: exercise.endPosition,
                            exerciseDescription: exercise.description,
                            isExpanded: $showInstructions
                        )

                        // Tips (shown when instructions are expanded)
                        if showInstructions && !exercise.tips.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Tips")
                                    .font(AppFonts.captionSemiBold)
                                    .foregroundColor(AppColors.secondaryText)
                                ForEach(exercise.tips, id: \.self) { tip in
                                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                        Text(tip)
                                            .font(AppFonts.caption)
                                            .foregroundColor(AppColors.secondaryText)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Last session context (for familiar/mastered exercises)
                        if currentFamiliarity >= .familiar {
                            lastSessionContextView
                        }

                        // Compact secondary actions
                        secondaryActionsRow
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }

            // Fixed bottom action bar
            if let exercise = vm.currentExercise {
                bottomActionBar(exercise: exercise)
            }
        }
    }

    // MARK: - Bottom Action Bar

    private func bottomActionBar(exercise: RehabExercise) -> some View {
        VStack(spacing: AppSpacing.sm) {
            // Set dot indicators with bounce animation
            HStack(spacing: AppSpacing.sm) {
                ForEach(0..<exercise.sets, id: \.self) { index in
                    Circle()
                        .fill(index < vm.currentSet - 1 ? AppColors.accent : Color.clear)
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle()
                                .stroke(AppColors.accent, lineWidth: 2)
                        )
                        .scaleEffect(justCompletedSet == index ? 1.4 : 1.0)
                        .animation(AppAnimations.bouncy, value: justCompletedSet)
                        .accessibilityIdentifier("workout.setDot.\(index)")
                }
            }

            // Primary action button
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                let completedIndex = vm.currentSet - 1
                vm.completeSet()
                // Bounce the just-completed set dot
                withAnimation { justCompletedSet = completedIndex }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    justCompletedSet = nil
                }
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(vm.currentSet >= exercise.sets ? "Complete Exercise" : "Complete Set \(vm.currentSet)")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("workout.completeSetButton")
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, 34)
        .background(
            AppColors.cardBackground
                .shadow(color: AppColors.cardShadowColor, radius: 12, y: -4)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.subtleBorder)
                .frame(height: 1)
        }
        .accessibilityIdentifier("workout.bottomBar")
    }

    // MARK: - Compact Secondary Actions

    private var secondaryActionsRow: some View {
        HStack(spacing: 32) {
            compactActionButton(
                icon: "video.fill",
                label: "Form",
                identifier: "workout.formCheckButton"
            ) {
                showFormAnalysis = true
            }

            compactActionButton(
                icon: "arrow.triangle.2.circlepath",
                label: "Swap",
                identifier: "workout.swapButton"
            ) {
                showSwapSheet = true
            }

            compactActionButton(
                icon: "forward.fill",
                label: "Skip",
                identifier: "workout.skipButton"
            ) {
                vm.skipExercise()
            }
        }
        .padding(.vertical, AppSpacing.sm)
    }

    private func compactActionButton(icon: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 44, height: 44)
                    .background(AppColors.cardBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppColors.subtleBorder, lineWidth: 1))
                    .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)

                Text(label)
                    .font(AppFonts.captionMedium)
                    .foregroundColor(AppColors.mutedText)
            }
        }
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Rest Phase

    private var restPhaseView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Color-coded timer ring
            ZStack {
                Circle()
                    .stroke(AppColors.accentTint, lineWidth: 8)
                    .frame(width: 220, height: 220)

                Circle()
                    .trim(from: 0, to: restProgress)
                    .stroke(timerColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: restProgress)

                VStack(spacing: AppSpacing.sm) {
                    Text(vm.formattedTimeRemaining)
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundColor(timerColor)
                        .contentTransition(.numericText())

                    Text("Rest")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: timerColor)

            // +/- 15s adjustment buttons
            HStack(spacing: AppSpacing.wide) {
                Button { vm.adjustRestTime(by: -15) } label: {
                    Text("\u{2212}15")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 48, height: 48)
                        .background(AppColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.subtleBorder, lineWidth: 1))
                        .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
                }

                Button { vm.adjustRestTime(by: 15) } label: {
                    Text("+15")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(AppColors.secondaryText)
                        .frame(width: 48, height: 48)
                        .background(AppColors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(AppColors.subtleBorder, lineWidth: 1))
                        .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
                }
            }

            // Next exercise preview with image
            if vm.currentExerciseIndex + 1 < vm.totalExercises {
                let next = vm.plan.exercises[vm.currentExerciseIndex + 1]
                HStack(spacing: AppSpacing.lg) {
                    ExerciseImageView(exercise: next, isCompact: true)

                    VStack(alignment: .leading, spacing: AppSpacing.nano) {
                        Text("Up Next")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.mutedText)
                            .textCase(.uppercase)
                        Text(next.name)
                            .font(.system(.headline, design: .serif))
                            .foregroundColor(AppColors.primaryText)
                        Text("\(next.sets) sets \u{00D7} \(next.reps)")
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.secondaryText)
                    }

                    Spacer()
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
                .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()

            Button(action: {
                vm.skipRest()
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "forward.fill")
                    Text("Skip Rest")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("workout.skipRestButton")
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
    }

    private var timerColor: Color {
        switch restProgress {
        case 0.66...: return AppColors.accent
        case 0.33..<0.66: return AppColors.warning
        default: return AppColors.danger
        }
    }

    // MARK: - Empty State

    private var emptyExercisesView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 50))
                .foregroundColor(AppColors.secondaryText)

            VStack(spacing: AppSpacing.sm) {
                Text("No Exercises Available")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("This plan doesn't have any exercises yet. Please go back and regenerate the plan.")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            Button(action: { dismiss() }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "chevron.left")
                    Text("Go Back")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Helpers

    private var progressHeader: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Text("Exercise \(vm.exerciseProgress)")
                    .font(AppFonts.captionSemiBold)
                    .foregroundColor(AppColors.accent)
                Spacer()
                Text(vm.formattedElapsedTime)
                    .font(AppFonts.captionMedium)
                    .foregroundColor(AppColors.secondaryText)
            }

            HStack(spacing: AppSpacing.xs) {
                ForEach(0..<vm.totalExercises, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(segmentColor(for: index))
                        .frame(height: 6)
                        .scaleEffect(y: completedSegmentIndex == index ? 1.8 : 1.0)
                        .animation(AppAnimations.springy, value: completedSegmentIndex)
                }
            }
        }
    }

    private func segmentColor(for index: Int) -> Color {
        if index < vm.currentExerciseIndex {
            return AppColors.accent
        } else if index == vm.currentExerciseIndex {
            return AppColors.accent.opacity(0.5)
        } else {
            return AppColors.accentTint
        }
    }

    private func infoBadge(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(AppFonts.captionMedium)
        }
        .foregroundColor(AppColors.accent)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.accentTint)
        .cornerRadius(AppCorners.small)
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(AppColors.accent)
            Text(text)
                .font(AppFonts.body)
                .foregroundColor(AppColors.secondaryText)
        }
    }

    // MARK: - Progressive Learning

    private var currentFamiliarity: GuidedWorkoutViewModel.ExerciseFamiliarity {
        guard let exercise = vm.currentExercise else { return .new }
        let count = GuidedWorkoutViewModel.completionCount(for: exercise.name)
        return .init(completions: count)
    }

    private var lastSessionContextView: some View {
        Group {
            if let lastSession = workoutViewModel.sessions
                .filter({ $0.planId == vm.plan.id })
                .sorted(by: { $0.date > $1.date })
                .first {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                        .frame(width: 28, height: 28)
                        .background(AppColors.accent.opacity(0.10))
                        .cornerRadius(7)

                    Text("Last time: ")
                        .font(AppFonts.captionMedium)
                        .foregroundColor(AppColors.secondaryText)
                    +
                    Text("Completed \(lastSession.exercisesPerformed.count) exercises")
                        .font(AppFonts.captionSemiBold)
                        .foregroundColor(AppColors.primaryText)
                    +
                    Text(" · Pain \(Int(lastSession.painLevel))/10")
                        .font(AppFonts.captionMedium)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
            }
        }
    }

    private var restProgress: CGFloat {
        guard let exercise = vm.currentExercise, exercise.restSeconds > 0 else { return 0 }
        let total = Double(exercise.restSeconds)
        return CGFloat(Double(vm.timeRemaining) / total)
    }
}
