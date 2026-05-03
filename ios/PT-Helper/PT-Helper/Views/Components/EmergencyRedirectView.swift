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
                    .font(.body)
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
                                    .font(.footnote)
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
                    Button(action: callEmergencyServices) {
                        Label("Call Emergency Services", systemImage: "phone.fill")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.danger)
                            .cornerRadius(AppCorners.pill)
                    }
                    .accessibilityIdentifier("emergencyRedirect.callCta")

                    Button(action: onDismiss) {
                        Text("Go Back")
                            .font(.subheadline)
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

    private func callEmergencyServices() {
        // US-default for v1. Future: honor locale. 911 is overwhelmingly the safest
        // single-number fallback for US users; non-US users will see the screen guide
        // them to their local services.
        if let url = URL(string: "tel://911"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
