import SwiftUI

struct BasicInfoStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var weightText: String = ""
    @State private var hasInteracted = false

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                CardSection(icon: "person.fill", color: .blue, title: "Full Name") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        StyledTextField(placeholder: "First Name", text: $viewModel.userProfile.firstName)
                        if hasInteracted && viewModel.userProfile.firstName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("First name is required")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        StyledTextField(placeholder: "Last Name", text: $viewModel.userProfile.lastName)
                        if hasInteracted && viewModel.userProfile.lastName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Last name is required")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                CardSection(icon: "calendar", color: .orange, title: "Date of Birth") {
                    DatePicker("", selection: $viewModel.userProfile.dateOfBirth,
                               in: ...Date(),
                               displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                CardSection(icon: "figure.stand", color: .purple, title: "Sex") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(["Male", "Female", "Other"], id: \.self) { option in
                                Button(action: { viewModel.userProfile.sex = option }) {
                                    Text(option)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(viewModel.userProfile.sex == option ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AppSpacing.md)
                                        .background(viewModel.userProfile.sex == option ? Color.purple : AppColors.subtleBorder)
                                        .cornerRadius(AppCorners.medium)
                                }
                            }
                        }
                        if hasInteracted && viewModel.userProfile.sex.isEmpty {
                            Text("Please select an option")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                CardSection(icon: "ruler", color: .green, title: "Height") {
                    HStack(spacing: AppSpacing.md) {
                        Picker("Feet", selection: $viewModel.userProfile.heightFeet) {
                            ForEach(3..<8) { Text("\($0) ft").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .clipped()

                        Picker("Inches", selection: $viewModel.userProfile.heightInches) {
                            ForEach(0..<12) { Text("\($0) in").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 100)
                        .clipped()
                    }
                }

                CardSection(icon: "scalemass", color: .teal, title: "Weight") {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            TextField("Enter weight", text: $weightText)
                                .keyboardType(.decimalPad)
                                .font(.title3.weight(.medium))
                                .padding(AppSpacing.md)
                                .background(AppColors.inputBackground)
                                .cornerRadius(AppCorners.medium)
                                .onChange(of: weightText) { _, newValue in
                                    if let val = Double(newValue) {
                                        viewModel.userProfile.weight = val
                                    } else if newValue.isEmpty {
                                        viewModel.userProfile.weight = 0
                                    }
                                }
                            Text("lbs")
                                .foregroundColor(.secondary)
                                .font(.body.weight(.medium))
                        }
                        if hasInteracted && (viewModel.userProfile.weight < 50 || viewModel.userProfile.weight > 500) {
                            Text(viewModel.userProfile.weight == 0 ? "Weight is required" : "Please enter a weight between 50 and 500 lbs")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
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
        .onChange(of: viewModel.currentStep) { _, _ in
            // Show validation hints when user tries to move away from step 1
            if !hasInteracted {
                hasInteracted = true
            }
        }
    }
}

// CardSection and StyledTextField are defined in DesignSystem.swift
