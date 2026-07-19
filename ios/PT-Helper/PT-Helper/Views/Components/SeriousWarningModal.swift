import SwiftUI

/// Modal acknowledgement gate shown before a plan containing `.serious` findings is displayed.
///
/// Serious findings are plan-level contraindications that need the user's explicit informed
/// consent to proceed: osteoporosis + impact, blood-thinners + balance/fall-risk work, a
/// post-surgical restriction violation, a contraindicated substitute exercise.
///
/// The modal is gated by `@AppStorage("strictValidationV1Enabled")`. Acknowledgements are
/// persisted per planId via `SeriousWarningAcknowledgements` so the modal doesn't re-fire
/// on every reopen of the same plan.
///
/// `.emergency` severity is NOT routed through this modal — it goes to
/// `EmergencyRedirectView`, which is never gated.
struct SeriousWarningModal: View {
    let planId: String
    let warningMessages: [String]

    /// Called when the user accepts the risk and wants to proceed with the plan as-is.
    let onAcknowledge: () -> Void

    /// Called when the user asks for a revised (safer) plan.
    let onRequestSaferPlan: () -> Void

    /// Called when the user dismisses without deciding (e.g. taps outside).
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .frame(width: 40, height: 4)
                .foregroundColor(AppColors.mutedText.opacity(0.4))
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.md)

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(AppColors.warning)
                        .accessibilityHidden(true)

                    Text("Safety Review Required")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.primaryText)

                    Text("This plan contains exercises that may not be appropriate for some items in your health profile. Please review the concerns below and talk to your PT before starting.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppColors.secondaryText)
                        .padding(.horizontal, AppSpacing.lg)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(warningMessages, id: \.self) { msg in
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(AppColors.warning)
                                    .font(.caption)
                                Text(msg)
                                    .font(.footnote)
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                    }
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.warning.opacity(0.10))
                    .cornerRadius(AppCorners.medium)
                }
                .padding(.horizontal, AppSpacing.xl)
            }

            VStack(spacing: AppSpacing.md) {
                Button(action: {
                    SeriousWarningAcknowledgements.acknowledge(planId: planId)
                    onAcknowledge()
                }) {
                    Text("I've read this & accept the risk")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.ctaBackground)
                        .cornerRadius(AppCorners.pill)
                }
                .accessibilityIdentifier("seriousWarning.acknowledgeButton")

                Button(action: onRequestSaferPlan) {
                    Text("Request a safer plan")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                }
                .accessibilityIdentifier("seriousWarning.requestSaferPlanButton")

                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.footnote)
                        .foregroundColor(AppColors.mutedText)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
