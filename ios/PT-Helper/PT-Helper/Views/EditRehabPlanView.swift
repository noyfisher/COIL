import SwiftUI

/// Full editing view for a rehab plan: reorder, remove, edit exercises.
struct EditRehabPlanView: View {
    @Binding var plan: RehabPlan
    var onSave: (RehabPlan) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var exercises: [RehabExercise] = []
    @State private var planName: String = ""
    @State private var editingExerciseIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                List {
                    // Plan name
                    Section("Plan Name") {
                        TextField("Plan name", text: $planName)
                    }

                    // Exercises
                    Section("Exercises (\(exercises.count))") {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(exercise.sets) sets \u{00D7} \(exercise.reps) \u{2022} \(exercise.difficulty.rawValue.capitalized)")
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()

                                Button(action: { editingExerciseIndex = index }) {
                                    Image(systemName: "pencil.circle")
                                        .foregroundColor(AppColors.accent)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Edit \(exercise.name)")
                            }
                        }
                        .onMove(perform: moveExercise)
                        .onDelete(perform: deleteExercise)
                    }

                    // Add custom exercise
                    Section {
                        Button(action: addCustomExercise) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Custom Exercise")
                            }
                            .foregroundColor(AppColors.accentText)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Edit Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        plan.planName = planName
                        plan.exercises = exercises
                        plan.lastModifiedDate = Date()
                        onSave(plan)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(exercises.isEmpty)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(item: editingBinding) { _ in
                if let index = editingExerciseIndex, exercises.indices.contains(index) {
                    EditExerciseView(exercise: $exercises[index])
                }
            }
        }
        .onAppear {
            exercises = plan.exercises
            planName = plan.planName
        }
        .trackScreen("EditRehabPlan")
    }

    // MARK: - Actions

    private func moveExercise(from source: IndexSet, to destination: Int) {
        exercises.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteExercise(at offsets: IndexSet) {
        exercises.remove(atOffsets: offsets)
    }

    private func addCustomExercise() {
        let newExercise = RehabExercise(
            id: UUID(),
            name: "New Exercise",
            targetArea: "General",
            description: "Describe this exercise",
            sets: 3,
            reps: "10",
            restSeconds: 30,
            difficulty: .beginner,
            demonstrationIcon: "figure.flexibility",
            tips: [],
            contraindications: []
        )
        exercises.append(newExercise)
        editingExerciseIndex = exercises.count - 1
    }

    // Helper to create an identifiable binding for the sheet
    private var editingBinding: Binding<IdentifiableInt?> {
        Binding(
            get: {
                if let index = editingExerciseIndex {
                    return IdentifiableInt(value: index)
                }
                return nil
            },
            set: { newValue in
                editingExerciseIndex = newValue?.value
            }
        )
    }
}

/// Helper to make Int identifiable for sheet presentation
struct IdentifiableInt: Identifiable {
    let value: Int
    var id: Int { value }
}
