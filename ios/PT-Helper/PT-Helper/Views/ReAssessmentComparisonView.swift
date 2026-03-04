import SwiftUI
import Charts

/// Side-by-side before/after comparison of pain assessments.
struct ReAssessmentComparisonView: View {
    let initial: AssessmentSnapshot
    let latest: AssessmentSnapshot
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Image(systemName: overallImproved ? "arrow.down.heart.fill" : "heart.fill")
                        .font(.system(size: 40))
                        .foregroundColor(overallImproved ? .green : .orange)

                    Text(overallImproved ? "You're Improving!" : "Keep Going!")
                        .font(.title2.weight(.bold))

                    Text("Comparing \(initial.assessmentType.rawValue) to \(latest.assessmentType.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.lg)

                // Overall pain comparison
                CardSection(icon: "waveform.path.ecg", color: .blue, title: "Overall Pain") {
                    HStack(spacing: AppSpacing.xl) {
                        painComparisonColumn(label: "Before", value: initial.overallPain)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                        painComparisonColumn(label: "After", value: latest.overallPain)
                        Spacer()
                        changeIndicator(before: initial.overallPain, after: latest.overallPain)
                    }
                }

                // Per-region comparison
                if !allRegions.isEmpty {
                    CardSection(icon: "figure.arms.open", color: .purple, title: "Pain by Region") {
                        VStack(spacing: AppSpacing.md) {
                            ForEach(allRegions, id: \.self) { region in
                                regionComparisonRow(region: region)
                            }
                        }
                    }
                }

                // Chart
                if !allRegions.isEmpty {
                    CardSection(icon: "chart.bar", color: .green, title: "Comparison Chart") {
                        Chart {
                            ForEach(allRegions, id: \.self) { region in
                                let beforeVal = initial.regionPainLevels[region] ?? 0
                                let afterVal = latest.regionPainLevels[region] ?? 0

                                BarMark(
                                    x: .value("Region", RegionPainInputView.displayName(for: region)),
                                    y: .value("Pain", beforeVal)
                                )
                                .foregroundStyle(by: .value("When", "Before"))
                                .position(by: .value("When", "Before"))

                                BarMark(
                                    x: .value("Region", RegionPainInputView.displayName(for: region)),
                                    y: .value("Pain", afterVal)
                                )
                                .foregroundStyle(by: .value("When", "After"))
                                .position(by: .value("When", "After"))
                            }
                        }
                        .chartYScale(domain: 0...10)
                        .chartForegroundStyleScale(["Before": Color.red.opacity(0.7), "After": Color.green.opacity(0.7)])
                        .frame(height: 220)
                    }
                }

                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
        .navigationTitle("Progress Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("ReAssessmentComparison")
    }

    // MARK: - Components

    private func painComparisonColumn(label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(format: "%.1f", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(painColor(for: value))
        }
    }

    private func changeIndicator(before: Double, after: Double) -> some View {
        let diff = after - before
        let improved = diff < 0
        return HStack(spacing: 2) {
            Image(systemName: improved ? "arrow.down" : (diff > 0 ? "arrow.up" : "equal"))
                .font(.caption)
            Text(String(format: "%+.1f", diff))
                .font(.caption.weight(.bold))
        }
        .foregroundColor(improved ? .green : (diff > 0 ? .red : .secondary))
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(improved ? Color.green.opacity(0.1) : (diff > 0 ? Color.red.opacity(0.1) : Color.gray.opacity(0.1)))
        .cornerRadius(AppCorners.small)
    }

    private func regionComparisonRow(region: String) -> some View {
        let before = initial.regionPainLevels[region] ?? 0
        let after = latest.regionPainLevels[region] ?? 0

        return HStack {
            Text(RegionPainInputView.displayName(for: region))
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)

            Spacer()

            Text(String(format: "%.0f", before))
                .font(.caption.weight(.medium))
                .foregroundColor(.red.opacity(0.8))
                .frame(width: 30)

            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(String(format: "%.0f", after))
                .font(.caption.weight(.medium))
                .foregroundColor(.green)
                .frame(width: 30)

            changeIndicator(before: before, after: after)
        }
    }

    // MARK: - Computed

    private var allRegions: [String] {
        let regions = Set(initial.regionPainLevels.keys).union(Set(latest.regionPainLevels.keys))
        return regions.sorted()
    }

    private var overallImproved: Bool {
        latest.overallPain < initial.overallPain
    }

    private func painColor(for level: Double) -> Color {
        switch Int(level) {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }
}
