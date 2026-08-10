import SwiftUI

/// Brief post-completion feedback. Drives progression: "easier" (repeated)
/// advances future routines, "too much" or concerning pain regresses them —
/// see `PreventionRoutineEngine.decideProgression`.
struct PreventionFeedbackSheet: View {
    @ObservedObject var viewModel: PreventionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var difficulty: PreventionDifficultyRating?
    @State private var pain: PreventionPainLevel?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("How did that feel?")
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.primaryText)
                    FlowLayout(spacing: AppSpacing.sm) {
                        ForEach(PreventionDifficultyRating.allCases) { option in
                            ChipButton(label: option.displayName, isSelected: difficulty == option) {
                                difficulty = option
                            }
                            .accessibilityIdentifier("prevention.feedback.\(option.rawValue)Button")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Any pain during or after? (Optional)")
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.primaryText)
                    FlowLayout(spacing: AppSpacing.sm) {
                        ForEach(PreventionPainLevel.allCases) { option in
                            ChipButton(label: option.displayName, isSelected: pain == option) {
                                pain = (pain == option) ? nil : option
                            }
                            .accessibilityIdentifier("prevention.feedback.pain.\(option.rawValue)Button")
                        }
                    }
                }

                Spacer()

                Button("Submit Feedback") {
                    guard let difficulty else { return }
                    viewModel.submitFeedback(difficulty: difficulty, pain: pain)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle(isDisabled: difficulty == nil))
                .disabled(difficulty == nil)
                .accessibilityIdentifier("prevention.feedback.submitButton")

                Button("Skip") {
                    viewModel.dismissFeedback()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("prevention.feedback.skipButton")
            }
            .padding(AppSpacing.lg)
            .background(AppColors.pageBackground.ignoresSafeArea())
            .navigationTitle("Quick Feedback")
            .navigationBarTitleDisplayMode(.inline)
        }
        .trackScreen("PreventionFeedback")
    }
}
