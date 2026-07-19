import SwiftUI

/// Full-screen takeover shown when a `.emergency` severity finding surfaces during analysis.
///
/// Emergency findings are symptom-level red flags (cardiac pattern, cauda equina, stroke
/// signs, DVT signs). We do NOT show the normal analysis result — the user should seek
/// emergency care, not read an AI differential. This is a non-negotiable safety path and
/// is NOT gated by any feature flag.
struct EmergencyRedirectView: View {
    /// Short human-readable description of which red flag(s) fired (for logging & UI).
    let warningMessages: [String]

    /// Called when the user dismisses the screen (e.g. back-nav). Parent should clear
    /// analysis state so stale results don't re-navigate on the next screen update.
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()

            VStack(spacing: AppSpacing.xl) {
                Spacer()

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundColor(AppColors.danger)
                    .accessibilityHidden(true)

                Text("Seek Medical Attention")
                    .font(AppFonts.heroTitle)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.primaryText)

                Text("Your reported symptoms include warning signs that need urgent evaluation by a healthcare provider. This app cannot safely advise on your situation.")
                    .font(AppFonts.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(AppColors.secondaryText)
                    .padding(.horizontal, AppSpacing.xl)

                if !warningMessages.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ForEach(warningMessages, id: \.self) { msg in
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Text("•")
                                    .foregroundColor(AppColors.danger)
                                Text(msg)
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.primaryText)
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.danger.opacity(0.08))
                    .cornerRadius(AppCorners.medium)
                    .padding(.horizontal, AppSpacing.xl)
                }

                Spacer()

                VStack(spacing: AppSpacing.md) {
                    // Always display the number as large selectable text so a user
                    // in a crisis is never left staring at a dead button (audit #80).
                    Text(emergencyNumber)
                        .font(AppFonts.display)
                        .foregroundColor(AppColors.danger)
                        .textSelection(.enabled)
                        .accessibilityLabel("Emergency number \(emergencyNumber)")
                    Text("Call \(emergencyNumber) from a phone, or dial your local emergency number.")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)

                    Button(action: callEmergencyServices) {
                        Label("Call Emergency Services", systemImage: "phone.fill")
                            .font(AppFonts.bodySemiBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.danger)
                            .cornerRadius(AppCorners.pill)
                    }
                    .accessibilityIdentifier("emergencyRedirect.callCta")

                    Button(action: onDismiss) {
                        Text("Go Back")
                            .font(AppFonts.small)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    .padding(.top, AppSpacing.sm)
                    .accessibilityIdentifier("emergencyRedirect.goBack")
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    /// US-default for v1. Future: honor locale. The number is ALSO shown on screen
    /// as large selectable text, so it's usable even when the device can't dial.
    private let emergencyNumber = "911"

    private func callEmergencyServices() {
        if let url = URL(string: "tel://\(emergencyNumber)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        // If canOpenURL is false (iPad / non-cellular), the on-screen number above
        // is the fallback — no silent dead button in a crisis (audit #80).
    }
}
