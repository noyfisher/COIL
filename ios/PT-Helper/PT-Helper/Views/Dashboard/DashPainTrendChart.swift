import SwiftUI
import Charts

struct DashPainTrendChart: View {
    let sessions: [WorkoutSession]

    private var recentSessions: [WorkoutSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -RecoveryInsightsViewModel.lookbackDays, to: Date()) ?? Date()
        return sessions
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Pain Trend (14 Days)")

            if recentSessions.isEmpty {
                Text("No recent sessions")
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.xxl)
            } else {
                Chart(recentSessions) { session in
                    LineMark(
                        x: .value("Date", session.date, unit: .day),
                        y: .value("Pain", session.painLevel)
                    )
                    .foregroundStyle(AppColors.dashAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", session.date, unit: .day),
                        y: .value("Pain", session.painLevel)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [AppColors.dashAccent.opacity(0.3), AppColors.dashAccent.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", session.date, unit: .day),
                        y: .value("Pain", session.painLevel)
                    )
                    .foregroundStyle(AppColors.dashAccent)
                    .symbolSize(30)
                }
                .chartYScale(domain: 0...10)
                .chartYAxis {
                    AxisMarks(values: [0, 2, 4, 6, 8, 10]) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.dashBorder)
                        AxisValueLabel {
                            Text("\(value.as(Int.self) ?? 0)")
                                .font(.caption2)
                                .foregroundColor(AppColors.dashTextSecondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(AppColors.dashBorder)
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.caption2)
                            .foregroundStyle(AppColors.dashTextSecondary)
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea.background(Color.clear)
                }
                .frame(height: 180)
            }
        }
        .dashWidget()
    }
}
