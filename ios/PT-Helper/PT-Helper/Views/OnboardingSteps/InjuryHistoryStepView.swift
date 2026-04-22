import SwiftUI

struct InjuryHistoryStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    private var yearRange: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array((1950...currentYear).reversed())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header card
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Any current or past injuries?")
                            .font(.body.weight(.medium))
                            .foregroundColor(AppColors.primaryText)
                        Text(viewModel.userProfile.injuries.isEmpty ? "Tap to add" : "\(viewModel.userProfile.injuries.count) recorded")
                            .font(.caption)
                            .foregroundColor(AppColors.secondaryText)
                    }
                    Spacer()
                    Image(systemName: viewModel.userProfile.injuries.isEmpty ? "cross.case" : "cross.case.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.danger)
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                // Injury entries
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

                        StyledTextField(placeholder: "Body area (e.g. Left Knee)", text: Binding(
                            get: { viewModel.userProfile.injuries[safe: index]?.bodyArea ?? "" },
                            set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].bodyArea = $0 } }
                        ))

                        StyledTextField(placeholder: "Description", text: Binding(
                            get: { viewModel.userProfile.injuries[safe: index]?.description ?? "" },
                            set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].description = $0 } }
                        ))

                        // Current / Past toggle
                        HStack(spacing: AppSpacing.sm) {
                            let isCurrent = viewModel.userProfile.injuries[safe: index]?.isCurrent ?? false
                            ForEach(["Current", "Past"], id: \.self) { label in
                                let selected = (label == "Current") == isCurrent
                                Button(action: {
                                    if index < viewModel.userProfile.injuries.count {
                                        viewModel.userProfile.injuries[index].isCurrent = (label == "Current")
                                    }
                                }) {
                                    Text(label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(selected ? AppColors.ctaText : AppColors.primaryText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AppSpacing.sm)
                                        .background(selected ? AppColors.danger.opacity(0.8) : AppColors.subtleBorder)
                                        .cornerRadius(AppCorners.small)
                                }
                            }
                        }

                        // Year picker
                        HStack {
                            Text("Year")
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                            Spacer()
                            Picker("Year", selection: Binding(
                                get: { viewModel.userProfile.injuries[safe: index]?.year ?? Calendar.current.component(.year, from: Date()) },
                                set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].year = $0 } }
                            )) {
                                ForEach(yearRange, id: \.self) { year in
                                    Text(String(year)).tag(year)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.danger)
                        }
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.medium)

                        // Saw doctor / Did PT toggles
                        HStack(spacing: AppSpacing.md) {
                            yesNoToggle(
                                label: "Saw a doctor?",
                                value: Binding(
                                    get: { viewModel.userProfile.injuries[safe: index]?.sawDoctor },
                                    set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].sawDoctor = $0 } }
                                )
                            )
                            yesNoToggle(
                                label: "Did PT?",
                                value: Binding(
                                    get: { viewModel.userProfile.injuries[safe: index]?.hadPhysicalTherapy },
                                    set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].hadPhysicalTherapy = $0 } }
                                )
                            )
                        }

                        // Recovery status (only for past injuries)
                        if !(viewModel.userProfile.injuries[safe: index]?.isCurrent ?? true) {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Recovery")
                                    .font(.subheadline)
                                    .foregroundColor(AppColors.secondaryText)
                                HStack(spacing: AppSpacing.sm) {
                                    ForEach(["Fully recovered", "Mostly recovered", "Still dealing with it"], id: \.self) { status in
                                        let isSelected = viewModel.userProfile.injuries[safe: index]?.recoveryStatus == status
                                        Button(action: {
                                            if index < viewModel.userProfile.injuries.count {
                                                viewModel.userProfile.injuries[index].recoveryStatus = isSelected ? nil : status
                                            }
                                        }) {
                                            Text(status)
                                                .font(.caption.weight(.medium))
                                                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
                                                .padding(.horizontal, AppSpacing.sm)
                                                .padding(.vertical, AppSpacing.xs)
                                                .frame(maxWidth: .infinity)
                                                .background(isSelected ? AppColors.danger.opacity(0.7) : AppColors.inputBackground)
                                                .cornerRadius(AppCorners.small)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
                }

                // Add button
                Button(action: {
                    viewModel.userProfile.injuries.append(UserProfile.Injury(bodyArea: "", description: "", isCurrent: true))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Injury")
                    }
                    .font(.body.weight(.medium))
                    .foregroundColor(AppColors.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColors.danger.opacity(0.1))
                    .cornerRadius(AppCorners.medium)
                }
                .accessibilityIdentifier("onboarding.addInjuryButton")
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .trackScreen("OnboardingInjuryHistory")
    }

    private func yesNoToggle(label: String, value: Binding<Bool?>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
            HStack(spacing: AppSpacing.sm) {
                ForEach(["Yes", "No"], id: \.self) { option in
                    let isYes = option == "Yes"
                    let isSelected = value.wrappedValue == isYes
                    Button(action: {
                        value.wrappedValue = isSelected ? nil : isYes
                    }) {
                        Text(option)
                            .font(.caption.weight(.medium))
                            .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.xs)
                            .background(isSelected ? AppColors.danger.opacity(0.7) : AppColors.inputBackground)
                            .cornerRadius(AppCorners.small)
                    }
                }
            }
        }
    }
}
