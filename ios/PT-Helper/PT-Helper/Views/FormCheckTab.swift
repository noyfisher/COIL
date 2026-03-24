import SwiftUI

/// Standalone entry point for form checking — lets users pick an exercise
/// from their saved plans and launch form analysis.
struct FormCheckTab: View {
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @State private var selectedExercise: RehabExercise?
    @State private var showFormAnalysis = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                if savedPlansVM.rehabPlans.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
            }
            .navigationTitle("Form Check")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedExercise) { exercise in
                FormAnalysisView(exercise: exercise)
            }
        }
        .trackScreen("FormCheckTab")
    }

    // MARK: - Exercise List

    private var exerciseList: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Select an exercise to check your form")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Exercises grouped by plan
                ForEach(savedPlansVM.rehabPlans) { plan in
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text(plan.planName)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ForEach(plan.exercises) { exercise in
                            exerciseRow(exercise)
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func exerciseRow(_ exercise: RehabExercise) -> some View {
        Button {
            selectedExercise = exercise
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "figure.mixed.cardio")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 40, height: 40)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(AppCorners.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("\(exercise.targetArea) • \(exercise.sets) sets × \(exercise.reps)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "video.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("formCheck.exercise.\(exercise.name)")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "video.badge.checkmark")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            VStack(spacing: AppSpacing.sm) {
                Text("No Exercises Available")
                    .font(.title3.weight(.bold))

                Text("Create a rehab plan first, then you can check your form on any exercise.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }
}

// MARK: - Make RehabExercise Identifiable for sheet(item:)

// RehabExercise already conforms to Identifiable via its id: UUID property
