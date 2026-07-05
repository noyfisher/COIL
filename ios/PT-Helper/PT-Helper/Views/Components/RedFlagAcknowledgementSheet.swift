import SwiftUI

/// Friction gate shown before a user proceeds to build a self-guided rehab plan
/// from an analysis that surfaced red-flag warnings. Unlike `EmergencyRedirectView`
/// (which blocks entirely for `.emergency` findings), this sheet lets the user
/// continue after an explicit, recorded acknowledgement of the risk.
///
/// Layout mirrors `SeriousWarningModal` (drag handle, shield icon, warning list card,
/// medium/large detents). The acknowledgement is persisted locally via
/// `SeriousWarningAcknowledgements` and recorded server-side via
/// `RiskAcknowledgementRecorder`.
struct RedFlagAcknowledgementSheet: View {
    let analysisId: String
    let warningMessages: [String]

    /// Called when the user accepts the risk and wants to proceed to build a plan.
    let onAcknowledge: () -> Void

    /// Called when the user backs out ("Not now").
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

                    Text("Please Read Before Continuing")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.primaryText)
                        .multilineTextAlignment(.center)

                    Text("Your results include warnings that a clinician should look at before you start a self-guided plan. You can still build a plan, but you do so at your own risk.")
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
                Button(action: onAcknowledge) {
                    Text("I understand the risks — build my plan")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.ctaBackground)
                        .cornerRadius(AppCorners.pill)
                }
                .accessibilityIdentifier("redFlagAcknowledgement.acknowledgeButton")

                Button(action: onDismiss) {
                    Text("Not now")
                        .font(.footnote)
                        .foregroundColor(AppColors.mutedText)
                }
                .accessibilityIdentifier("redFlagAcknowledgement.dismissButton")
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}
