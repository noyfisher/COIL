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
            VStack(spacing: AppSpacing.lg) {
                // Basic info
                ReviewCard(title: "Personal Info", icon: "person.fill", color: .blue) {
                    ReviewRow(label: "Name", value: "\(viewModel.userProfile.firstName) \(viewModel.userProfile.lastName)")
                    ReviewRow(label: "Date of Birth", value: viewModel.userProfile.dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                    ReviewRow(label: "Sex", value: viewModel.userProfile.sex)
                    ReviewRow(label: "Height", value: "\(viewModel.userProfile.heightFeet)' \(viewModel.userProfile.heightInches)\"")
                    ReviewRow(label: "Weight", value: "\(Int(viewModel.userProfile.weight)) lbs")
                    if let side = viewModel.userProfile.dominantSide {
                        ReviewRow(label: "Dominant Side", value: side)
                    }
                }

                // Medical
                ReviewCard(title: "Medical History", icon: "heart.fill", color: .red) {
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

                // Surgeries
                ReviewCard(title: "Surgical History", icon: "bandage.fill", color: .orange) {
                    if viewModel.userProfile.surgeries.isEmpty {
                        ReviewRow(label: "", value: "No surgeries reported")
                    } else {
                        ForEach(viewModel.userProfile.surgeries) { surgery in
                            VStack(alignment: .leading, spacing: 2) {
                                ReviewRow(label: surgery.name, value: "\(surgery.year)")
                                if let area = surgery.bodyArea, !area.isEmpty {
                                    ReviewRow(label: "Area", value: area)
                                }
                                if let status = surgery.recoveryStatus {
                                    ReviewRow(label: "Status", value: status)
                                }
                                if let restrictions = surgery.restrictions, !restrictions.isEmpty {
                                    ReviewRow(label: "Restrictions", value: restrictions)
                                }
                                if let surgeryType = surgery.surgeryType, !surgeryType.isEmpty {
                                    ReviewRow(label: "Type", value: surgeryType)
                                }
                                if let causingInjury = surgery.causingInjury, !causingInjury.isEmpty {
                                    ReviewRow(label: "Caused By", value: causingInjury)
                                }
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

                // Injuries
                ReviewCard(title: "Injuries", icon: "cross.case.fill", color: .red) {
                    if viewModel.userProfile.injuries.isEmpty {
                        ReviewRow(label: "", value: "No injuries reported")
                    } else {
                        ForEach(viewModel.userProfile.injuries) { injury in
                            VStack(alignment: .leading, spacing: 2) {
                                ReviewRow(label: "\(injury.bodyArea) (\(injury.isCurrent ? "Current" : "Past"))", value: injury.description)
                                if let year = injury.year {
                                    ReviewRow(label: "Year", value: "\(year)")
                                }
                                if let status = injury.recoveryStatus {
                                    ReviewRow(label: "Recovery", value: status)
                                }
                            }
                        }
                    }
                }

                // Activity
                ReviewCard(title: "Activity Level", icon: "figure.run", color: .green) {
                    ReviewRow(label: "Level", value: viewModel.userProfile.activityLevel.isEmpty ? "Not set" : viewModel.userProfile.activityLevel)
                    if let sport = viewModel.userProfile.primarySport, !sport.isEmpty {
                        ReviewRow(label: "Sport", value: sport)
                    }
                }

                // Error message
                if showError {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                        Text("Failed to save profile. Please try again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(AppSpacing.md)
                    .background(Color.orange.opacity(0.1))
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
                            withAnimation(AppAnimations.bouncy) {
                                showCelebration = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                onComplete?()
                            }
                        } else {
                            showError = true
                        }
                    }
                }) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else if showSuccess {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.bold))
                            Text("Saved!")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Submit Profile")
                        }
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(showSuccess ? Color.green.opacity(0.8) : Color.green)
                    .cornerRadius(AppCorners.card)
                }
                .disabled(isSaving || showSuccess)
                .padding(.top, AppSpacing.sm)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }

        // Celebration overlay
        if showCelebration {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .transition(.opacity)

            CelebrationOverlay(
                icon: "checkmark.circle.fill",
                message: "Profile Saved!",
                iconColor: AppColors.success
            )
        }
        } // ZStack
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            Divider()
            content
        }
        .cardStyle()
    }
}

struct ReviewRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            if !label.isEmpty {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }
}
