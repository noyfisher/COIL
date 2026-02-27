import SwiftUI

struct BasicInfoStepView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var weightText: String = ""

    /// Whether to show validation errors — driven by ViewModel
    private var showErrors: Bool { viewModel.showValidationErrors }

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                CardSection(icon: "person.fill", color: .blue, title: "Full Name", required: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        StyledTextField(placeholder: "First Name", text: $viewModel.userProfile.firstName)
                        if showErrors && viewModel.userProfile.firstName.trimmingCharacters(in: .whitespaces).isEmpty {
                            validationMessage("First name is required")
                        }
                        StyledTextField(placeholder: "Last Name", text: $viewModel.userProfile.lastName)
                        if showErrors && viewModel.userProfile.lastName.trimmingCharacters(in: .whitespaces).isEmpty {
                            validationMessage("Last name is required")
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

                CardSection(icon: "figure.stand", color: .teal, title: "Sex", required: true) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(["Male", "Female", "Other"], id: \.self) { option in
                                Button(action: { viewModel.userProfile.sex = option }) {
                                    Text(option)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(viewModel.userProfile.sex == option ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, AppSpacing.md)
                                        .background(viewModel.userProfile.sex == option ? Color.teal : AppColors.subtleBorder)
                                        .cornerRadius(AppCorners.medium)
                                }
                            }
                        }
                        if showErrors && viewModel.userProfile.sex.isEmpty {
                            validationMessage("Please select an option")
                        }
                    }
                }

                CardSection(icon: "ruler", color: .green, title: "Height") {
                    HStack(spacing: AppSpacing.md) {
                        Menu {
                            ForEach(3..<8, id: \.self) { feet in
                                Button("\(feet) ft") { viewModel.userProfile.heightFeet = feet }
                            }
                        } label: {
                            HStack {
                                Text("\(viewModel.userProfile.heightFeet) ft")
                                    .font(.title3.weight(.medium))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.inputBackground)
                            .cornerRadius(AppCorners.medium)
                        }

                        Menu {
                            ForEach(0..<12, id: \.self) { inches in
                                Button("\(inches) in") { viewModel.userProfile.heightInches = inches }
                            }
                        } label: {
                            HStack {
                                Text("\(viewModel.userProfile.heightInches) in")
                                    .font(.title3.weight(.medium))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.md)
                            .background(AppColors.inputBackground)
                            .cornerRadius(AppCorners.medium)
                        }
                    }
                }

                CardSection(icon: "scalemass", color: .teal, title: "Weight (lbs)", required: true) {
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
                        if showErrors && (viewModel.userProfile.weight < 50 || viewModel.userProfile.weight > 500) {
                            validationMessage(viewModel.userProfile.weight == 0 ? "Weight is required" : "Please enter a weight between 50 and 500 lbs")
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
    }

    private func validationMessage(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(.red)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
