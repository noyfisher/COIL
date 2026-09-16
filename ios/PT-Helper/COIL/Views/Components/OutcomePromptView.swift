import SwiftUI

// MARK: - Tier 3 PR D: Outcome Prompt

/// Asks the user how accurate the AI analysis turned out to be. Shows after a plan
/// has been active for ≥ 7 days. One-tap submission via `OutcomeRecorder.shared.record(...)`.
///
/// Two presentations: `.card` (the original inline card, options always visible)
/// and `.banner` (a one-line row that expands in place when tapped — the Progress
/// tab uses this so the prompt stops competing with the content around it).
struct OutcomePromptView: View {
    enum Style { case card, banner }

    /// One source for the collapsed row's question — the visible label and the
    /// VoiceOver label must not drift apart.
    private static let bannerQuestion = "How accurate was your analysis?"

    let analysisId: UUID
    let planId: UUID?
    let planAgeDays: Int?
    var style: Style = .card

    /// Called after a rating is submitted (or the user dismisses) so the
    /// containing view can re-evaluate `shouldShowPrompt` and hide.
    let onComplete: () -> Void

    @State private var isSubmitting = false
    @State private var submittedFeedback: OutcomeFeedback?
    @State private var isExpanded = false

    var body: some View {
        switch style {
        case .card: cardBody
        case .banner: bannerBody
        }
    }

    // MARK: - Card (original layout; the dismiss glyph gained a 44pt hit area)

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundColor(AppColors.accent)
                Text("How's it going?")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                dismissButton
            }

            Text("Thinking back to the original analysis — how accurate did it turn out to be?")
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ratingContent
        }
        .padding(AppSpacing.lg)
        .background(AppColors.elevatedSurface.opacity(0.6))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Banner (collapsed row, expands in place)

    private var bannerBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    withAnimation(AppAnimations.smooth) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "sparkles")
                            .font(AppFonts.small)
                            .foregroundColor(AppColors.accent)
                        Text(Self.bannerQuestion)
                            .font(AppFonts.small)
                            .foregroundColor(AppColors.primaryText)
                        Spacer(minLength: 0)
                        if !isExpanded && submittedFeedback == nil {
                            Text("Rate")
                                .font(AppFonts.captionSemiBold)
                                .textCase(.uppercase)
                                .foregroundColor(AppColors.accentText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("outcomePrompt.expand")
                .accessibilityLabel(Self.bannerQuestion)
                .accessibilityHint(isExpanded ? "Collapses the rating options" : "Expands the rating options")

                dismissButton
            }

            // Stay open through the confirmation window: collapsing the row while
            // "Thanks — recorded as …" is showing would swallow the acknowledgement.
            if isExpanded || submittedFeedback != nil {
                ratingContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.xs)
        .background(AppColors.elevatedSurface.opacity(0.6))
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Shared pieces

    private var dismissButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(AppFonts.iconXS)
                .foregroundColor(AppColors.mutedText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("outcomePrompt.dismiss")
        .accessibilityLabel("Dismiss")
    }

    /// The four rating options, or the confirmation line once one is chosen.
    @ViewBuilder
    private var ratingContent: some View {
        if let chosen = submittedFeedback {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: chosen.icon)
                    .foregroundColor(AppColors.success)
                Text("Thanks — recorded as \(chosen.displayName.lowercased()).")
                    .font(AppFonts.caption)
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
                                .font(AppFonts.small)
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
        VStack(spacing: AppSpacing.lg) {
            OutcomePromptView(analysisId: UUID(), planId: UUID(), planAgeDays: 12, onComplete: {})
            OutcomePromptView(analysisId: UUID(), planId: UUID(), planAgeDays: 12, style: .banner, onComplete: {})
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
