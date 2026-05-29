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
    @State private var isSaved = false
    @State private var insightText: String?

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Celebration header
                celebrationHeader

                // Workout stats
                statsGrid

                // Adaptive progression insight
                if let insight = insightText {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundColor(.yellow)
                        Text(insight)
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(AppSpacing.md)
                    .background(Color.yellow.opacity(0.08))
                    .cornerRadius(AppCorners.medium)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Pain input
                CardSection(icon: "waveform.path.ecg", color: painColor, title: "How do you feel?") {
                    VStack(spacing: AppSpacing.md) {
                        HStack {
                            Text("\(Int(overallPain))")
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .foregroundColor(painColor)
                            Text("/ 10")
                                .font(.title3)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                        }
                        Slider(value: $overallPain, in: 0...10, step: 1)
                            .tint(painColor)
                        HStack {
                            Text("No pain")
                                .font(.caption2)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Text("Severe")
                                .font(.caption2)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }

                // Per-region pain
                RegionPainInputView(
                    regionPainLevels: $regionPainLevels,
                    suggestedRegions: suggestedRegions
                )

                // Notes
                CardSection(icon: "note.text", color: AppColors.accent, title: "Session Notes") {
                    TextField("How did the session go?", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.medium)
                }

                // Save / Done button
                if isSaved {
                    Button(action: { dismiss() }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Done")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("workoutSummary.doneButton")
                } else {
                    Button(action: saveSession) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save & Done")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("workoutSummary.saveButton")
                }

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
        .onAppear {
            // Compute trajectory insight from previous sessions for this plan
            let planSessions = workoutViewModel.sessions
                .filter { $0.planId == vm.plan.id }
                .sorted { $0.date < $1.date }
            guard planSessions.count >= 2 else { return }
            let recentPain = planSessions.suffix(3).map(\.painLevel)
            let avgPain = recentPain.reduce(0, +) / Double(recentPain.count)
            if planSessions.count >= 3 {
                let earlyPain = planSessions.prefix(min(3, planSessions.count / 2)).map(\.painLevel)
                let earlyAvg = earlyPain.reduce(0, +) / Double(earlyPain.count)
                let delta = avgPain - earlyAvg
                if delta <= -1.0 {
                    insightText = "Your recent pain is trending down (avg \(String(format: "%.1f", avgPain))/10). Great progress!"
                } else if delta >= 1.0 {
                    insightText = "Pain has been trending up recently (avg \(String(format: "%.1f", avgPain))/10). Listen to your body."
                }
            }
        }
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
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundColor(AppColors.primaryText)

            Text(vm.plan.planName)
                .font(AppFonts.body)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xl)
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        HStack(spacing: AppSpacing.md) {
            summaryStatCard(
                icon: "clock",
                color: AppColors.accent,
                value: formattedDuration,
                label: "Duration"
            )
            summaryStatCard(
                icon: "checkmark.circle",
                color: AppColors.success,
                value: "\(vm.completedExercises.count)",
                label: "Completed"
            )
            summaryStatCard(
                icon: "forward",
                color: AppColors.warning,
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
                .foregroundColor(AppColors.primaryText)

            Text(label)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Helpers

    private func saveSession() {
        let session = vm.buildSession(
            painLevel: overallPain,
            regionPainLevels: regionPainLevels.isEmpty ? nil : regionPainLevels,
            notes: notes
        )
        workoutViewModel.addSession(session: session)
        isSaved = true

        let notification = UINotificationFeedbackGenerator()
        notification.notificationOccurred(.success)

        withAnimation(AppAnimations.bouncy) {
            showSavedConfirmation = true
        }
        // Hide celebration overlay after 2 seconds, but keep user on screen
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showSavedConfirmation = false
            }
        }
    }

    private var formattedDuration: String {
        let minutes = Int(vm.totalElapsedTime) / 60
        if minutes < 1 { return "<1m" }
        return "\(minutes)m"
    }

    private var painColor: Color {
        switch Int(overallPain) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
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
