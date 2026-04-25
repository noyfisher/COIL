import SwiftUI

// MARK: - Tier 3 PR D: Outcome Prompt

/// Inline card asking the user how accurate the AI analysis turned out to be.
/// Shows after a plan has been active for ≥ 7 days. One-tap submission via
/// `OutcomeRecorder.shared.record(...)`.
///
/// Wire-up (intentionally NOT done in PR D — this is the data layer):
/// add to a Progress tab section guarded by:
///
///     if let plan = ..., let analysisId = ...,
///        OutcomeRecorder.shared.shouldShowPrompt(planStartDate: plan.startDate, analysisId: analysisId) {
///         OutcomePromptView(
///             analysisId: analysisId,
///             planId: plan.id,
///             planAgeDays: OutcomeRecorder.planAgeDays(planStartDate: plan.startDate)
///         ) { /* refresh trigger to re-check shouldShowPrompt */ }
///     }
struct OutcomePromptView: View {
    let analysisId: UUID
    let planId: UUID?
    let planAgeDays: Int?

    /// Called after a rating is submitted (or the user dismisses) so the
    /// containing view can re-evaluate `shouldShowPrompt` and hide.
    let onComplete: () -> Void

    @State private var isSubmitting = false
    @State private var submittedFeedback: OutcomeFeedback?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundColor(AppColors.accent)
                Text("How's it going?")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(AppColors.mutedText)
                }
                .accessibilityIdentifier("outcomePrompt.dismiss")
            }

            Text("Thinking back to the original analysis — how accurate did it turn out to be?")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let chosen = submittedFeedback {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: chosen.icon)
                        .foregroundColor(AppColors.success)
                    Text("Thanks — recorded as \(chosen.displayName.lowercased()).")
                        .font(.footnote)
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.top, AppSpacing.xs)
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(OutcomeFeedback.allCases) { feedback in
                        Button(action: { submit(feedback) }) {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: feedback.icon)
                                    .frame(width: 18)
                                Text(feedback.displayName)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .padding(.vertical, AppSpacing.sm)
                            .padding(.horizontal, AppSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.cardBackground)
                            .cornerRadius(AppCorners.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppCorners.medium)
                                    .stroke(AppColors.subtleBorder, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("outcomePrompt.\(feedback.rawValue)")
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.elevatedSurface.opacity(0.6))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Actions

    private func submit(_ feedback: OutcomeFeedback) {
        guard !isSubmitting else { return }
        isSubmitting = true
        OutcomeRecorder.shared.record(
            feedback,
            for: analysisId,
            planId: planId,
            planAgeDays: planAgeDays
        )
        withAnimation(AppAnimations.smooth) {
            submittedFeedback = feedback
        }
        // Auto-dismiss after a short confirmation pause so the parent view
        // can hide the prompt on the next render cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onComplete()
        }
    }

    private func dismiss() {
        // Mark "asked" by recording .notApplicable so the prompt doesn't
        // re-fire next time. Users who didn't engage = silent signal.
        OutcomeRecorder.shared.record(
            .notApplicable,
            for: analysisId,
            planId: planId,
            planAgeDays: planAgeDays
        )
        onComplete()
    }
}

#if DEBUG
struct OutcomePromptView_Previews: PreviewProvider {
    static var previews: some View {
        OutcomePromptView(
            analysisId: UUID(),
            planId: UUID(),
            planAgeDays: 12,
            onComplete: {}
        )
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
