import SwiftUI
import Charts

struct DashConfidenceChart: View {
    let conditions: [ConditionResult]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Confidence Breakdown")

            Chart(conditions) { condition in
                BarMark(
                    x: .value("Confidence", condition.confidence),
                    y: .value("Condition", shortName(condition.commonName))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.dashAccent, AppColors.dashSecondaryAccent],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 4) {
                    Text("\(Int(condition.confidence))%")
                        .font(AppFonts.dataSmall)
                        .foregroundColor(AppColors.dashTextSecondary)
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(AppColors.dashBorder)
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)")
                            .font(.caption2)
                            .foregroundColor(AppColors.dashTextSecondary)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption)
                        .foregroundStyle(AppColors.dashTextPrimary)
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.clear)
            }
            .frame(height: CGFloat(max(conditions.count, 1)) * 44)
        }
        .dashWidget()
    }

    private func shortName(_ name: String) -> String {
        if name.count > 22 {
            return String(name.prefix(20)) + "..."
        }
        return name
    }
}
