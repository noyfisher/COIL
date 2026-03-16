import SwiftUI

struct AnalyzingView: View {
    @ObservedObject var viewModel: InjuryAnalysisViewModel
    @State private var animateSteps = false
    @State private var navigateToResults = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var showCompletionFlash = false

    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()

            if let error = viewModel.analysisError {
                errorView(error)
            } else {
                loadingView
            }

            // Completion flash overlay
            if showCompletionFlash {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .transition(.opacity)

                CelebrationOverlay(
                    icon: "checkmark.circle.fill",
                    message: "Analysis Complete!",
                    iconColor: AppColors.success
                )
            }
        }
        .navigationTitle("Analyzing")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isAnalyzing {
                    Button("Cancel") {
                        viewModel.cancelAnalysis()
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.5)) {
                animateSteps = true
            }
            // Start elapsed time counter
            elapsedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                elapsedSeconds += 1
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: viewModel.isAnalyzing) { _, isAnalyzing in
            // When analysis finishes and we have a result, show flash then navigate
            if !isAnalyzing && viewModel.analysisResult != nil {
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
                withAnimation(AppAnimations.bouncy) {
                    showCompletionFlash = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showCompletionFlash = false
                    navigateToResults = true
                }
            }
        }
        .onChange(of: navigateToResults) { _, newValue in
            // When user navigates back from results, also pop back to PainDetailView.
            // Use Task + yield to let NavigationStack complete its transition before
            // mutating the second navigation binding. This avoids the simultaneous
            // navigation state mutation crash that a fixed-delay asyncAfter can cause.
            if !newValue {
                viewModel.analysisResult = nil
                Task { @MainActor in
                    // Yield twice to let the NavigationStack pop animation settle
                    await Task.yield()
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(50))
                    viewModel.showAnalyzingScreen = false
                }
            }
        }
        .navigationDestination(isPresented: $navigateToResults) {
            AnalysisResultView(
                analysisResult: viewModel.analysisResult ?? AnalysisResult(
                    id: UUID(), assessments: [], conditions: [],
                    overallSummary: "", disclaimerText: "",
                    generatedDate: Date(), userProfileSnapshot: viewModel.userProfile
                ),
                validationWarnings: viewModel.validationWarnings,
                redFlagAlerts: viewModel.redFlagAlerts
            )
        }
        .trackScreen("Analyzing")
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Animated brain icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 70))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Analyzing Your Symptoms")
                    .font(.title2.weight(.bold))

                Text("Our AI is reviewing your pain assessments and health profile to identify potential conditions...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            VStack(spacing: AppSpacing.xs) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(AppColors.accent)

                Text(elapsedTimeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // Animated step indicators
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                AnalysisStepRow(
                    icon: "checkmark.circle.fill",
                    text: "Pain data collected",
                    isCompleted: true,
                    isActive: true
                )
                AnalysisStepRow(
                    icon: "gearshape.2.fill",
                    text: "Analyzing symptoms...",
                    isCompleted: false,
                    isActive: animateSteps
                )
                AnalysisStepRow(
                    icon: "checkmark.shield.fill",
                    text: "Verifying results...",
                    isCompleted: false,
                    isActive: false
                )
                AnalysisStepRow(
                    icon: "list.bullet.clipboard.fill",
                    text: "Generating recommendations",
                    isCompleted: false,
                    isActive: false
                )
            }
            .padding(AppSpacing.xl)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, AppSpacing.xl)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    private var elapsedTimeText: String {
        if elapsedSeconds < 5 {
            return ""
        } else if elapsedSeconds < 20 {
            return "\(elapsedSeconds)s — this usually takes 10–20 seconds"
        } else {
            return "\(elapsedSeconds)s — almost there..."
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Analysis Failed")
                    .font(.title2.weight(.bold))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            VStack(spacing: AppSpacing.md) {
                Button(action: { viewModel.retryAnalysis() }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: {
                    viewModel.showAnalyzingScreen = false
                }) {
                    Text("Go Back to Assessment")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }
}

// MARK: - Step Row Component

private struct AnalysisStepRow: View {
    let icon: String
    let text: String
    let isCompleted: Bool
    let isActive: Bool

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundColor(isCompleted ? AppColors.success : (isActive ? AppColors.accent : Color.gray.opacity(0.4)))
                .frame(width: 24)

            Text(text)
                .font(.subheadline.weight(isActive ? .medium : .regular))
                .foregroundColor(isActive ? .primary : .secondary)

            Spacer()

            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.success)
            } else if isActive {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .opacity(isActive || isCompleted ? 1.0 : 0.4)
    }
}
