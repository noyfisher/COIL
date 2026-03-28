import SwiftUI

struct WellnessPlanView: View {
    @ObservedObject var viewModel: WellnessPlanViewModel
    let wellnessResult: WellnessAnalysisResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            if viewModel.isGenerating {
                generatingView
            } else if let plan = viewModel.wellnessPlan {
                planContentView(plan)
            } else if let error = viewModel.generationError {
                errorView(error)
            }
        }
        .navigationTitle("Wellness Plan")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Plan Saved!", isPresented: $viewModel.showSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your wellness plan has been saved. You can find it in your Rehab tab.")
        }
        .trackScreen("WellnessPlan")
    }

    // MARK: - Generating View

    private var generatingView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "figure.flexibility")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [.teal, .green], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Building Your Plan")
                    .font(.system(.title2, design: .serif).weight(.bold))
                Text("Creating personalized exercises and habits...")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
            }

            ProgressView()
                .scaleEffect(1.3)
                .tint(AppColors.accent)

            Spacer()
        }
    }

    // MARK: - Plan Content

    private func planContentView(_ plan: RehabPlan) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Plan header
                VStack(spacing: AppSpacing.sm) {
                    Text(plan.planName)
                        .font(.system(.title3, design: .serif).weight(.bold))
                    Text("\(plan.exercises.count) exercises · \(plan.totalWeeks) weeks")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.top, AppSpacing.md)

                // Warnings
                if !viewModel.rehabPlanWarnings.isEmpty {
                    warningsBanner
                }

                // Notes
                if let notes = plan.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: AppSpacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(AppColors.accent)
                        Text(notes)
                            .font(.subheadline)
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.accentTint)
                    .cornerRadius(AppCorners.medium)
                }

                // Exercises
                ForEach(plan.exercises) { exercise in
                    exerciseCard(exercise)
                }

                // Save button
                saveButton

                // Back button
                Button(action: { dismiss() }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "chevron.left")
                        Text("Back to Recommendations")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.bottom, AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: - Exercise Card

    private func exerciseCard(_ exercise: RehabExercise) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                ExerciseImageView(exercise: exercise, isCompact: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline)
                    Text(exercise.targetArea)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    HStack(spacing: AppSpacing.sm) {
                        Text("\(exercise.sets) sets")
                        Text("·")
                        Text("\(exercise.reps) reps")
                        Text("·")
                        Text(exercise.difficulty.rawValue.capitalized)
                            .foregroundColor(difficultyColor(exercise.difficulty))
                    }
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                // Verification badge
                if let status = viewModel.exerciseVerifications[exercise.name] {
                    verificationBadge(status)
                }
            }

            Text(exercise.description)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)

            // Tips
            if !exercise.tips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tips")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.teal)
                    ForEach(exercise.tips, id: \.self) { tip in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(tip)
                        }
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.xl)
        .shadow(color: AppColors.cardShadowColor, radius: 6, y: 2)
    }

    private func difficultyColor(_ difficulty: RehabExercise.Difficulty) -> Color {
        switch difficulty {
        case .beginner: return AppColors.success
        case .intermediate: return AppColors.warning
        case .advanced: return AppColors.danger
        }
    }

    @ViewBuilder
    private func verificationBadge(_ status: ExerciseVerificationStatus) -> some View {
        switch status {
        case .verified, .crossModelVerified:
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(AppColors.success)
                .font(.caption)
        case .contraindicated:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(AppColors.danger)
                .font(.caption)
        case .crossModelFlagged:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(AppColors.warning)
                .font(.caption)
        case .checking:
            ProgressView()
                .scaleEffect(0.6)
        case .crossModelFailed:
            Image(systemName: "questionmark.circle")
                .foregroundColor(AppColors.secondaryText)
                .font(.caption)
        }
    }

    // MARK: - Warnings

    private var warningsBanner: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(viewModel.rehabPlanWarnings.indices, id: \.self) { index in
                let warning = viewModel.rehabPlanWarnings[index]
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.warning)
                        .font(.caption)
                    Text(warning.message)
                        .font(.caption)
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.warning.opacity(0.1))
        .cornerRadius(AppCorners.medium)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button(action: { viewModel.savePlanToFirestore() }) {
            HStack(spacing: AppSpacing.sm) {
                if viewModel.isSaving {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
                Text(viewModel.isSaving ? "Saving..." : "Save Wellness Plan")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(viewModel.isSaving)
        .padding(.top, AppSpacing.lg)
        .accessibilityIdentifier("wellnessPlan.saveButton")
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.warning)
            Text("Plan Generation Failed")
                .font(.system(.title2, design: .serif).weight(.bold))
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
            Button(action: {
                viewModel.generateWellnessPlan(from: wellnessResult)
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxl)
    }
}
