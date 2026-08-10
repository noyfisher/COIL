import SwiftUI

/// Optional, approachable prevention setup — reachable via an unobtrusive
/// "Personalize" entry point. Skippable at any time; skipping leaves
/// `PreventionProfile.defaultProfile`'s safe defaults in place.
struct PreventionProfileSetupView: View {
    @ObservedObject var viewModel: PreventionViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var focus: PreventionFocus
    @State private var typicalContext: DailyContext
    @State private var equipment: RehabPlanPreferences.Equipment
    @State private var preferredLength: PreventionRoutineLength
    @State private var wantsReminder: Bool
    @State private var reminderHour: Int
    @State private var reminderMinute: Int

    init(viewModel: PreventionViewModel) {
        self.viewModel = viewModel
        let profile = viewModel.profile
        _focus = State(initialValue: profile.focus)
        _typicalContext = State(initialValue: profile.typicalContext)
        _equipment = State(initialValue: profile.equipment)
        _preferredLength = State(initialValue: profile.preferredLength)
        _wantsReminder = State(initialValue: profile.reminderHour != nil)
        _reminderHour = State(initialValue: profile.reminderHour ?? 9)
        _reminderMinute = State(initialValue: profile.reminderMinute ?? 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    CardSection(icon: "target", color: AppColors.accent, title: "Primary Focus") {
                        VStack(spacing: AppSpacing.sm) {
                            ForEach(PreventionFocus.allCases) { option in
                                focusRow(option)
                            }
                        }
                    }

                    CardSection(icon: "calendar", color: AppColors.info, title: "Typical Day") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(DailyContext.allCases) { option in
                                ChipButton(label: option.displayName, isSelected: typicalContext == option) {
                                    typicalContext = option
                                }
                                .accessibilityIdentifier("prevention.setup.context.\(option.rawValue)")
                            }
                        }
                    }

                    CardSection(icon: "dumbbell.fill", color: AppColors.warning, title: "Available Equipment") {
                        FlowLayout(spacing: AppSpacing.sm) {
                            ForEach(RehabPlanPreferences.Equipment.allCases, id: \.self) { option in
                                ChipButton(label: option.rawValue, isSelected: equipment == option) {
                                    equipment = option
                                }
                            }
                        }
                    }

                    CardSection(icon: "clock.fill", color: AppColors.success, title: "Preferred Routine Length") {
                        HStack(spacing: AppSpacing.sm) {
                            ForEach(PreventionRoutineLength.allCases) { option in
                                ChipButton(label: option.displayName, isSelected: preferredLength == option) {
                                    preferredLength = option
                                }
                                .accessibilityIdentifier("prevention.setup.length.\(option.rawValue)")
                            }
                        }
                    }

                    CardSection(icon: "bell.fill", color: AppColors.accent, title: "Reminder (Optional)") {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Toggle("Remind me daily", isOn: $wantsReminder)
                                .tint(AppColors.accent)
                            if wantsReminder {
                                DatePicker("Time", selection: reminderTimeBinding, displayedComponents: .hourAndMinute)
                                Text("Saved for now — daily reminder notifications aren't sent yet in this version.")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.mutedText)
                            }
                        }
                    }

                    VStack(spacing: AppSpacing.sm) {
                        Button("Save") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("prevention.setup.saveButton")

                        Button("Skip for now") { dismiss() }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("prevention.setup.skipButton")
                    }
                }
                .padding(AppSpacing.lg)
                .floatingTabBarClearance()
            }
            .background(AppColors.pageBackground.ignoresSafeArea())
            .navigationTitle("Personalize Prevention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .trackScreen("PreventionProfileSetup")
    }

    private var reminderTimeBinding: Binding<Date> {
        Binding<Date>(
            get: {
                Calendar.current.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = comps.hour ?? 9
                reminderMinute = comps.minute ?? 0
            }
        )
    }

    @ViewBuilder
    private func focusRow(_ option: PreventionFocus) -> some View {
        let isSelected = focus == option
        Button {
            focus = option
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: option.icon)
                    .foregroundColor(isSelected ? .white : AppColors.accent)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? AppColors.accent : AppColors.accent.opacity(0.12))
                    .cornerRadius(AppCorners.small)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.displayName)
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                    Text(option.subtitle)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(AppSpacing.sm)
            .background(isSelected ? AppColors.accentTint : Color.clear)
            .cornerRadius(AppCorners.medium)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prevention.setup.focus.\(option.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func save() {
        var profile = viewModel.profile
        profile.focus = focus
        profile.typicalContext = typicalContext
        profile.equipment = equipment
        profile.preferredLength = preferredLength
        profile.reminderHour = wantsReminder ? reminderHour : nil
        profile.reminderMinute = wantsReminder ? reminderMinute : nil
        viewModel.saveProfile(profile)
        dismiss()
    }
}
