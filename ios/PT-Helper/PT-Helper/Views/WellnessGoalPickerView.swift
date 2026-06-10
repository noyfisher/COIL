import SwiftUI

struct WellnessGoalPickerView: View {
    let userProfile: UserProfile
    @State private var selectedCategories: Set<GoalCategory> = []
    @State private var customGoalText: String = ""
    @State private var showDetailView = false
    @StateObject private var viewModel: WellnessAnalysisViewModel = {
        // Placeholder — will be replaced when navigating
        WellnessAnalysisViewModel(userProfile: UserProfile(
            userId: "", firstName: "", lastName: "", dateOfBirth: Date(), sex: "",
            heightFeet: 0, heightInches: 0, weight: 0, medicalConditions: [],
            surgeries: [], injuries: [], activityLevel: ""
        ), selectedGoals: [])
    }()

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.md),
        GridItem(.flexible(), spacing: AppSpacing.md)
    ]

    /// All selectable categories (excluding .custom which is handled by free text)
    private var selectableCategories: [GoalCategory] {
        GoalCategory.allCases.filter { $0 != .custom }
    }

    private var selectedGoals: [GoalSelection] {
        var goals = selectedCategories.map { GoalSelection(category: $0) }
        if !customGoalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            goals.append(GoalSelection(category: .custom, customDescription: customGoalText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return goals
    }

    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: AppSpacing.xl) {
                    headerSection
                    goalGrid
                    customGoalSection
                    continueButton
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .mvvcNavBar()
        .navigationDestination(isPresented: $showDetailView) {
            WellnessDetailView(viewModel: createViewModel())
        }
        .trackScreen("WellnessGoalPicker")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            MVVCDividerHeader(title: "What Do You Want to Improve?")
            Text("Select one or more goals below, or describe your own.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Goal Grid

    private var goalGrid: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.md) {
            ForEach(selectableCategories, id: \.self) { category in
                goalCard(for: category)
            }
        }
    }

    private func goalCard(for category: GoalCategory) -> some View {
        let isSelected = selectedCategories.contains(category)
        return Button(action: {
            withAnimation(AppAnimations.springy) {
                if isSelected {
                    selectedCategories.remove(category)
                } else {
                    selectedCategories.insert(category)
                }
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(category.color.opacity(isSelected ? 0.2 : 0.1))
                        .frame(width: 50, height: 50)
                    Image(systemName: category.icon)
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? category.color : .secondary)
                }

                Text(category.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundColor(isSelected ? AppColors.primaryText : AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .padding(.horizontal, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .fill(AppColors.cardBackground)
                    .shadow(color: AppColors.cardShadowColor, radius: isSelected ? 8 : 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(isSelected ? AppColors.accent : AppColors.cardBorder, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(category.color)
                        .font(.system(size: 20))
                        .offset(x: -8, y: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AppCorners.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.displayName), \(selectedCategories.contains(category) ? "selected" : "not selected")")
    }

    // MARK: - Custom Goal

    private var customGoalSection: some View {
        CardSection(icon: "text.bubble.fill", color: AppColors.secondaryText, title: "Or Describe Your Own Goal") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(AppColors.accent)
                    Text("AI-powered")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.accent)
                }
                .padding(.horizontal, AppSpacing.sm)
                .padding(.vertical, 4)
                .background(AppColors.accentTint)
                .cornerRadius(AppCorners.small)

                TextField("Describe what you'd like to improve...", text: $customGoalText, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
            }
        }
    }

    // MARK: - Continue Button

    private var continueButton: some View {
        Button(action: {
            showDetailView = true
        }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.right")
                Text("Continue with \(selectedGoals.count) \(selectedGoals.count == 1 ? "Goal" : "Goals")")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(selectedGoals.isEmpty)
        .opacity(selectedGoals.isEmpty ? 0.5 : 1)
        .padding(.bottom, AppSpacing.xxl)
        .accessibilityIdentifier("wellnessGoalPicker.continueButton")
    }

    // MARK: - ViewModel Creation

    private func createViewModel() -> WellnessAnalysisViewModel {
        WellnessAnalysisViewModel(
            userProfile: userProfile,
            selectedGoals: selectedGoals
        )
    }
}
