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
                    .foregroundColor(.red)
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
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your completed exercises will be saved. This cannot be undone.")
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
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Progress bar
                progressHeader

                if let exercise = vm.currentExercise {
                    // Exercise image
                    ExerciseImageView(exercise: exercise, isCompact: false)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.elevatedSurface)
                        .cornerRadius(AppCorners.large)

                    // Exercise info card
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text(exercise.name)
                            .font(.title3.weight(.bold))
                            .accessibilityIdentifier("workout.exerciseName")

                        HStack(spacing: AppSpacing.md) {
                            infoBadge(icon: "arrow.triangle.2.circlepath", text: "Set \(vm.currentSet)/\(exercise.sets)")
                            infoBadge(icon: "repeat", text: "\(exercise.reps) reps")
                            infoBadge(icon: "timer", text: "\(exercise.restSeconds)s rest")
                        }

                        if let start = exercise.startPosition {
                            instructionRow(icon: "1.circle.fill", text: start)
                        }
                        if let movement = exercise.movement {
                            instructionRow(icon: "2.circle.fill", text: movement)
                        }
                        if let end = exercise.endPosition {
                            instructionRow(icon: "3.circle.fill", text: end)
                        }

                        if !exercise.tips.isEmpty {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Tips")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                ForEach(exercise.tips, id: \.self) { tip in
                                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                        Text(tip)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)

                    // Action buttons
                    VStack(spacing: AppSpacing.md) {
                        Button(action: {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            vm.completeSet()
                        }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                Text(vm.currentSet >= exercise.sets ? "Complete Exercise" : "Complete Set \(vm.currentSet)")
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("workout.completeSetButton")

                        Button(action: { showFormAnalysis = true }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "video.fill")
                                Text("Check My Form")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("workout.formCheckButton")

                        Button(action: { showSwapSheet = true }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Swap Exercise")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("workout.swapButton")

                        Button(action: {
                            vm.skipExercise()
                        }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "forward.fill")
                                Text("Skip Exercise")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("workout.skipButton")
                    }
                }

                // Elapsed time
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text(vm.formattedElapsedTime)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Rest Phase

    private var restPhaseView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Timer ring
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.15), lineWidth: 8)
                    .frame(width: 200, height: 200)

                Circle()
                    .trim(from: 0, to: restProgress)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: restProgress)

                VStack(spacing: AppSpacing.sm) {
                    Text(vm.formattedTimeRemaining)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)

                    Text("Rest")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            // Next exercise preview
            if vm.currentExerciseIndex + 1 < vm.totalExercises {
                let next = vm.plan.exercises[vm.currentExerciseIndex + 1]
                VStack(spacing: AppSpacing.sm) {
                    Text("Up Next")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(next.name)
                        .font(.headline)
                    Text("\(next.sets) sets \u{00D7} \(next.reps)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
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
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
    }

    // MARK: - Empty State

    private var emptyExercisesView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "figure.walk.motion")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            VStack(spacing: AppSpacing.sm) {
                Text("No Exercises Available")
                    .font(.title3.weight(.bold))

                Text("This plan doesn't have any exercises yet. Please go back and regenerate the plan.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
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
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.blue)
                Spacer()
                Text(vm.formattedElapsedTime)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.15))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * vm.progress, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: vm.progress)
                }
            }
            .frame(height: 6)
        }
    }

    private func infoBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .foregroundColor(.blue)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(AppCorners.small)
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var restProgress: CGFloat {
        guard let exercise = vm.currentExercise, exercise.restSeconds > 0 else { return 0 }
        let total = Double(exercise.restSeconds)
        return CGFloat(Double(vm.timeRemaining) / total)
    }
}
