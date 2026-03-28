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
            VStack(spacing: AppSpacing.md) {
                ForEach(levels, id: \.0) { level, icon, subtitle in
                    let isSelected = viewModel.userProfile.activityLevel == level
                    Button(action: { viewModel.userProfile.activityLevel = level }) {
                        HStack(spacing: AppSpacing.lg) {
                            Image(systemName: icon)
                                .font(.title3)
                                .foregroundColor(isSelected ? .white : AppColors.accent)
                                .frame(width: 44, height: 44)
                                .background(isSelected ? AppColors.accent : AppColors.accentTint)
                                .cornerRadius(AppCorners.medium)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(level)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(isSelected ? .white : .primary)
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                            }

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.title3)
                            }
                        }
                        .padding(AppSpacing.lg)
                        .background(isSelected ? AppColors.accent : AppColors.cardBackground)
                        .cornerRadius(AppCorners.card)
                        .shadow(color: .black.opacity(isSelected ? 0 : 0.04), radius: 8, y: 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.card)
                                .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
                        )
                    }
                }

                CardSection(icon: "sportscourt", color: .green, title: "Primary Sport or Activity") {
                    TextField("e.g. Basketball, Running, Yoga...", text: $viewModel.userProfile.primarySport.bound)
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.medium)
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
    }
}
