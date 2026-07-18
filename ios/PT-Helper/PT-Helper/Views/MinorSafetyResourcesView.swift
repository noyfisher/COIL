import SwiftUI

/// Teen-facing safety resources (Anthropic minors program). Shown once to
/// minors after they land in the app, and always available from Settings.
/// The parent binding drives dismissal via the `onDismiss` callback — this view
/// holds NO `@Environment(\.dismiss)` (see Gotchas #1).
struct MinorSafetyResourcesView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.coolGradient)
                            .padding(.top, AppSpacing.xxl)

                        Text("Staying Safe While You Recover")
                            .font(.system(.title2, design: .serif).weight(.bold))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xl)

                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            safetySection(
                                icon: "graduationcap.fill",
                                color: AppColors.accent,
                                title: "A learning tool, not a doctor",
                                text: "This app's analysis is educational. A real diagnosis needs a real clinician — especially while you're still growing."
                            )

                            safetySection(
                                icon: "person.2.fill",
                                color: AppColors.success,
                                title: "Bring in an adult",
                                text: "Share your results with a parent, guardian, coach, or school athletic trainer before starting a plan. Growing bodies have growth plates, so the same pain can mean something different for teens."
                            )

                            safetySection(
                                icon: "hand.raised.fill",
                                color: AppColors.warning,
                                title: "Stop if it hurts",
                                text: "Sharp pain, swelling, numbness, or pain that wakes you up at night means stop the exercise and tell an adult."
                            )

                            safetySection(
                                icon: "phone.fill",
                                color: AppColors.danger,
                                title: "Emergencies",
                                text: "Severe pain after an injury, chest pain, trouble breathing, or sudden weakness or numbness: call 911 or tell an adult immediately."
                            )

                            safetySection(
                                icon: "heart.fill",
                                color: AppColors.accent,
                                title: "Feeling overwhelmed?",
                                text: "If you're struggling with stress, your body image, or anything else, you can call or text 988 (Suicide & Crisis Lifeline) any time, free and confidential."
                            )

                            safetySection(
                                icon: "flag.fill",
                                color: AppColors.warning,
                                title: "See something wrong in the app?",
                                text: "Use Settings → Report a Concern and we'll look into it."
                            )
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        Button(action: onDismiss) {
                            Text("Got it")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppColors.accent)
                                .foregroundColor(AppColors.ctaText)
                                .font(AppFonts.cardTitle)
                                .cornerRadius(AppCorners.large)
                        }
                        .accessibilityIdentifier("minorSafety.gotItButton")
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.lg)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Safety Resources")
            .navigationBarTitleDisplayMode(.inline)
        }
        .trackScreen("MinorSafetyResources")
    }

    private func safetySection(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFonts.smallSemiBold)
                Text(text)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    MinorSafetyResourcesView(onDismiss: {})
}
