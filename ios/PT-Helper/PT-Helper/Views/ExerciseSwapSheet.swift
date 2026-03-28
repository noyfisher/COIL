import SwiftUI

/// Sheet for swapping an exercise with AI-generated alternatives.
struct ExerciseSwapSheet: View {
    @StateObject private var vm: ExerciseSwapViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @Environment(\.dismiss) private var dismiss

    /// Callback when a substitute is selected. Passes the substitute exercise and updated plan.
    let onSwap: (RehabExercise, RehabPlan) -> Void

    init(exercise: RehabExercise, plan: RehabPlan,
         onSwap: @escaping (RehabExercise, RehabPlan) -> Void) {
        _vm = StateObject(wrappedValue: ExerciseSwapViewModel(exercise: exercise, plan: plan))
        self.onSwap = onSwap
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    loadingView
                } else if !vm.substitutes.isEmpty {
                    substituteListView
                } else {
                    reasonSelectionView
                }
            }
            .navigationTitle("Swap Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .trackScreen("ExerciseSwap")
    }

    // MARK: - Reason Selection

    private var reasonSelectionView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 40))
                        .foregroundStyle(AppColors.coolGradient)

                    Text("Why can't you do this exercise?")
                        .font(.system(.headline, design: .serif))
                        .foregroundColor(AppColors.primaryText)

                    Text(vm.exercise.name)
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.top, AppSpacing.xl)

                // Error banner (if retry after error)
                if let error = vm.error {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.warning.opacity(0.08))
                    .cornerRadius(AppCorners.medium)
                }

                // Reason buttons
                ForEach(SwapReason.allCases) { reason in
                    Button(action: {
                        vm.selectedReason = reason
                        Task { await vm.fetchSubstitutes() }
                    }) {
                        HStack(spacing: AppSpacing.lg) {
                            Image(systemName: reason.icon)
                                .font(.title3)
                                .foregroundColor(AppColors.accent)
                                .frame(width: 36, height: 36)
                                .background(AppColors.accentTint)
                                .cornerRadius(AppCorners.small)

                            Text(reason.displayName)
                                .font(.body.weight(.medium))
                                .foregroundColor(AppColors.primaryText)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(AppColors.mutedText.opacity(0.5))
                        }
                        .padding(AppSpacing.lg)
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.card)
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "figure.flexibility")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.success, AppColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Finding Alternatives")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("Looking for exercises that work for you...")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            ProgressView()
                .scaleEffect(1.2)
                .tint(AppColors.success)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Substitute List

    private var substituteListView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Text("Pick a Substitute")
                        .font(.system(.headline, design: .serif))
                        .foregroundColor(AppColors.primaryText)

                    Text("Replacing: \(vm.exercise.name)")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.top, AppSpacing.md)

                // Error banner
                if let error = vm.error {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        Spacer()
                        Button("Retry") {
                            Task { await vm.fetchSubstitutes() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.accent)
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.warning.opacity(0.08))
                    .cornerRadius(AppCorners.medium)
                }

                // Substitute cards
                ForEach(vm.substitutes) { substitute in
                    substituteCard(for: substitute)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
    }

    private func substituteCard(for substitute: RehabExercise) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Top row: image + name + badge
            HStack(spacing: AppSpacing.md) {
                ExerciseImageView(exercise: substitute, isCompact: true)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text(substitute.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)

                        Spacer()

                        if let status = vm.verificationStatuses[substitute.id] {
                            verificationBadge(for: status)
                        }
                    }

                    HStack(spacing: AppSpacing.sm) {
                        Text("\(substitute.sets) sets \u{00D7} \(substitute.reps)")
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppColors.secondaryText)

                        DifficultyBadge(difficulty: substitute.difficulty)
                    }
                }
            }

            // Why it helps
            if let reason = vm.substituteReasons[substitute.id] {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.yellow)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            // Contraindication warning
            if let status = vm.verificationStatuses[substitute.id],
               case .contraindicated(let reason) = status {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(AppColors.danger)
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(AppColors.danger)
                }
                .padding(AppSpacing.sm)
                .background(AppColors.danger.opacity(0.08))
                .cornerRadius(AppCorners.small)
            }

            // Select button
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                let updatedPlan = vm.selectSubstitute(substitute, savedPlansVM: savedPlansVM)
                onSwap(substitute, updatedPlan)
                dismiss()
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Select This Exercise")
                }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Verification Badge

    @ViewBuilder
    private func verificationBadge(for status: ExerciseVerificationStatus) -> some View {
        switch status {
        case .verified:
            Label("Verified", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.success)
        case .contraindicated:
            Label("Warning", systemImage: "xmark.octagon.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.danger)
        case .crossModelVerified:
            Label("Checked", systemImage: "checkmark.seal")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.accent)
        case .crossModelFlagged:
            Label("Review", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.warning)
        default:
            Label("Unreviewed", systemImage: "questionmark.circle")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.mutedText)
        }
    }
}
