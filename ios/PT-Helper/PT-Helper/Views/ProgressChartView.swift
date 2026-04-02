import SwiftUI
import Charts

struct ProgressChartView: View {
    @EnvironmentObject private var viewModel: WorkoutViewModel
    @EnvironmentObject private var insightsVM: RecoveryInsightsViewModel
    @State private var selectedRegion: String? = nil

    var body: some View {
        ZStack {
            AppColors.pageBackground
                .ignoresSafeArea()

            if viewModel.sessions.isEmpty {
                EmptyStateView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "No Data Yet",
                    subtitle: "Complete workout sessions to see your progress over time"
                )
                .padding(.horizontal, AppSpacing.xl)
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        regionFilterPicker
                        painTrendChart
                        summaryStats

                        // AI Recovery Insights
                        RecoveryInsightsCardView(vm: insightsVM)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("ProgressChart")
    }

    // MARK: - Region Filter

    private var regionFilterPicker: some View {
        let regions = availableRegions
        if regions.isEmpty {
            return AnyView(EmptyView())
        }
        return AnyView(
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    filterChip(label: "Overall", isSelected: selectedRegion == nil) {
                        selectedRegion = nil
                    }
                    ForEach(regions, id: \.self) { region in
                        filterChip(
                            label: RegionPainInputView.displayName(for: region),
                            isSelected: selectedRegion == region
                        ) {
                            selectedRegion = region
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xs)
            }
        )
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? AppColors.accent : Color(.systemGray5))
                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
                .cornerRadius(AppCorners.medium)
        }
    }

    /// All unique region keys across sessions that have per-region data
    private var availableRegions: [String] {
        var regions = Set<String>()
        for session in viewModel.sessions {
            if let regionPain = session.regionPainLevels {
                regions.formUnion(regionPain.keys)
            }
        }
        return regions.sorted()
    }

    // MARK: - Pain Trend Chart

    private var painTrendChart: some View {
        let chartTitle = selectedRegion != nil
            ? "\(RegionPainInputView.displayName(for: selectedRegion!)) Pain"
            : "Pain Trend"

        return CardSection(icon: "chart.line.uptrend.xyaxis", color: AppColors.accent, title: chartTitle) {
            Chart(filteredChartData, id: \.id) { session in
                let painValue = painValueForChart(session)
                LineMark(
                    x: .value("Date", session.date),
                    y: .value("Pain", painValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accent.opacity(0.6)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                AreaMark(
                    x: .value("Date", session.date),
                    y: .value("Pain", painValue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accent.opacity(0.2), AppColors.accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                PointMark(
                    x: .value("Date", session.date),
                    y: .value("Pain", painValue)
                )
                .foregroundStyle(AppColors.accent)
                .symbolSize(30)
            }
            .chartYScale(domain: 0...10)
            .chartYAxis {
                AxisMarks(values: [0, 2, 4, 6, 8, 10]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(AppColors.mutedText.opacity(0.3))
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
        }
    }

    /// Sessions filtered by selected region (or all if no region selected)
    private var filteredChartData: [WorkoutSession] {
        guard let region = selectedRegion else {
            return viewModel.sessions
        }
        return viewModel.sessions.filter { $0.regionPainLevels?[region] != nil }
    }

    /// Get the pain value for chart based on selected region filter
    private func painValueForChart(_ session: WorkoutSession) -> Double {
        if let region = selectedRegion, let regionPain = session.regionPainLevels?[region] {
            return regionPain
        }
        return session.painLevel
    }

    // MARK: - Summary Stats

    private var summaryStats: some View {
        HStack(spacing: AppSpacing.md) {
            statCard(
                icon: "number",
                color: AppColors.accent,
                value: "\(viewModel.sessions.count)",
                label: "Sessions"
            )

            statCard(
                icon: "waveform.path.ecg",
                color: averagePainColor,
                value: String(format: "%.1f", averagePain),
                label: "Avg Pain"
            )

            statCard(
                icon: "clock",
                color: AppColors.warning,
                value: "\(totalMinutes)",
                label: "Total Min"
            )
        }
    }

    private func statCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15))
                .cornerRadius(AppCorners.small)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.primaryText)

            Text(label)
                .font(.caption2)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Computed Properties

    private var averagePain: Double {
        guard !viewModel.sessions.isEmpty else { return 0 }
        let total = viewModel.sessions.reduce(0.0) { $0 + $1.painLevel }
        return total / Double(viewModel.sessions.count)
    }

    private var averagePainColor: Color {
        switch Int(averagePain) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    private var totalMinutes: Int {
        Int(viewModel.sessions.reduce(0.0) { $0 + $1.duration } / 60)
    }
}
