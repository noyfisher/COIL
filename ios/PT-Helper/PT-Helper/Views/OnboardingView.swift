import SwiftUI

struct OnboardingView: View {
    var onComplete: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppColors.bgGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with skip
                HStack {
                    Spacer()
                    if let onSkip = onSkip {
                        Button(action: {
                            AnalyticsService.shared.log(.onboardingSkipped, parameters: ["skipped_at_step": viewModel.currentStep])
                            OnboardingViewModel.clearDraft()
                            onSkip()
                        }) {
                            Text("Skip")
                                .font(AppFonts.bodyMedium)
                                .foregroundColor(Color.white.opacity(0.40))
                        }
                        .accessibilityIdentifier("onboarding.skipButton")
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)

                // Step indicator header
                VStack(spacing: AppSpacing.md) {
                    HStack(spacing: AppSpacing.xl) {
                        HStack(spacing: 5) {
                            ForEach(1...6, id: \.self) { step in
                                Capsule()
                                    .fill(step <= viewModel.currentStep ? AppColors.accent : Color.white.opacity(0.15))
                                    .frame(height: 3)
                                    .animation(.spring(response: 0.35), value: viewModel.currentStep)
                            }
                        }
                        Text("\(viewModel.currentStep)/6")
                            .font(AppFonts.microMedium)
                            .foregroundColor(Color.white.opacity(0.30))
                            .monospacedDigit()
                            .accessibilityIdentifier("onboarding.stepIndicator")
                    }
                    .padding(.horizontal, AppSpacing.xxl)

                    VStack(spacing: AppSpacing.xs) {
                        Text(stepTitle)
                            .font(Font.custom("Industry-Bold", size: 26))
                            .foregroundColor(.white)
                        Text(stepSubtitle)
                            .font(AppFonts.small)
                            .foregroundColor(Color.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, AppSpacing.xxl)
                    }
                }
                .padding(.bottom, AppSpacing.sm)

                // Step content
                TabView(selection: $viewModel.currentStep) {
                    BasicInfoStepView(viewModel: viewModel).tag(1)
                    MedicalHistoryStepView(viewModel: viewModel).tag(2)
                    SurgicalHistoryStepView(viewModel: viewModel).tag(3)
                    InjuryHistoryStepView(viewModel: viewModel).tag(4)
                    ActivityLevelStepView(viewModel: viewModel).tag(5)
                    ProfileReviewStepView(viewModel: viewModel, onComplete: onComplete).tag(6)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                // Navigation buttons
                HStack(spacing: AppSpacing.md) {
                    if viewModel.currentStep > 1 {
                        Button(action: { viewModel.previousStep() }) {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Back")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("onboarding.backButton")
                    }

                    if viewModel.currentStep < 6 {
                        Button(action: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            viewModel.nextStep()
                        }) {
                            HStack(spacing: AppSpacing.xs) {
                                Text("Continue")
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(isDisabled: !viewModel.canProceedFromCurrentStep))
                        .disabled(!viewModel.canProceedFromCurrentStep)
                        .accessibilityIdentifier("onboarding.continueButton")
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
        }
        .onAppear {
            AnalyticsService.shared.log(.onboardingStarted)
            if viewModel.loadDraft() {
                AppLogger.data.info("Resumed onboarding draft at step \(viewModel.currentStep)")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveDraft()
            }
        }
        .trackScreen("Onboarding")
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case 1: return "About You"
        case 2: return "Medical History"
        case 3: return "Past Surgeries"
        case 4: return "Injuries"
        case 5: return "Activity Level"
        case 6: return "Review & Submit"
        default: return ""
        }
    }

    private var stepSubtitle: String {
        switch viewModel.currentStep {
        case 1: return "Let's start with some basic information"
        case 2: return "Select any conditions that apply to you"
        case 3: return "Tell us about any past surgical procedures"
        case 4: return "Any current or previous injuries?"
        case 5: return "How active are you day to day?"
        case 6: return "Make sure everything looks correct"
        default: return ""
        }
    }
}
