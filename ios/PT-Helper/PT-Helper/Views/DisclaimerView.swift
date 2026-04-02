import SwiftUI

/// One-time disclaimer that must be accepted before using the analysis feature.
/// Stored as a simple boolean in UserDefaults (not sensitive data).
struct DisclaimerView: View {
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Icon
                        Image(systemName: "stethoscope")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.coolGradient)
                            .padding(.top, AppSpacing.xxl)

                        Text("Before You Begin")
                            .font(.system(.title2, design: .serif).weight(.bold))

                        // Disclaimer text
                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            disclaimerSection(
                                icon: "info.circle.fill",
                                color: AppColors.accent,
                                title: "Educational Tool Only",
                                text: "PT Helper provides general health information for educational purposes. It is not a medical device and does not provide medical diagnoses."
                            )

                            disclaimerSection(
                                icon: "person.fill",
                                color: AppColors.success,
                                title: "Not a Substitute for Professional Care",
                                text: "The information provided should not replace professional medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider for medical concerns."
                            )

                            disclaimerSection(
                                icon: "exclamationmark.triangle.fill",
                                color: AppColors.warning,
                                title: "Seek Emergency Care When Needed",
                                text: "If you experience severe pain, sudden weakness, difficulty breathing, or any symptoms you believe are a medical emergency, call 911 or go to your nearest emergency room immediately."
                            )

                            disclaimerSection(
                                icon: "lock.shield.fill",
                                color: AppColors.accent,
                                title: "Your Data",
                                text: "Your health information is stored securely and used only to provide personalized guidance. You can delete your account and all data at any time from Settings."
                            )
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        // Accept button
                        Button(action: {
                            DisclaimerManager.markAccepted()
                            onAccept()
                            dismiss()
                        }) {
                            Text("I Understand, Continue")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppColors.accent)
                                .foregroundColor(AppColors.ctaText)
                                .font(.headline)
                                .cornerRadius(AppCorners.large)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.lg)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Important Information")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .trackScreen("Disclaimer")
    }

    private func disclaimerSection(icon: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Disclaimer Manager

enum DisclaimerManager {
    private static let key = "hasAcceptedDisclaimer"

    static var hasAccepted: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markAccepted() {
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Reset (for testing or account deletion)
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
