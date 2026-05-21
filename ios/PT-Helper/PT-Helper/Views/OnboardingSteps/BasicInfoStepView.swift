import SwiftUI

struct BasicInfoStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var weightText: String = ""
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false
    @FocusState private var isWeightFieldFocused: Bool

    private var showErrors: Bool { viewModel.showValidationErrors }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {

                // Name
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Full Name")
                    DarkTextField(placeholder: "First Name", text: $viewModel.userProfile.firstName)
                    if showErrors && viewModel.userProfile.firstName.trimmingCharacters(in: .whitespaces).isEmpty {
                        validationMessage("First name is required")
                    }
                    DarkTextField(placeholder: "Last Name", text: $viewModel.userProfile.lastName)
                    if showErrors && viewModel.userProfile.lastName.trimmingCharacters(in: .whitespaces).isEmpty {
                        validationMessage("Last name is required")
                    }
                }

                // Date of Birth
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Date of Birth")
                    DatePicker("", selection: $viewModel.userProfile.dateOfBirth, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(AppColors.accent)
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Sex
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Sex")
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(["Male", "Female", "Other"], id: \.self) { option in
                            DarkChipButton(label: option, isSelected: viewModel.userProfile.sex == option) {
                                viewModel.userProfile.sex = option
                            }
                        }
                    }
                    if showErrors && viewModel.userProfile.sex.isEmpty {
                        validationMessage("Please select an option")
                    }
                }

                // Dominant Side
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Dominant Side")
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(["Left", "Right", "Ambidextrous"], id: \.self) { option in
                            DarkChipButton(label: option, isSelected: viewModel.userProfile.dominantSide == option) {
                                viewModel.userProfile.dominantSide = option
                            }
                        }
                    }
                }

                // Height
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Height")
                    HStack(spacing: AppSpacing.md) {
                        Menu {
                            ForEach(3..<8, id: \.self) { feet in
                                Button("\(feet) ft") { viewModel.userProfile.heightFeet = feet }
                            }
                        } label: {
                            HStack {
                                Text("\(viewModel.userProfile.heightFeet) ft")
                                    .font(Font.custom("Inter-Medium", size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(OnboardingColors.muted)
                            }
                            .padding(AppSpacing.md)
                            .background(OnboardingColors.inputBg)
                            .cornerRadius(AppCorners.medium)
                            .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(OnboardingColors.cardBorder, lineWidth: 1))
                        }

                        Menu {
                            ForEach(0..<12, id: \.self) { inches in
                                Button("\(inches) in") { viewModel.userProfile.heightInches = inches }
                            }
                        } label: {
                            HStack {
                                Text("\(viewModel.userProfile.heightInches) in")
                                    .font(Font.custom("Inter-Medium", size: 15))
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(OnboardingColors.muted)
                            }
                            .padding(AppSpacing.md)
                            .background(OnboardingColors.inputBg)
                            .cornerRadius(AppCorners.medium)
                            .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(OnboardingColors.cardBorder, lineWidth: 1))
                        }
                    }
                }

                // Weight
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    OnboardingFieldLabel(text: "Weight")
                    HStack {
                        TextField("Enter weight", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($isWeightFieldFocused)
                            .font(Font.custom("Inter-Regular", size: 14))
                            .foregroundColor(.white)
                            .padding(AppSpacing.md)
                            .background(OnboardingColors.inputBg)
                            .cornerRadius(AppCorners.medium)
                            .overlay(RoundedRectangle(cornerRadius: AppCorners.medium).stroke(OnboardingColors.cardBorder, lineWidth: 1))
                            .onChange(of: weightText) { _, newValue in
                                if let val = Double(newValue) {
                                    viewModel.userProfile.weight = val
                                } else if newValue.isEmpty {
                                    viewModel.userProfile.weight = 0
                                }
                            }
                        Text("lbs")
                            .foregroundColor(OnboardingColors.muted)
                            .font(Font.custom("Inter-Medium", size: 14))
                    }
                    if showErrors && (viewModel.userProfile.weight < 50 || viewModel.userProfile.weight > 500) {
                        validationMessage(viewModel.userProfile.weight == 0 ? "Weight is required" : "Please enter a weight between 50 and 500 lbs")
                    }
                }

                // Terms
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(alignment: .top, spacing: AppSpacing.md) {
                        Button {
                            viewModel.hasAcceptedTerms.toggle()
                        } label: {
                            Image(systemName: viewModel.hasAcceptedTerms ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundColor(viewModel.hasAcceptedTerms ? AppColors.accent : OnboardingColors.muted)
                        }
                        .accessibilityIdentifier("onboarding.termsCheckbox")

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text("I agree to the ")
                                    .font(Font.custom("Inter-Regular", size: 14))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Button("Terms of Service") { showTermsSheet = true }
                                    .font(Font.custom("Inter-Medium", size: 14))
                                    .foregroundColor(AppColors.accent)
                            }
                            HStack(spacing: 0) {
                                Text("and ")
                                    .font(Font.custom("Inter-Regular", size: 14))
                                    .foregroundColor(Color.white.opacity(0.7))
                                Button("Privacy Policy") { showPrivacySheet = true }
                                    .font(Font.custom("Inter-Medium", size: 14))
                                    .foregroundColor(AppColors.accent)
                            }
                        }
                    }
                    if showErrors && !viewModel.hasAcceptedTerms {
                        validationMessage("You must accept the Terms of Service to continue")
                    }
                }
                .padding(AppSpacing.lg)
                .background(OnboardingColors.cardBg)
                .cornerRadius(AppCorners.card)
                .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(OnboardingColors.cardBorder, lineWidth: 1))
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .onAppear {
            if viewModel.userProfile.weight > 0 {
                weightText = String(Int(viewModel.userProfile.weight))
            }
        }
        .sheet(isPresented: $showTermsSheet) {
            LegalDocumentView(title: "Terms of Service", markdownContent: LegalContent.termsOfService)
        }
        .sheet(isPresented: $showPrivacySheet) {
            LegalDocumentView(title: "Privacy Policy", markdownContent: LegalContent.privacyPolicy)
        }
        .trackScreen("OnboardingBasicInfo")
    }

    private func validationMessage(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill").font(.caption2)
            Text(text).font(.caption)
        }
        .foregroundColor(AppColors.danger)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
