import SwiftUI

struct MedicalHistoryStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var showMoreConditions = false
    @State private var customMedicationText = ""

    let conditions: [(String, String)] = [
        ("Diabetes", "drop.fill"),
        ("High Blood Pressure", "heart.fill"),
        ("Asthma", "lungs.fill"),
        ("Heart Disease", "waveform.path.ecg"),
        ("Arthritis", "figure.walk"),
        ("Osteoporosis", "bone"),
        ("None", "checkmark.shield.fill")
    ]

    let additionalConditions: [(String, String)] = [
        ("Blood Clotting Disorder", "drop.triangle.fill"),
        ("Fibromyalgia", "figure.cooldown"),
        ("Previous Cancer", "cross.circle"),
        ("Hypermobility", "arrow.left.and.right"),
        ("Neuropathy", "bolt.horizontal")
    ]

    let medications: [String] = [
        "Blood Thinners",
        "Beta Blockers",
        "Corticosteroids",
        "Insulin/Diabetes Meds",
        "Pain Medication",
        "Muscle Relaxants"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                    ForEach(conditions, id: \.0) { condition, icon in
                        conditionButton(condition: condition, icon: icon)
                    }
                }

                // Show More conditions
                Button(action: { withAnimation { showMoreConditions.toggle() } }) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(showMoreConditions ? "Show Less" : "Show More Conditions")
                            .font(.subheadline.weight(.medium))
                        Image(systemName: showMoreConditions ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(AppColors.accent)
                }

                if showMoreConditions {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.sm) {
                        ForEach(additionalConditions, id: \.0) { condition, icon in
                            conditionButton(condition: condition, icon: icon)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Medications section
                CardSection(icon: "pills.fill", color: AppColors.accent, title: "Current Medications") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Select any medications you take regularly")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(medications, id: \.self) { med in
                                let isSelected = viewModel.userProfile.medications?.contains(med) ?? false
                                Button(action: { toggleMedication(med) }) {
                                    Text(med)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, AppSpacing.md)
                                        .padding(.vertical, AppSpacing.sm)
                                        .background(isSelected ? AppColors.accent : AppColors.inputBackground)
                                        .cornerRadius(AppCorners.small)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: AppCorners.small)
                                                .stroke(isSelected ? Color.clear : AppColors.subtleBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }

                        // Custom medication input
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("Other Medications")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.secondaryText)
                                .padding(.top, AppSpacing.sm)

                            HStack(spacing: AppSpacing.sm) {
                                TextField("Type medication name", text: $customMedicationText)
                                    .font(.subheadline)
                                    .padding(AppSpacing.md)
                                    .background(AppColors.inputBackground)
                                    .cornerRadius(AppCorners.medium)

                                Button(action: { addCustomMedication() }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(AppColors.accent)
                                }
                                .disabled(customMedicationText.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            // Show custom medications as removable chips
                            if let meds = viewModel.userProfile.medications {
                                let customMeds = meds.filter { !medications.contains($0) }
                                if !customMeds.isEmpty {
                                    FlowLayout(spacing: AppSpacing.sm) {
                                        ForEach(customMeds, id: \.self) { med in
                                            HStack(spacing: 4) {
                                                Text(med)
                                                    .font(.subheadline.weight(.medium))
                                                Button(action: { toggleMedication(med) }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.caption)
                                                        .foregroundColor(.white.opacity(0.8))
                                                }
                                            }
                                            .foregroundColor(AppColors.ctaText)
                                            .padding(.horizontal, AppSpacing.md)
                                            .padding(.vertical, AppSpacing.sm)
                                            .background(AppColors.accent)
                                            .cornerRadius(AppCorners.small)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                CardSection(icon: "plus.circle.fill", color: AppColors.warning, title: "Other Conditions") {
                    TextField("e.g. Epilepsy, Thyroid issues...", text: $viewModel.userProfile.otherMedicalConditions.bound)
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
        .trackScreen("OnboardingMedicalHistory")
    }

    private func conditionButton(condition: String, icon: String) -> some View {
        let isSelected = viewModel.userProfile.medicalConditions.contains(condition)
        return Button(action: { toggleCondition(condition) }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(condition)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .padding(.horizontal, AppSpacing.sm)
            .background(isSelected ? AppColors.accent : AppColors.cardBackground)
            .cornerRadius(AppCorners.medium)
            .shadow(color: AppColors.cardShadowColor.opacity(isSelected ? 0 : 1), radius: 6, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 2)
            )
        }
    }

    private func toggleCondition(_ condition: String) {
        if condition == "None" {
            viewModel.userProfile.medicalConditions = ["None"]
            return
        }
        viewModel.userProfile.medicalConditions.removeAll { $0 == "None" }
        if viewModel.userProfile.medicalConditions.contains(condition) {
            viewModel.userProfile.medicalConditions.removeAll { $0 == condition }
        } else {
            viewModel.userProfile.medicalConditions.append(condition)
        }
    }

    private func addCustomMedication() {
        let trimmed = customMedicationText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if viewModel.userProfile.medications == nil {
            viewModel.userProfile.medications = []
        }
        // Don't add duplicates
        if viewModel.userProfile.medications?.contains(trimmed) != true {
            viewModel.userProfile.medications?.append(trimmed)
        }
        customMedicationText = ""
    }

    private func toggleMedication(_ med: String) {
        if viewModel.userProfile.medications == nil {
            viewModel.userProfile.medications = []
        }
        if viewModel.userProfile.medications?.contains(med) == true {
            viewModel.userProfile.medications?.removeAll { $0 == med }
            if viewModel.userProfile.medications?.isEmpty == true {
                viewModel.userProfile.medications = nil
            }
        } else {
            viewModel.userProfile.medications?.append(med)
        }
    }
}

extension Optional where Wrapped == String {
    var bound: String {
        get { self ?? "" }
        set { self = newValue.isEmpty ? nil : newValue }
    }
}
