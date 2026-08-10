import SwiftUI

/// Compact, ≤3-interaction daily check-in shown before today's prevention
/// routine. Symptoms = "Yes" branches to non-diagnostic safety guidance
/// instead of a time question — no routine is prescribed or progressed today.
struct PreventionCheckInSheet: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @ObservedObject var viewModel: PreventionViewModel
    let activePlan: RehabPlan?
    let healthProfile: UserProfile?
    @Environment(\.dismiss) private var dismiss

    @State private var context: DailyContext
    @State private var hasSymptoms: Bool = false
    @State private var length: PreventionRoutineLength

    init(viewModel: PreventionViewModel, activePlan: RehabPlan?, healthProfile: UserProfile?) {
        self.viewModel = viewModel
        self.activePlan = activePlan
        self.healthProfile = healthProfile
        // "Change" reopens this sheet after a check-in already exists today —
        // prefill from it so editing doesn't silently reset to profile defaults.
        if let existing = viewModel.todayCheckIn {
            _context = State(initialValue: existing.context)
            _hasSymptoms = State(initialValue: existing.hasNewOrWorseningSymptoms)
            _length = State(initialValue: existing.length)
        } else {
            let profile = viewModel.profile
            _context = State(initialValue: profile.typicalContext)
            _length = State(initialValue: profile.preferredLength)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    questionSection(title: "What does today look like?") {
                        ForEach(DailyContext.allCases) { option in
                            ChipButton(label: option.displayName, isSelected: context == option) {
                                context = option
                            }
                            .accessibilityIdentifier("prevention.checkIn.context.\(option.rawValue)")
                        }
                    }

                    questionSection(title: "Any new or worsening symptoms?") {
                        ChipButton(label: "No", isSelected: !hasSymptoms) { hasSymptoms = false }
                            .accessibilityIdentifier("prevention.checkIn.symptomsNoButton")
                        ChipButton(label: "Yes", isSelected: hasSymptoms) { hasSymptoms = true }
                            .accessibilityIdentifier("prevention.checkIn.symptomsYesButton")
                    }

                    if hasSymptoms {
                        SafetyGuidanceCard {
                            dismiss()
                            tabSelection.assessmentRequest = .pain
                        }
                    } else {
                        questionSection(title: "How much time do you have?") {
                            ForEach(PreventionRoutineLength.allCases) { option in
                                ChipButton(label: option.displayName, isSelected: length == option) {
                                    length = option
                                }
                                .accessibilityIdentifier("prevention.checkIn.length.\(option.rawValue)")
                            }
                        }
                    }

                    Button(hasSymptoms ? "Continue" : "See My Routine") {
                        viewModel.submitCheckIn(
                            context: context, hasSymptoms: hasSymptoms, length: length,
                            activePlan: activePlan, healthProfile: healthProfile
                        )
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("prevention.checkIn.submitButton")
                }
                .padding(AppSpacing.lg)
            }
            .background(AppColors.pageBackground.ignoresSafeArea())
            .navigationTitle("Daily Check-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .trackScreen("PreventionCheckIn")
    }

    @ViewBuilder
    private func questionSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(title)
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.primaryText)
            FlowLayout(spacing: AppSpacing.sm) {
                content()
            }
        }
    }
}

// MARK: - Safety Guidance

/// Non-diagnostic safety framing shown whenever symptoms are flagged — inline
/// during check-in, and again on Home for the rest of the day (safety hold).
/// Never claims diagnosis or treatment; only offers safe navigation to an
/// injury assessment.
struct SafetyGuidanceCard: View {
    var onStartAssessment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.warning)
                Text("Let's Prioritize Safety")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
            }

            Text("New or worsening symptoms are a signal to stop or modify activity. We won't suggest or progress exercises today — this isn't a diagnosis, just a safety pause.")
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)

            Text("If anything feels severe or sudden, or you're worried, contact a medical professional.")
                .font(AppFonts.caption)
                .foregroundColor(AppColors.mutedText)

            Button(action: onStartAssessment) {
                Text("Start an Assessment")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("prevention.safety.startAssessmentButton")
            .accessibilityHint("Opens a pain assessment to help understand your symptoms.")
        }
        .cardStyle()
    }
}
