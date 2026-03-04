import SwiftUI

/// Post-workout completion summary with pain input and session saving.
struct GuidedWorkoutSummaryView: View {
    @ObservedObject var vm: GuidedWorkoutViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var overallPain: Double = 3
    @State private var regionPainLevels: [String: Double] = [:]
    @State private var notes: String = ""
    @State private var showSavedConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Celebration header
                celebrationHeader

                // Workout stats
                statsGrid

                // Pain input
                CardSection(icon: "waveform.path.ecg", color: painColor, title: "How do you feel?") {
                    VStack(spacing: AppSpacing.md) {
                        HStack {
                            Text("\(Int(overallPain))")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(painColor)
                            Text("/ 10")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        Slider(value: $overallPain, in: 0...10, step: 1)
                            .tint(painColor)
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

                // Per-region pain
                RegionPainInputView(
                    regionPainLevels: $regionPainLevels,
                    suggestedRegions: suggestedRegions
                )

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
                        Text("Save & Done")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .overlay {
            if showSavedConfirmation {
                CelebrationOverlay(
                    icon: "checkmark.circle.fill",
                    message: "Workout Saved!",
                    iconColor: AppColors.success
                )
            }
        }
        .trackScreen("GuidedWorkoutSummary")
    }

    // MARK: - Celebration Header

    private var celebrationHeader: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 50))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolEffect(.bounce, value: true)

            Text("Workout Complete!")
                .font(.title2.weight(.bold))

            Text(vm.plan.planName)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: AppSpacing.md) {
            summaryStatCard(
                icon: "clock",
                color: .blue,
                value: formattedDuration,
                label: "Duration"
            )
            summaryStatCard(
                icon: "checkmark.circle",
                color: .green,
                value: "\(vm.completedExercises.count)",
                label: "Completed"
            )
            summaryStatCard(
                icon: "forward",
                color: .orange,
                value: "\(vm.skippedExercises.count)",
                label: "Skipped"
            )
        }
    }

    private func summaryStatCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .cornerRadius(AppCorners.small)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Helpers

    private func saveSession() {
        let session = vm.buildSession(
            painLevel: overallPain,
            regionPainLevels: regionPainLevels.isEmpty ? nil : regionPainLevels,
            notes: notes
        )
        workoutViewModel.addSession(session: session)

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        withAnimation(AppAnimations.bouncy) {
            showSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            dismiss()
        }
    }

    private var formattedDuration: String {
        let minutes = Int(vm.totalElapsedTime) / 60
        if minutes < 1 { return "<1m" }
        return "\(minutes)m"
    }

    private var painColor: Color {
        switch Int(overallPain) {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }

    /// Suggested regions from the plan's exercises
    private var suggestedRegions: [String] {
        let targets = vm.plan.exercises.map {
            $0.targetArea.lowercased().replacingOccurrences(of: " ", with: "_")
        }
        return Array(Set(targets)).sorted()
    }
}
