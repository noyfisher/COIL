import SwiftUI

struct ProfileReviewStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    var onComplete: (() -> Void)? = nil
    @State private var isSaving = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var showCelebration = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {

                    ReviewCard(title: "Personal Info", icon: "person.fill", color: AppColors.accent) {
                        ReviewRow(label: "Name", value: "\(viewModel.userProfile.firstName) \(viewModel.userProfile.lastName)")
                        ReviewRow(label: "Date of Birth", value: viewModel.userProfile.dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                        ReviewRow(label: "Sex", value: viewModel.userProfile.sex)
                        ReviewRow(label: "Height", value: "\(viewModel.userProfile.heightFeet)' \(viewModel.userProfile.heightInches)\"")
                        ReviewRow(label: "Weight", value: "\(Int(viewModel.userProfile.weight)) lbs")
                        if let side = viewModel.userProfile.dominantSide {
                            ReviewRow(label: "Dominant Side", value: side)
                        }
                    }

                    ReviewCard(title: "Medical History", icon: "heart.fill", color: AppColors.danger) {
                        if viewModel.userProfile.medicalConditions.isEmpty {
                            ReviewRow(label: "Conditions", value: "None reported")
                        } else {
                            ReviewRow(label: "Conditions", value: viewModel.userProfile.medicalConditions.joined(separator: ", "))
                        }
                        if let other = viewModel.userProfile.otherMedicalConditions, !other.isEmpty {
                            ReviewRow(label: "Other", value: other)
                        }
                        if let meds = viewModel.userProfile.medications, !meds.isEmpty {
                            ReviewRow(label: "Medications", value: meds.joined(separator: ", "))
                        }
                    }

                    ReviewCard(title: "Surgical History", icon: "bandage.fill", color: AppColors.warning) {
                        if viewModel.userProfile.surgeries.isEmpty {
                            ReviewRow(label: "", value: "No surgeries reported")
                        } else {
                            ForEach(viewModel.userProfile.surgeries) { surgery in
                                VStack(alignment: .leading, spacing: 2) {
                                    ReviewRow(label: surgery.name, value: "\(surgery.year)")
                                    if let area = surgery.bodyArea, !area.isEmpty { ReviewRow(label: "Area", value: area) }
                                    if let status = surgery.recoveryStatus { ReviewRow(label: "Status", value: status) }
                                    if let restrictions = surgery.restrictions, !restrictions.isEmpty { ReviewRow(label: "Restrictions", value: restrictions) }
                                    if let surgeryType = surgery.surgeryType, !surgeryType.isEmpty { ReviewRow(label: "Type", value: surgeryType) }
                                    if let causingInjury = surgery.causingInjury, !causingInjury.isEmpty { ReviewRow(label: "Caused By", value: causingInjury) }
                                    if let hasHardware = surgery.hasHardware {
                                        ReviewRow(label: "Hardware", value: hasHardware ? "Yes" : "No")
                                        if hasHardware, let details = surgery.hardwareDetails, !details.isEmpty {
                                            ReviewRow(label: "Hardware Details", value: details)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    ReviewCard(title: "Injuries", icon: "cross.case.fill", color: AppColors.danger) {
                        if viewModel.userProfile.injuries.isEmpty {
                            ReviewRow(label: "", value: "No injuries reported")
                        } else {
                            ForEach(viewModel.userProfile.injuries) { injury in
                                VStack(alignment: .leading, spacing: 2) {
                                    ReviewRow(label: "\(injury.bodyArea) (\(injury.isCurrent ? "Current" : "Past"))", value: injury.description)
                                    if let year = injury.year { ReviewRow(label: "Year", value: "\(year)") }
                                    if let status = injury.recoveryStatus { ReviewRow(label: "Recovery", value: status) }
                                }
                            }
                        }
                    }

                    ReviewCard(title: "Activity Level", icon: "figure.run", color: AppColors.success) {
                        ReviewRow(label: "Level", value: viewModel.userProfile.activityLevel.isEmpty ? "Not set" : viewModel.userProfile.activityLevel)
                        if let sport = viewModel.userProfile.primarySport, !sport.isEmpty {
                            ReviewRow(label: "Sport", value: sport)
                        }
                    }

                    if showError {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(AppColors.warning)
                            Text("Failed to save profile. Please try again.")
                                .font(AppFonts.small)
                                .foregroundColor(Color.white.opacity(0.7))
                        }
                        .padding(AppSpacing.md)
                        .background(AppColors.warning.opacity(0.12))
                        .cornerRadius(AppCorners.small)
                    }

                    // Submit button
                    Button(action: {
                        isSaving = true
                        showError = false
                        viewModel.saveProfile { success in
                            isSaving = false
                            if success {
                                showSuccess = true
                                let notification = UINotificationFeedbackGenerator()
                                notification.notificationOccurred(.success)
                                withAnimation(AppAnimations.bouncy) { showCelebration = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { onComplete?() }
                            } else {
                                showError = true
                            }
                        }
                    }) {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else if showSuccess {
                                Image(systemName: "checkmark").font(.body.weight(.bold))
                                Text("Saved!")
                            } else {
                                Text("Submit Profile")
                            }
                        }
                        .font(Font.custom("Industry-Bold", size: 16))
                        .textCase(.uppercase)
                        .kerning(1.0)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                        .background(showSuccess ? AppColors.success : AppColors.accent)
                        .cornerRadius(AppCorners.pill)
                    }
                    .disabled(isSaving || showSuccess)
                    .accessibilityIdentifier("onboarding.submitButton")
                    .padding(.top, AppSpacing.sm)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }

            if showCelebration {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                CelebrationOverlay(
                    icon: "checkmark.circle.fill",
                    message: "Profile Saved!",
                    iconColor: AppColors.success
                )
            }
        }
        .trackScreen("OnboardingProfileReview")
    }
}

struct ReviewCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.15))
                    .cornerRadius(7)
                Text(title)
                    .font(Font.custom("Industry-Bold", size: 13))
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .foregroundColor(Color.white.opacity(0.5))
            }
            Color.white.opacity(0.08).frame(height: 1)
            content
        }
        .padding(AppSpacing.lg)
        .background(OnboardingColors.cardBg)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(OnboardingColors.cardBorder, lineWidth: 1))
    }
}

struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            if !label.isEmpty {
                Text(label)
                    .font(AppFonts.small)
                    .foregroundColor(Color.white.opacity(0.45))
            }
            Spacer()
            Text(value)
                .font(AppFonts.smallMedium)
                .foregroundColor(.white)
                .multilineTextAlignment(.trailing)
        }
    }
}
