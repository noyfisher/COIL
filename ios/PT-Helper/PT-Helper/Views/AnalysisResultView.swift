import SwiftUI

struct AnalysisResultView: View {
    let analysisResult: AnalysisResult
    var validationWarnings: [ValidationWarning] = []
    var redFlagAlerts: [ValidationWarning] = []
    @State private var showRehabPlan = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    // App-detected red flags (from validation pipeline)
                    if !redFlagAlerts.isEmpty {
                        appRedFlagAlert
                    }
                    // AI-detected red flags
                    if analysisResult.conditions.contains(where: { $0.isRedFlag }) {
                        aiRedFlagAlert
                    }
                    disclaimerBanner
                    // Validation cautions (if any)
                    if !cautionWarnings.isEmpty {
                        validationCautionBanner
                    }
                    overallSummaryCard
                    ForEach(Array(analysisResult.conditions.prefix(3))) { condition in
                        conditionCard(for: condition)
                    }
                    buildRehabPlanButton
                    navigationButtons
                }
                .padding(20)
            }
        }
        .navigationTitle("Analysis Results")
        .navigationDestination(isPresented: $showRehabPlan) {
            RehabPlanView(analysisResult: analysisResult)
        }
    }

    // MARK: - Filtered Warnings

    /// Caution-level warnings from validation (not red flags)
    private var cautionWarnings: [ValidationWarning] {
        validationWarnings.filter { $0.severity == .caution }
    }

    // MARK: - Disclaimer

    private var disclaimerBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.blue)
            Text(analysisResult.disclaimerText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.08))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Validation Caution Banner

    private var validationCautionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Things to Keep in Mind")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
            }
            ForEach(Array(cautionWarnings.enumerated()), id: \.offset) { _, warning in
                Text("• \(warning.message)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Summary

    private var overallSummaryCard: some View {
        CardSection(icon: "heart.text.clipboard", color: .blue, title: "What We Found") {
            Text(analysisResult.overallSummary)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(3)
        }
    }

    // MARK: - Condition Card

    private func conditionCard(for condition: ConditionResult) -> some View {
        let strength = ConfidenceCalibrator.matchStrength(for: condition.confidence)
        let calibrated = ConfidenceCalibrator.calibrate(condition.confidence)

        return VStack(alignment: .leading, spacing: 0) {
            // Header with common name and match strength
            VStack(alignment: .leading, spacing: 4) {
                Text(condition.commonName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                Text(condition.conditionName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ProgressView(value: calibrated, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: matchColor(strength)))
                        .frame(width: 80)
                        .accessibilityHidden(true)
                    Text(strength.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundColor(matchColor(strength))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(condition.commonName), \(strength.rawValue)")
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))

            Divider()

            // Explanation
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(condition.explanation)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineSpacing(3)

                if condition.isRedFlag {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.body)
                        Text(condition.redFlagMessage ?? "Seek immediate medical attention")
                            .font(.body.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
                    .cornerRadius(AppCorners.small)
                }

                // What's happening in your body
                VStack(alignment: .leading, spacing: 8) {
                    Label("What's happening", systemImage: "figure.stand")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.blue)
                    Text(condition.whatItMeans)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineSpacing(3)
                }

                // Suggested next steps
                VStack(alignment: .leading, spacing: 8) {
                    Label("Suggested next steps", systemImage: "list.number")
                        .font(.body.weight(.semibold))
                        .foregroundColor(.purple)
                    ForEach(Array(condition.nextSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.purple)
                                .frame(width: 20, alignment: .leading)
                            Text(step)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func matchColor(_ strength: MatchStrength) -> Color {
        switch strength {
        case .strong: return .green
        case .moderate: return .orange
        case .weak: return .gray
        }
    }

    // MARK: - App-Detected Red Flag Alert

    private var appRedFlagAlert: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Important Safety Notice")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Based on what you reported, please read this carefully")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
            }
            ForEach(Array(redFlagAlerts.enumerated()), id: \.offset) { _, alert in
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .padding()
        .background(Color.red)
        .cornerRadius(AppCorners.card)
    }

    // MARK: - AI-Detected Red Flag Alert

    private var aiRedFlagAlert: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Please Read This Carefully")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Some of your symptoms may need urgent attention")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
            }
            ForEach(analysisResult.conditions.filter({ $0.isRedFlag })) { condition in
                Text(condition.redFlagMessage ?? "")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))
            }
        }
        .padding()
        .background(Color.red.opacity(0.85))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Buttons

    private var buildRehabPlanButton: some View {
        Button(action: { showRehabPlan = true }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "figure.run")
                Text("Build Rehab Plan")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .padding(.top, AppSpacing.lg)
    }

    private var navigationButtons: some View {
        VStack(spacing: AppSpacing.md) {
            Button(action: {
                dismiss()
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "chevron.left")
                    Text("Back to Assessment")
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Button(action: {
                NotificationCenter.default.post(name: .popToRoot, object: nil)
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "house")
                    Text("Home")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}
