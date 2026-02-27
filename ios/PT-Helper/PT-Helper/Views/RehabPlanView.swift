import SwiftUI

struct RehabPlanView: View {
    var analysisResult: AnalysisResult? = nil
    var existingPlan: RehabPlan? = nil
    @StateObject var viewModel = RehabPlanViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if viewModel.isGenerating {
                generatingView
            } else if let error = viewModel.generationError {
                errorView(error)
            } else if let plan = viewModel.rehabPlan {
                ScrollView {
                    VStack(spacing: 16) {
                        planHeader(plan: plan)
                        weeklyCalendar(plan: plan)
                        exerciseList(for: plan)
                        if analysisResult != nil {
                            savePlanButton
                        }
                    }
                    .padding(20)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Rehab Plan")
        .toolbar {
            if analysisResult != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if viewModel.rehabPlan == nil && !viewModel.isGenerating {
                if let existing = existingPlan {
                    // Viewing a saved plan — no generation needed
                    viewModel.rehabPlan = existing
                } else if let analysis = analysisResult {
                    // Generate a new AI-powered plan
                    viewModel.generateRehabPlan(from: analysis)
                }
            }
        }
    }

    // MARK: - Loading State

    private var generatingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Building Your Plan")
                    .font(.title2.weight(.bold))

                Text("Creating a personalized exercise program based on your conditions and fitness level...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            ProgressView()
                .scaleEffect(1.2)
                .tint(.green)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Plan Generation Failed")
                    .font(.title3.weight(.bold))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            if let analysis = analysisResult {
                Button(action: {
                    viewModel.generateRehabPlan(from: analysis)
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.xxl)
            }

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Plan Display

    private func planHeader(plan: RehabPlan) -> some View {
        CardSection(icon: "calendar", color: .blue, title: plan.planName) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Conditions: \(plan.conditions.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Duration: \(plan.totalWeeks) weeks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Start Date:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    DatePicker("", selection: Binding(
                        get: { viewModel.rehabPlan?.createdDate ?? Date() },
                        set: { viewModel.rehabPlan?.createdDate = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
                if let notes = plan.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, AppSpacing.xs)
                }
            }
        }
    }

    private func weeklyCalendar(plan: RehabPlan) -> some View {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { day in
                VStack(spacing: 6) {
                    Text(dayNames[day])
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(plan.weeklySchedule.indices.contains(day) && !plan.weeklySchedule[day].isEmpty ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func exerciseList(for plan: RehabPlan) -> some View {
        VStack(spacing: 16) {
            ForEach(plan.exercises) { exercise in
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                    exerciseCard(for: exercise)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func exerciseCard(for exercise: RehabExercise) -> some View {
        HStack(spacing: AppSpacing.lg) {
            // Compact exercise image with SF Symbol fallback
            ExerciseImageView(exercise: exercise, isCompact: true)

            // Exercise info
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Text("Target: \(exercise.targetArea)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Position preview teaser
                if let start = exercise.startPosition {
                    Text(start)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .italic()
                }

                HStack(spacing: AppSpacing.sm) {
                    Text("\(exercise.sets) sets \u{00D7} \(exercise.reps)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    DifficultyBadge(difficulty: exercise.difficulty)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var savePlanButton: some View {
        VStack(spacing: AppSpacing.sm) {
            if let error = viewModel.saveError {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.warning)
                    Text("Failed to save: \(error)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Button(action: { viewModel.savePlanToFirestore() }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Save")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if viewModel.showSaveSuccess {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.success)
                    Text("Plan saved successfully!")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.success)
                }
            } else {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    viewModel.savePlanToFirestore()
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(viewModel.isSaving ? "Saving..." : "Save Plan")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isSaving)
            }
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "figure.walk",
            title: "No Plan Available",
            subtitle: "Generate a plan from your analysis results"
        )
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - DateFormatter extensions

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()

    static let shortWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
