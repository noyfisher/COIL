import SwiftUI

struct WellnessAnalyzingView: View {
    @ObservedObject var viewModel: WellnessAnalysisViewModel
    @State private var animateSteps = false
    @State private var elapsedSeconds: Int = 0
    @State private var timer: Timer?
    @State private var showCompletionFlash = false

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            if let error = viewModel.analysisError {
                errorView(error)
            } else {
                loadingView
            }

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
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(viewModel.isAnalyzing)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isAnalyzing {
                    Button("Cancel") {
                        viewModel.cancelAnalysis()
                    }
                    .foregroundColor(AppColors.danger)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.5)) {
                animateSteps = true
            }
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: viewModel.analysisResult?.id) { _, newValue in
            if newValue != nil {
                timer?.invalidate()
                withAnimation(AppAnimations.springy) {
                    showCompletionFlash = true
                }
            }
        }
        .trackScreen("WellnessAnalyzing")
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 70))
                .foregroundColor(AppColors.accent)
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Analyzing Your Goals")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                Text("Our AI is building your personalized wellness plan...")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: AppSpacing.xs) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(AppColors.accent)
                Text(elapsedTimeText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(AppColors.secondaryText)
            }

            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                stepRow(icon: "checkmark.circle.fill", text: "Goal data collected", isCompleted: true, isActive: true)
                stepRow(icon: "brain.head.profile", text: "Understanding your goals...", isCompleted: false, isActive: animateSteps)
                stepRow(icon: "figure.flexibility", text: "Analyzing your lifestyle...", isCompleted: false, isActive: animateSteps && elapsedSeconds > 3)
                stepRow(icon: "sparkles", text: "Building your wellness plan...", isCompleted: false, isActive: animateSteps && elapsedSeconds > 8)
            }
            .padding(AppSpacing.xl)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        // Distinguish a dropped connection from a server error so users retry the
        // right thing instead of seeing an opaque technical string (audit #43).
        let isOffline = !NetworkMonitor.shared.isConnected
        return VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: isOffline ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text(isOffline ? "You're Offline" : "Analysis Failed")
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                Text(isOffline
                     ? "You appear to be offline. Reconnect and try again."
                     : message)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: AppSpacing.md) {
                Button(action: { viewModel.retryAnalysis() }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: { viewModel.showAnalyzingScreen = false }) {
                    Text("Go Back to Assessment")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, AppSpacing.xxl)

            Spacer()
        }
        .padding(.horizontal, AppSpacing.xxl)
    }

    // MARK: - Timer

    private func startTimer() {
        elapsedSeconds = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedSeconds += 1
        }
    }

    private var elapsedTimeText: String {
        if elapsedSeconds < 5 { return "" }
        else if elapsedSeconds < 20 { return "\(elapsedSeconds)s — this usually takes 10–20 seconds" }
        else { return "\(elapsedSeconds)s — almost there..." }
    }

    private func stepRow(icon: String, text: String, isCompleted: Bool, isActive: Bool) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundColor(isCompleted ? AppColors.success : (isActive ? AppColors.accent : Color.gray.opacity(0.4)))
                .frame(width: 24)
            Text(text)
                .font(.subheadline.weight(isActive ? .medium : .regular))
                .foregroundColor(isActive ? AppColors.primaryText : AppColors.mutedText)
        }
    }
}
