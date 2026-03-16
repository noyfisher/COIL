import SwiftUI

struct AnalysisResultView: View {
    let analysisResult: AnalysisResult
    var validationWarnings: [ValidationWarning] = []
    var redFlagAlerts: [ValidationWarning] = []
    @State private var showRehabPlan = false
    @State private var expandedConditions: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    /// Prefetched rehab plan VM — generation starts as soon as this view appears
    @StateObject private var rehabVM = RehabPlanViewModel()

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
            RehabPlanView(viewModel: rehabVM, analysisResult: analysisResult)
        }
        .onAppear {
            // Start generating the rehab plan in the background while the user
            // reads their analysis results — eliminates the second wait.
            rehabVM.generateRehabPlan(from: analysisResult)
        }
        .trackScreen("AnalysisResult")
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
        let isExpanded = expandedConditions.contains(condition.id.uuidString)

        return HStack(spacing: 0) {
            // Colored accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(matchColor(strength))
                .frame(width: 4)
                .padding(.vertical, AppSpacing.sm)

            VStack(alignment: .leading, spacing: 0) {
                // Header — always visible
                Button(action: {
                    withAnimation(AppAnimations.springy) {
                        if isExpanded {
                            expandedConditions.remove(condition.id.uuidString)
                        } else {
                            expandedConditions.insert(condition.id.uuidString)
                        }
                    }
                }) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(condition.commonName)
                                    .font(AppFonts.sectionTitle)
                                    .foregroundColor(.primary)
                                Text(condition.conditionName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                        }

                        // Match strength indicator
                        HStack(spacing: AppSpacing.sm) {
                            matchStrengthDots(strength)
                            Text(strength.rawValue)
                                .font(.caption.weight(.medium))
                                .foregroundColor(matchColor(strength))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(condition.commonName), \(strength.rawValue)")

                        // Red flag inline warning
                        if condition.isRedFlag {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                Text(condition.redFlagMessage ?? "Seek immediate medical attention")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(AppSpacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red)
                            .cornerRadius(AppCorners.small)
                        }
                    }
                    .padding(AppSpacing.lg)
                }
                .buttonStyle(.plain)

                // Expandable details
                if isExpanded {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        // Thin separator
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 1)
                            .padding(.horizontal, AppSpacing.lg)

                        // Explanation
                        Text(condition.explanation)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineSpacing(3)
                            .padding(.horizontal, AppSpacing.lg)

                        // What's happening
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("What's happening", systemImage: "figure.stand")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.blue)
                            Text(condition.whatItMeans)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineSpacing(3)
                        }
                        .padding(.horizontal, AppSpacing.lg)

                        // Next steps
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Label("Suggested next steps", systemImage: "list.number")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.purple)
                            ForEach(Array(condition.nextSteps.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: AppSpacing.sm) {
                                    Text("\(index + 1).")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.purple)
                                        .frame(width: 20, alignment: .leading)
                                    Text(step)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.lg)
                    }
                    .padding(.bottom, AppSpacing.lg)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.xl)
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
    }

    private func matchStrengthDots(_ strength: MatchStrength) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index, strength: strength))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func dotColor(for index: Int, strength: MatchStrength) -> Color {
        let filledCount: Int
        switch strength {
        case .strong: filledCount = 3
        case .moderate: filledCount = 2
        case .weak: filledCount = 1
        }
        return index < filledCount ? matchColor(strength) : Color(.systemGray5)
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
