import SwiftUI

struct ActivityLevelStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    let levels: [(String, String, String)] = [
        ("Sedentary", "figure.seated.side", "Little to no exercise"),
        ("Lightly Active", "figure.walk", "Light exercise 1-3 days/week"),
        ("Moderately Active", "figure.run", "Moderate exercise 3-5 days/week"),
        ("Very Active", "figure.strengthtraining.traditional", "Hard exercise 6-7 days/week"),
        ("Athlete", "medal.fill", "Competitive training & performance")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.sm) {
                ForEach(levels, id: \.0) { level, icon, subtitle in
                    let isSelected = viewModel.userProfile.activityLevel == level
                    Button(action: { viewModel.userProfile.activityLevel = level }) {
                        HStack(spacing: AppSpacing.lg) {
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundColor(isSelected ? .white : AppColors.accent)
                                .frame(width: 40, height: 40)
                                .background(isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.08))
                                .cornerRadius(AppCorners.medium)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(level)
                                    .font(Font.custom("Inter-SemiBold", size: 14))
                                    .foregroundColor(.white)
                                Text(subtitle)
                                    .font(Font.custom("Inter-Regular", size: 12))
                                    .foregroundColor(Color.white.opacity(isSelected ? 0.65 : 0.45))
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.white)
                                .font(.system(size: 18))
                                .opacity(isSelected ? 1 : 0)
                        }
                        .padding(AppSpacing.lg)
                        .background(isSelected ? AppColors.accent : OnboardingColors.cardBg)
                        .cornerRadius(AppCorners.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.card)
                                .stroke(isSelected ? AppColors.accent : OnboardingColors.cardBorder, lineWidth: 1.5)
                        )
                    }
                    .accessibilityIdentifier("onboarding.activityLevelOption")
                }

                // Primary sport
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Primary Sport or Activity")
                    DarkTextField(
                        placeholder: "e.g. Basketball, Running, Yoga...",
                        text: $viewModel.userProfile.primarySport.bound
                    )
                }
                .padding(.top, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .trackScreen("OnboardingActivityLevel")
    }
}
