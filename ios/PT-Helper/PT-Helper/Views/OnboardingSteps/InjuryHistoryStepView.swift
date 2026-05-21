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
                            .font(Font.custom("Inter-Medium", size: 15))
                            .foregroundColor(.white)
                        Text(viewModel.userProfile.injuries.isEmpty ? "Tap + to add" : "\(viewModel.userProfile.injuries.count) recorded")
                            .font(Font.custom("Inter-Regular", size: 12))
                            .foregroundColor(OnboardingColors.muted)
                    }
                    Spacer()
                    Image(systemName: viewModel.userProfile.injuries.isEmpty ? "cross.case" : "cross.case.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.accent)
                }
                .padding(AppSpacing.lg)
                .background(OnboardingColors.cardBg)
                .cornerRadius(AppCorners.card)
                .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(OnboardingColors.cardBorder, lineWidth: 1))

                // Injury entries
                ForEach(Array(viewModel.userProfile.injuries.enumerated()), id: \.element.id) { index, injury in
                    VStack(spacing: AppSpacing.sm) {
                        HStack {
                            Text("Injury \(index + 1)")
                                .font(Font.custom("BarlowCondensed-Black", size: 12))
                                .textCase(.uppercase)
                                .kerning(1.0)
                                .foregroundColor(AppColors.accent)
                            Spacer()
                            Button(action: { viewModel.userProfile.injuries.remove(at: index) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Color.white.opacity(0.35))
                            }
                        }

                        DarkTextField(placeholder: "Body area (e.g. Left Knee)", text: Binding(
                            get: { viewModel.userProfile.injuries[safe: index]?.bodyArea ?? "" },
                            set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].bodyArea = $0 } }
                        ))

                        DarkTextField(placeholder: "Description", text: Binding(
                            get: { viewModel.userProfile.injuries[safe: index]?.description ?? "" },
                            set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].description = $0 } }
                        ))

                        // Current / Past
                        HStack(spacing: AppSpacing.sm) {
                            let isCurrent = viewModel.userProfile.injuries[safe: index]?.isCurrent ?? false
                            ForEach(["Current", "Past"], id: \.self) { label in
                                let selected = (label == "Current") == isCurrent
                                DarkChipButton(label: label, isSelected: selected, action: {
                                    if index < viewModel.userProfile.injuries.count {
                                        viewModel.userProfile.injuries[index].isCurrent = (label == "Current")
                                    }
                                }, compact: true)
                            }
                        }

                        // Year picker
                        HStack {
                            Text("Year")
                                .font(Font.custom("Inter-Regular", size: 14))
                                .foregroundColor(OnboardingColors.muted)
                            Spacer()
                            Picker("Year", selection: Binding(
                                get: { viewModel.userProfile.injuries[safe: index]?.year ?? Calendar.current.component(.year, from: Date()) },
                                set: { if index < viewModel.userProfile.injuries.count { viewModel.userProfile.injuries[index].year = $0 } }
                            )) {
                                ForEach(yearRange, id: \.self) { year in Text(String(year)).tag(year) }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.accent)
                        }
                        .padding(AppSpacing.md)
                        .background(OnboardingColors.inputBg)
                        .cornerRadius(AppCorners.medium)
                        .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(OnboardingColors.cardBorder, lineWidth: 1))

                        // Saw doctor / Did PT
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

                        // Recovery status (past only)
                        if !(viewModel.userProfile.injuries[safe: index]?.isCurrent ?? true) {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text("Recovery")
                                    .font(Font.custom("Inter-Regular", size: 12))
                                    .foregroundColor(OnboardingColors.muted)
                                HStack(spacing: AppSpacing.sm) {
                                    ForEach(["Fully recovered", "Mostly recovered", "Still dealing with it"], id: \.self) { status in
                                        let isSelected = viewModel.userProfile.injuries[safe: index]?.recoveryStatus == status
                                        DarkChipButton(label: status, isSelected: isSelected, action: {
                                            if index < viewModel.userProfile.injuries.count {
                                                viewModel.userProfile.injuries[index].recoveryStatus = isSelected ? nil : status
                                            }
                                        }, compact: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(OnboardingColors.cardBg)
                    .cornerRadius(AppCorners.card)
                    .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(OnboardingColors.cardBorder, lineWidth: 1))
                }

                // Add button
                Button(action: {
                    viewModel.userProfile.injuries.append(UserProfile.Injury(bodyArea: "", description: "", isCurrent: true))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Injury")
                    }
                    .font(Font.custom("Inter-Medium", size: 15))
                    .foregroundColor(AppColors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColors.accent.opacity(0.08))
                    .cornerRadius(AppCorners.medium)
                    .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(AppColors.accent.opacity(0.25), lineWidth: 1))
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
                .font(Font.custom("Inter-Regular", size: 12))
                .foregroundColor(OnboardingColors.muted)
            HStack(spacing: AppSpacing.sm) {
                ForEach(["Yes", "No"], id: \.self) { option in
                    let isYes = option == "Yes"
                    let isSelected = value.wrappedValue == isYes
                    DarkChipButton(label: option, isSelected: isSelected, action: {
                        value.wrappedValue = isSelected ? nil : isYes
                    }, compact: true)
                }
            }
        }
    }
}
