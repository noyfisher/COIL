import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// Focused health update form shown after long inactivity.
/// Lets users quickly update medications, surgeries, and injuries
/// without going through the full onboarding flow.
struct QuickHealthUpdateView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showError = false
    @State private var previousMedications: [String]?
    @State private var customMedicationText = ""

    var onComplete: () -> Void

    private let predefinedMedications = [
        "Blood Thinners",
        "Beta Blockers",
        "Corticosteroids",
        "Insulin/Diabetes Meds",
        "Pain Medication",
        "Muscle Relaxants"
    ]

    private var yearRange: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((1950...currentYear).reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading your profile...")
                } else {
                    ScrollView {
                        VStack(spacing: AppSpacing.lg) {
                            // Header
                            VStack(spacing: AppSpacing.xs) {
                                Text("Quick Health Update")
                                    .font(.system(.title2, design: .serif).weight(.bold))
                                    .foregroundColor(AppColors.primaryText)
                                Text("Update any changes since your last visit")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .padding(.top, AppSpacing.md)

                            // Medications section
                            medicationsSection

                            // New surgeries section
                            surgeriesSection

                            // New injuries section
                            injuriesSection

                            // Error
                            if showError {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(AppColors.warning)
                                    Text("Failed to save. Please try again.")
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .padding(AppSpacing.md)
                                .background(AppColors.warning.opacity(0.1))
                                .cornerRadius(AppCorners.small)
                            }

                            // Save button
                            Button(action: saveAndContinue) {
                                HStack {
                                    if isSaving {
                                        ProgressView()
                                            .tint(AppColors.ctaText)
                                    } else {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Save & Continue")
                                    }
                                }
                                .font(.body.weight(.semibold))
                                .foregroundColor(AppColors.ctaText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.lg)
                                .background(AppColors.ctaBackground)
                                .cornerRadius(AppCorners.card)
                            }
                            .disabled(isSaving)
                            .padding(.top, AppSpacing.sm)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.vertical, AppSpacing.md)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Skip") {
                        UserProfileService.shared.recordActivity()
                        onComplete()
                    }
                }
            }
        }
        .onAppear {
            loadExistingProfile()
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .trackScreen("QuickHealthUpdate")
    }

    // MARK: - Sections

    private var medicationsSection: some View {
        CardSection(icon: "pills.fill", color: AppColors.accent, title: "Current Medications") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Update your current medications")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)

                FlowLayout(spacing: AppSpacing.sm) {
                    ForEach(predefinedMedications, id: \.self) { med in
                        let isSelected = viewModel.userProfile.medications?.contains(med) ?? false
                        Button(action: { toggleMedication(med) }) {
                            Text(med)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
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
                            .foregroundColor(AppColors.primaryText)
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
                        let customMeds = meds.filter { !predefinedMedications.contains($0) }
                        if !customMeds.isEmpty {
                            FlowLayout(spacing: AppSpacing.sm) {
                                ForEach(customMeds, id: \.self) { med in
                                    HStack(spacing: 4) {
                                        Text(med)
                                            .font(.subheadline.weight(.medium))
                                        Button(action: { toggleMedication(med) }) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundColor(AppColors.ctaText.opacity(0.8))
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
    }

    private var surgeriesSection: some View {
        CardSection(icon: "bandage.fill", color: AppColors.warning, title: "New Surgeries") {
            VStack(spacing: AppSpacing.sm) {
                Text("Add any surgeries since your last visit")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(viewModel.userProfile.surgeries.enumerated()), id: \.element.id) { index, surgery in
                    VStack(spacing: AppSpacing.sm) {
                        HStack {
                            Text("Surgery \(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.warning)
                            Spacer()
                            Button(action: {
                                viewModel.userProfile.surgeries.remove(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppColors.mutedText)
                            }
                        }

                        StyledTextField(placeholder: "Name of surgery", text: Binding(
                            get: { viewModel.userProfile.surgeries[safe: index]?.name ?? "" },
                            set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].name = $0 } }
                        ))

                        StyledTextField(placeholder: "Body area (e.g. Left Knee)", text: Binding(
                            get: { viewModel.userProfile.surgeries[safe: index]?.bodyArea ?? "" },
                            set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].bodyArea = $0.isEmpty ? nil : $0 } }
                        ))

                        // Year picker
                        HStack {
                            Text("Year")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Picker("Year", selection: Binding(
                                get: { viewModel.userProfile.surgeries[safe: index]?.year ?? Calendar.current.component(.year, from: Date()) },
                                set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].year = $0 } }
                            )) {
                                ForEach(yearRange, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.warning)
                        }
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.medium)

                        StyledTextField(placeholder: "What kind of surgery? (name or description)", text: Binding(
                            get: { viewModel.userProfile.surgeries[safe: index]?.surgeryType ?? "" },
                            set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].surgeryType = $0.isEmpty ? nil : $0 } }
                        ))

                        StyledTextField(placeholder: "What injury led to this surgery?", text: Binding(
                            get: { viewModel.userProfile.surgeries[safe: index]?.causingInjury ?? "" },
                            set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].causingInjury = $0.isEmpty ? nil : $0 } }
                        ))
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.medium)
                }

                Button(action: {
                    let currentYear = Calendar.current.component(.year, from: Date())
                    viewModel.userProfile.surgeries.append(UserProfile.Surgery(name: "", year: currentYear))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Surgery")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.warning)
                }
            }
        }
    }

    private var injuriesSection: some View {
        CardSection(icon: "cross.case.fill", color: AppColors.danger, title: "New Injuries") {
            VStack(spacing: AppSpacing.sm) {
                Text("Add any injuries since your last visit")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(Array(viewModel.userProfile.injuries.enumerated()), id: \.element.id) { index, injury in
                    VStack(spacing: AppSpacing.sm) {
                        HStack {
                            Text("Injury \(index + 1)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(AppColors.danger)
                            Spacer()
                            Button(action: {
                                viewModel.userProfile.injuries.remove(at: index)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(AppColors.mutedText)
                            }
                        }

                        StyledTextField(placeholder: "Body area (e.g. Right Shoulder)", text: Binding(
                            get: { viewModel.userProfile.injuries[safe: index]?.bodyArea ?? "" },
                            set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].bodyArea = $0 } }
                        ))

                        StyledTextField(placeholder: "Describe the injury", text: Binding(
                            get: { viewModel.userProfile.injuries[safe: index]?.description ?? "" },
                            set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].description = $0 } }
                        ))
                    }
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.medium)
                }

                Button(action: {
                    viewModel.userProfile.injuries.append(UserProfile.Injury(bodyArea: "", description: "", isCurrent: true))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Injury")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.danger)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadExistingProfile() {
        viewModel.loadProfile { success in
            if success {
                previousMedications = viewModel.userProfile.medications
            }
            isLoading = false
        }
    }

    private func saveAndContinue() {
        isSaving = true
        showError = false

        // Track medication changes before saving
        viewModel.updateMedicationHistory(previousMedications: previousMedications)

        viewModel.saveProfile { success in
            isSaving = false
            if success {
                // Reload the cached profile and record activity
                Task {
                    await UserProfileService.shared.reload()
                    UserProfileService.shared.recordActivity()
                }
                onComplete()
            } else {
                AnalyticsService.shared.log(.errorShown, parameters: [
                    "screen": "QuickHealthUpdateView",
                    "error_type": "save_failed"
                ])
                showError = true
            }
        }
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

    private func addCustomMedication() {
        let trimmed = customMedicationText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if viewModel.userProfile.medications == nil {
            viewModel.userProfile.medications = []
        }
        if viewModel.userProfile.medications?.contains(trimmed) != true {
            viewModel.userProfile.medications?.append(trimmed)
        }
        customMedicationText = ""
    }
}
