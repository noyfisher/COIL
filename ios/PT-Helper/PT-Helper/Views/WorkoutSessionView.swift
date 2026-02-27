import SwiftUI

struct WorkoutSessionView: View {
    @StateObject private var viewModel = WorkoutViewModel()
    @StateObject private var savedPlansVM = SavedPlansViewModel()
    @State private var painLevel: Double = 5
    @State private var durationMinutes: Double = 30
    @State private var notes: String = ""
    @State private var selectedExercises: Set<String> = []
    @State private var customExercise: String = ""
    @State private var showSavedConfirmation = false

    var body: some View {
        ZStack {
            AppColors.pageBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Pain level
                    CardSection(icon: "waveform.path.ecg", color: painColor, title: "Pain Level") {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Text("\(Int(painLevel))")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(painColor)
                                Text("/ 10")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(painDescription)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(painColor)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.xs)
                                    .background(painColor.opacity(0.12))
                                    .cornerRadius(AppCorners.small)
                            }

                            Slider(value: $painLevel, in: 0...10, step: 1)
                                .tint(painColor)
                                .accessibilityLabel("Pain level")
                                .accessibilityValue("\(Int(painLevel)) out of 10, \(painDescription)")

                            HStack {
                                Text("No pain")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Severe")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Duration
                    CardSection(icon: "timer", color: .orange, title: "Duration") {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Text("\(Int(durationMinutes))")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                                Text("min")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }

                            Slider(value: $durationMinutes, in: 5...120, step: 5)
                                .tint(.orange)
                                .accessibilityLabel("Workout duration")
                                .accessibilityValue("\(Int(durationMinutes)) minutes")

                            HStack {
                                Text("5 min")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("2 hours")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Exercises performed
                    CardSection(icon: "figure.strengthtraining.traditional", color: .green, title: "Exercises Performed") {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            if !availableExercises.isEmpty {
                                Text("From your rehab plans:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                ForEach(availableExercises, id: \.self) { name in
                                    Button(action: {
                                        if selectedExercises.contains(name) {
                                            selectedExercises.remove(name)
                                        } else {
                                            selectedExercises.insert(name)
                                        }
                                    }) {
                                        HStack(spacing: AppSpacing.sm) {
                                            Image(systemName: selectedExercises.contains(name) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedExercises.contains(name) ? .green : .secondary)
                                            Text(name)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.vertical, AppSpacing.xs)
                                    }
                                }
                            }

                            // Custom exercise input
                            HStack(spacing: AppSpacing.sm) {
                                TextField("Add other exercise...", text: $customExercise)
                                    .font(.subheadline)
                                    .padding(.horizontal, AppSpacing.md)
                                    .padding(.vertical, AppSpacing.sm)
                                    .background(AppColors.inputBackground)
                                    .cornerRadius(AppCorners.small)
                                    .submitLabel(.done)
                                    .onSubmit { addCustomExercise() }
                                Button(action: addCustomExercise) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                        .foregroundColor(customExercise.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .green)
                                }
                                .disabled(customExercise.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            if !selectedExercises.isEmpty {
                                Text("\(selectedExercises.count) exercise(s) selected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    // Notes
                    CardSection(icon: "note.text", color: .purple, title: "Session Notes") {
                        TextField("How did the session go?", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(AppSpacing.md)
                            .background(AppColors.inputBackground)
                            .cornerRadius(AppCorners.medium)
                    }

                    // Save button
                    Button(action: saveSession) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Session")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    // Session history
                    if viewModel.sessions.isEmpty {
                        EmptyStateView(
                            icon: "figure.strengthtraining.traditional",
                            title: "No Sessions Yet",
                            subtitle: "Log your first workout session above"
                        )
                    } else {
                        SectionHeader(icon: "clock.arrow.circlepath", color: .blue, title: "Recent Sessions")

                        ForEach(viewModel.sessions.reversed(), id: \.id) { session in
                            sessionCard(for: session)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Workout Session")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showSavedConfirmation {
                savedConfirmationOverlay
            }
        }
    }

    // MARK: - Helpers

    private func saveSession() {
        let session = WorkoutSession(
            id: UUID(),
            date: Date(),
            duration: durationMinutes * 60,
            painLevel: painLevel,
            isCompleted: true,
            exercisesPerformed: Array(selectedExercises),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty ? nil : notes
        )
        viewModel.addSession(session: session)

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        withAnimation(.spring(response: 0.3)) {
            showSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSavedConfirmation = false }
        }

        // Reset form
        painLevel = 5
        durationMinutes = 30
        notes = ""
        selectedExercises = []
    }

    private func addCustomExercise() {
        let trimmed = customExercise.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        selectedExercises.insert(trimmed)
        customExercise = ""
    }

    /// Unique exercise names from all saved rehab plans
    private var availableExercises: [String] {
        let allNames = savedPlansVM.rehabPlans.flatMap { $0.exercises.map { $0.name } }
        return Array(Set(allNames)).sorted()
    }

    private var painColor: Color {
        switch Int(painLevel) {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }

    private var painDescription: String {
        switch Int(painLevel) {
        case 0: return "None"
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default: return "Extreme"
        }
    }

    private func sessionCard(for session: WorkoutSession) -> some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(colorForPain(session.painLevel).opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Text("\(Int(session.painLevel))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(colorForPain(session.painLevel))
                )

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(session.date, style: .date)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
                Text("\(Int(session.duration / 60)) minutes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !session.exercisesPerformed.isEmpty {
                    Text(session.exercisesPerformed.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
        .cardStyle()
    }

    private func colorForPain(_ level: Double) -> Color {
        switch Int(level) {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }

    private var savedConfirmationOverlay: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)
            Text("Session Saved!")
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(AppSpacing.xxl)
        .background(.ultraThinMaterial)
        .cornerRadius(AppCorners.large)
        .transition(.scale.combined(with: .opacity))
    }
}
