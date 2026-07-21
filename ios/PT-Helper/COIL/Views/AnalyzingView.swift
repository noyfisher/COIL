import SwiftUI

/// Destination of the analysis navigation push. `.analysis` is the normal result view;
/// `.emergency` is the blocking full-screen takeover shown for `.emergency` severity
/// findings (cardiac, stroke, cauda equina, DVT, meningitis).
enum AnalysisDestination: Hashable {
    case analysis
    case emergency(warnings: [String])

    static func == (lhs: AnalysisDestination, rhs: AnalysisDestination) -> Bool {
        switch (lhs, rhs) {
        case (.analysis, .analysis): return true
        case let (.emergency(l), .emergency(r)): return l == r
        default: return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .analysis:
            hasher.combine(0)
        case .emergency(let msgs):
            hasher.combine(1)
            hasher.combine(msgs)
        }
    }
}

struct AnalyzingView: View {
    @ObservedObject var viewModel: InjuryAnalysisViewModel
    @State private var destination: AnalysisDestination?
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var showCompletionFlash = false

    /// Order of stages, used to decide which step rows are completed vs active vs pending.
    private static let stageOrder: [InjuryAnalyzer.Stage] = [
        .primaryAnalysis, .verifyingResults, .validating
    ]

    /// Returns (isCompleted, isActive) for a given stage relative to the current one.
    private func status(for stage: InjuryAnalyzer.Stage) -> (isCompleted: Bool, isActive: Bool) {
        guard let current = viewModel.currentStage else {
            return (false, false)
        }
        guard let currentIndex = Self.stageOrder.firstIndex(of: current),
              let stageIndex = Self.stageOrder.firstIndex(of: stage) else {
            return (false, false)
        }
        if stageIndex < currentIndex { return (true, false) }
        if stageIndex == currentIndex { return (false, true) }
        return (false, false)
    }

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
        .interactiveDismissDisabled(viewModel.isAnalyzing)
        .gesture(viewModel.isAnalyzing ? DragGesture() : nil)
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
            // Start elapsed time counter
            elapsedSeconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                elapsedSeconds += 1
            }
            if !viewModel.isAnalyzing,
               viewModel.analysisResult == nil,
               viewModel.redFlagAlerts.map(\.severity).max() == .emergency {
                destination = routingDestination()
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
                    destination = routingDestination()
                }
            }
        }
        .onChange(of: destination) { _, newValue in
            // When user navigates back (destination becomes nil), pop back to PainDetailView.
            // Use Task + yield to let NavigationStack complete its transition before mutating
            // the second navigation binding — avoids the simultaneous-state-mutation crash.
            // Carried forward verbatim from the prior `navigateToResults` crash-guard.
            if newValue == nil {
                viewModel.analysisResult = nil
                Task { @MainActor in
                    await Task.yield()
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(50))
                    viewModel.showAnalyzingScreen = false
                }
            }
        }
        .navigationDestination(item: $destination) { dest in
            switch dest {
            case .analysis:
                AnalysisResultView(
                    analysisResult: viewModel.analysisResult ?? AnalysisResult(
                        id: UUID(), assessments: [], conditions: [],
                        overallSummary: "", disclaimerText: "",
                        generatedDate: Date(), userProfileSnapshot: viewModel.userProfile
                    ),
                    validationWarnings: viewModel.validationWarnings,
                    redFlagAlerts: viewModel.redFlagAlerts
                )
            case .emergency(let warnings):
                EmergencyRedirectView(warningMessages: warnings) {
                    // User tapped "Go Back" — clear destination to trigger the
                    // same back-nav cleanup as an analysis dismiss.
                    destination = nil
                }
            }
        }
        .trackScreen("Analyzing")
    }

    /// Decide which destination to push based on the worst validation severity.
    /// `.emergency` findings trigger the redirect regardless of feature flags;
    /// all others go to the normal result view where `.serious` findings get
    /// handled as a modal gate.
    private func routingDestination() -> AnalysisDestination {
        let worst = viewModel.redFlagAlerts.map(\.severity).max() ?? .info
        if worst == .emergency {
            let msgs = viewModel.redFlagAlerts
                .filter { $0.severity == .emergency }
                .map(\.message)
            return .emergency(warnings: msgs)
        }
        return .analysis
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
                        colors: [AppColors.accent, AppColors.accentLight],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Analyzing Your Symptoms")
                    .font(AppFonts.title)

                Text("Our AI is reviewing your pain assessments and health profile to identify potential conditions...")
                    .font(AppFonts.small)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            VStack(spacing: AppSpacing.xs) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(AppColors.accent)

                Text(elapsedTimeText)
                    .font(AppFonts.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // Backend-synced step indicators
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                // Step 0: always complete once this screen is shown — user did finish the form.
                AnalysisStepRow(
                    icon: "checkmark.circle.fill",
                    text: "Pain data collected",
                    isCompleted: true,
                    isActive: true
                )

                let primary = status(for: .primaryAnalysis)
                AnalysisStepRow(
                    icon: "gearshape.2.fill",
                    text: "Analyzing symptoms...",
                    isCompleted: primary.isCompleted,
                    isActive: primary.isActive
                )

                let verify = status(for: .verifyingResults)
                AnalysisStepRow(
                    icon: "checkmark.shield.fill",
                    text: "Verifying results...",
                    isCompleted: verify.isCompleted,
                    isActive: verify.isActive
                )

                let validate = status(for: .validating)
                AnalysisStepRow(
                    // This stage is the 6-step safety/validation pipeline, not
                    // recommendation generation — name it for the trust signal (audit #28).
                    icon: "checkmark.shield.fill",
                    text: "Running safety checks",
                    isCompleted: validate.isCompleted,
                    isActive: validate.isActive
                )
            }
            .padding(AppSpacing.xl)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, AppSpacing.xl)
            .animation(AppAnimations.smooth, value: viewModel.currentStage)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    private var elapsedTimeText: String {
        if elapsedSeconds < 5 {
            return ""
        } else if elapsedSeconds < 20 {
            return "\(elapsedSeconds)s — hang tight, this usually takes a few moments"
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
                    .font(AppFonts.title)

                Text(message)
                    .font(AppFonts.small)
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
                        .font(AppFonts.smallMedium)
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
                .font(isActive ? AppFonts.smallMedium : AppFonts.small)
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
