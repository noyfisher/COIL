import SwiftUI

struct AnalysisResultView: View {
    let analysisResult: AnalysisResult
    @State private var showRehabPlan = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    if analysisResult.conditions.contains(where: { $0.isRedFlag }) {
                        redFlagAlert
                    }
                    disclaimerBanner
                    overallSummaryCard
                    ForEach(Array(analysisResult.conditions.prefix(3))) { condition in
                        conditionCard(for: condition)
                    }
                    buildRehabPlanButton
                    startNewAssessmentButton
                }
                .padding(20)
            }
        }
        .navigationTitle("Analysis Results")
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showRehabPlan) {
            NavigationStack {
                RehabPlanView(analysisResult: analysisResult)
            }
        }
    }

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

    private var overallSummaryCard: some View {
        CardSection(icon: "heart.text.clipboard", color: .blue, title: "What We Found") {
            Text(analysisResult.overallSummary)
                .font(.body)
                .foregroundColor(.primary)
                .lineSpacing(3)
        }
    }

    private func conditionCard(for condition: ConditionResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with common name and confidence
            VStack(alignment: .leading, spacing: 4) {
                Text(condition.commonName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)
                Text(condition.conditionName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ProgressView(value: condition.confidence, total: 100)
                        .progressViewStyle(LinearProgressViewStyle(tint: confidenceColor(condition.confidence)))
                        .frame(width: 80)
                        .accessibilityHidden(true)
                    Text("\(Int(condition.confidence))% match")
                        .font(.caption.weight(.medium))
                        .foregroundColor(confidenceColor(condition.confidence))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(condition.commonName), \(Int(condition.confidence)) percent match")
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))

            Divider()

            // Explanation
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(condition.explanation)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineSpacing(2)

                if condition.isRedFlag {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                        Text(condition.redFlagMessage ?? "Seek immediate medical attention")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red)
                    .cornerRadius(AppCorners.small)
                }

                // What's happening in your body
                VStack(alignment: .leading, spacing: 6) {
                    Label("What's happening", systemImage: "figure.stand")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    Text(condition.whatItMeans)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }

                // What you can do right now
                VStack(alignment: .leading, spacing: 6) {
                    Label("What you can do", systemImage: "hand.thumbsup.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                    Text(condition.howToManage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                }

                // Next steps
                VStack(alignment: .leading, spacing: 6) {
                    Label("Recommended next steps", systemImage: "list.number")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.purple)
                    ForEach(Array(condition.nextSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
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
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 70...: return .green
        case 40...: return .orange
        default: return .red
        }
    }

    private var redFlagAlert: some View {
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
        .background(Color.red)
        .cornerRadius(AppCorners.card)
    }

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

    private var startNewAssessmentButton: some View {
        Button(action: {
            NotificationCenter.default.post(name: .popToRoot, object: nil)
        }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                Text("Start New Assessment")
            }
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}
