import SwiftUI

/// Shown when a user returns after 3+ months of inactivity.
/// Asks whether their health has changed before proceeding to injury analysis.
struct HealthCheckPromptView: View {
    var onUpdateProfile: () -> Void
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Icon
            Image(systemName: "heart.text.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(AppColors.warmGradient)

            // Heading
            VStack(spacing: AppSpacing.sm) {
                Text("Welcome Back!")
                    .font(.system(.title, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)

                Text("It's been a while since your last visit. Have there been any changes to your health?")
                    .font(.body)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            Spacer()

            // Action buttons
            VStack(spacing: AppSpacing.md) {
                Button(action: onUpdateProfile) {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text("Yes, Update My Profile")
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(AppColors.ctaText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColors.ctaBackground)
                    .cornerRadius(AppCorners.card)
                }

                Button(action: onContinue) {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("No, Continue to Analysis")
                    }
                    .font(.body.weight(.medium))
                    .foregroundColor(AppColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCorners.card)
                            .stroke(AppColors.subtleBorder, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
        .background(AppColors.bgGradient.ignoresSafeArea())
        .trackScreen("HealthCheckPrompt")
    }
}
