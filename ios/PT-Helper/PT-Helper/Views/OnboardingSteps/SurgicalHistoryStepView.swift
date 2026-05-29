import SwiftUI

struct SurgicalHistoryStepView: View {
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
                        Text("Have you had any surgeries?")
                            .font(Font.custom("Inter-Medium", size: 15))
                            .foregroundColor(.white)
                        Text(viewModel.userProfile.surgeries.isEmpty ? "Tap + to add" : "\(viewModel.userProfile.surgeries.count) recorded")
                            .font(AppFonts.caption)
                            .foregroundColor(OnboardingColors.muted)
                    }
                    Spacer()
                    Image(systemName: viewModel.userProfile.surgeries.isEmpty ? "bandage" : "bandage.fill")
                        .font(.title2)
                        .foregroundColor(AppColors.warning)
                }
                .padding(AppSpacing.lg)
                .background(OnboardingColors.cardBg)
                .cornerRadius(AppCorners.card)
                .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(OnboardingColors.cardBorder, lineWidth: 1))

                ForEach(Array(viewModel.userProfile.surgeries.enumerated()), id: \.element.id) { index, _ in
                    surgeryCard(index: index)
                }

                // Add button
                Button(action: {
                    let currentYear = Calendar.current.component(.year, from: Date())
                    viewModel.userProfile.surgeries.append(UserProfile.Surgery(name: "", year: currentYear))
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Surgery")
                    }
                    .font(Font.custom("Inter-Medium", size: 15))
                    .foregroundColor(AppColors.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.lg)
                    .background(AppColors.warning.opacity(0.08))
                    .cornerRadius(AppCorners.medium)
                    .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(AppColors.warning.opacity(0.25), lineWidth: 1))
                }
                .accessibilityIdentifier("onboarding.addSurgeryButton")
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .trackScreen("OnboardingSurgicalHistory")
    }

    @ViewBuilder
    private func surgeryCard(index: Int) -> some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Text("Surgery \(index + 1)")
                    .font(Font.custom("BarlowCondensed-Black", size: 12))
                    .textCase(.uppercase)
                    .kerning(1.0)
                    .foregroundColor(AppColors.warning)
                Spacer()
                Button(action: { viewModel.userProfile.surgeries.remove(at: index) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.white.opacity(0.35))
                }
            }

            DarkTextField(placeholder: "Name of surgery", text: Binding(
                get: { viewModel.userProfile.surgeries[safe: index]?.name ?? "" },
                set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].name = $0 } }
            ))

            DarkTextField(placeholder: "Body area (e.g. Left Knee)", text: Binding(
                get: { viewModel.userProfile.surgeries[safe: index]?.bodyArea ?? "" },
                set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].bodyArea = $0.isEmpty ? nil : $0 } }
            ))

            yearPickerRow(index: index)
            recoveryStatusRow(index: index)
            detailFieldsRow(index: index)
            hardwareRow(index: index)
        }
        .padding(AppSpacing.lg)
        .background(OnboardingColors.cardBg)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(OnboardingColors.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func yearPickerRow(index: Int) -> some View {
        HStack {
            Text("Year")
                .font(AppFonts.body)
                .foregroundColor(OnboardingColors.muted)
            Spacer()
            Picker("Year", selection: Binding(
                get: { viewModel.userProfile.surgeries[safe: index]?.year ?? Calendar.current.component(.year, from: Date()) },
                set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].year = $0 } }
            )) {
                ForEach(yearRange, id: \.self) { year in Text(String(year)).tag(year) }
            }
            .pickerStyle(.menu)
            .tint(AppColors.warning)
        }
        .padding(AppSpacing.md)
        .background(OnboardingColors.inputBg)
        .cornerRadius(AppCorners.medium)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(OnboardingColors.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func recoveryStatusRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Recovery Status")
                .font(AppFonts.caption)
                .foregroundColor(OnboardingColors.muted)
            HStack(spacing: AppSpacing.sm) {
                ForEach(["Fully recovered", "Still recovering", "Have restrictions"], id: \.self) { status in
                    let isSelected = viewModel.userProfile.surgeries[safe: index]?.recoveryStatus == status
                    DarkChipButton(label: status, isSelected: isSelected, action: {
                        if index < viewModel.userProfile.surgeries.count {
                            viewModel.userProfile.surgeries[index].recoveryStatus = isSelected ? nil : status
                            if status != "Have restrictions" {
                                viewModel.userProfile.surgeries[index].restrictions = nil
                            }
                        }
                    }, compact: true)
                }
            }
        }

        if viewModel.userProfile.surgeries[safe: index]?.recoveryStatus == "Have restrictions" {
            DarkTextField(placeholder: "Describe restrictions", text: Binding(
                get: { viewModel.userProfile.surgeries[safe: index]?.restrictions ?? "" },
                set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].restrictions = $0.isEmpty ? nil : $0 } }
            ))
        }
    }

    @ViewBuilder
    private func detailFieldsRow(index: Int) -> some View {
        Color.white.opacity(0.08).frame(height: 1).padding(.vertical, AppSpacing.xs)

        DarkTextField(placeholder: "What kind of surgery was it?", text: Binding(
            get: { viewModel.userProfile.surgeries[safe: index]?.surgeryType ?? "" },
            set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].surgeryType = $0.isEmpty ? nil : $0 } }
        ))

        DarkTextField(placeholder: "What injury led to this surgery?", text: Binding(
            get: { viewModel.userProfile.surgeries[safe: index]?.causingInjury ?? "" },
            set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].causingInjury = $0.isEmpty ? nil : $0 } }
        ))
    }

    @ViewBuilder
    private func hardwareRow(index: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Did surgery leave pins, screws, or plates?")
                .font(AppFonts.caption)
                .foregroundColor(OnboardingColors.muted)
            HStack(spacing: AppSpacing.sm) {
                ForEach(["Yes", "No", "Not Sure"], id: \.self) { option in
                    let currentValue: String? = {
                        guard let has = viewModel.userProfile.surgeries[safe: index]?.hasHardware else { return nil }
                        return has ? "Yes" : "No"
                    }()
                    let isSelected: Bool = {
                        if option == "Not Sure" {
                            return viewModel.userProfile.surgeries[safe: index]?.hasHardware == nil
                                && viewModel.userProfile.surgeries[safe: index]?.hardwareDetails == "__not_sure__"
                        }
                        return currentValue == option
                    }()
                    DarkChipButton(label: option, isSelected: isSelected, action: {
                        if index < viewModel.userProfile.surgeries.count {
                            switch option {
                            case "Yes":
                                viewModel.userProfile.surgeries[index].hasHardware = true
                                viewModel.userProfile.surgeries[index].hardwareDetails = nil
                            case "No":
                                viewModel.userProfile.surgeries[index].hasHardware = false
                                viewModel.userProfile.surgeries[index].hardwareDetails = nil
                            default:
                                viewModel.userProfile.surgeries[index].hasHardware = nil
                                viewModel.userProfile.surgeries[index].hardwareDetails = "__not_sure__"
                            }
                        }
                    }, compact: true)
                }
            }
        }

        if viewModel.userProfile.surgeries[safe: index]?.hasHardware == true {
            DarkTextField(placeholder: "Describe the hardware (e.g. two titanium screws)", text: Binding(
                get: { viewModel.userProfile.surgeries[safe: index]?.hardwareDetails ?? "" },
                set: { if index < viewModel.userProfile.surgeries.count { viewModel.userProfile.surgeries[index].hardwareDetails = $0.isEmpty ? nil : $0 } }
            ))
        }
    }
}

// MARK: - Safe array subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
