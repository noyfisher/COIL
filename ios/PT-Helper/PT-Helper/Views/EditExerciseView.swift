import SwiftUI

/// Sheet for editing a single exercise's mutable properties.
struct EditExerciseView: View {
    @Binding var exercise: RehabExercise
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var sets: Int = 3
    @State private var reps: String = "10"
    @State private var restSeconds: Int = 30
    @State private var description: String = ""
    @State private var difficulty: RehabExercise.Difficulty = .beginner

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Name
                        CardSection(icon: "textformat", color: .blue, title: "Exercise Name") {
                            TextField("Exercise name", text: $name)
                                .font(.body)
                                .padding(AppSpacing.md)
                                .background(AppColors.inputBackground)
                                .cornerRadius(AppCorners.medium)
                        }

                        // Sets & Reps
                        CardSection(icon: "arrow.triangle.2.circlepath", color: .green, title: "Sets & Reps") {
                            VStack(spacing: AppSpacing.md) {
                                HStack {
                                    Text("Sets")
                                        .font(.subheadline)
                                    Spacer()
                                    Stepper("\(sets)", value: $sets, in: 1...10)
                                        .fixedSize()
                                }

                                HStack {
                                    Text("Reps")
                                        .font(.subheadline)
                                    Spacer()
                                    TextField("Reps", text: $reps)
                                        .font(.body)
                                        .multilineTextAlignment(.trailing)
                                        .frame(width: 80)
                                        .padding(AppSpacing.sm)
                                        .background(AppColors.inputBackground)
                                        .cornerRadius(AppCorners.small)
                                }

                                HStack {
                                    Text("Rest (seconds)")
                                        .font(.subheadline)
                                    Spacer()
                                    Stepper("\(restSeconds)s", value: $restSeconds, in: 5...180, step: 5)
                                        .fixedSize()
                                }
                            }
                        }

                        // Difficulty
                        CardSection(icon: "gauge.with.dots.needle.33percent", color: .orange, title: "Difficulty") {
                            Picker("Difficulty", selection: $difficulty) {
                                ForEach(RehabExercise.Difficulty.allCases, id: \.self) { level in
                                    Text(level.rawValue.capitalized).tag(level)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // Description
                        CardSection(icon: "text.alignleft", color: .purple, title: "Description") {
                            TextField("Exercise description", text: $description, axis: .vertical)
                                .lineLimit(3...8)
                                .padding(AppSpacing.md)
                                .background(AppColors.inputBackground)
                                .cornerRadius(AppCorners.medium)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        exercise.name = name
                        exercise.sets = sets
                        exercise.reps = reps
                        exercise.restSeconds = restSeconds
                        exercise.description = description
                        exercise.difficulty = difficulty
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            name = exercise.name
            sets = exercise.sets
            reps = exercise.reps
            restSeconds = exercise.restSeconds
            description = exercise.description
            difficulty = exercise.difficulty
        }
        .trackScreen("EditExercise")
    }
}
