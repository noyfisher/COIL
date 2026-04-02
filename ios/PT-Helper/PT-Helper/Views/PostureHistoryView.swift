import SwiftUI
import Charts

/// Line chart + list showing the user's posture check score history.
struct PostureHistoryView: View {
    @ObservedObject private var vm = PostureCheckViewModel.shared
    @State private var selectedContext: PostureContext? = nil

    private var filteredResults: [PostureCheckResult] {
        guard let ctx = selectedContext else { return vm.history }
        return vm.history.filter { $0.context == ctx }
    }

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            if vm.history.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Context filter
                        contextFilter

                        // Score chart
                        if filteredResults.count >= 2 {
                            scoreChart
                        }

                        // List
                        historyList
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xxxl)
                }
            }
        }
        .navigationTitle("Posture History")
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen("PostureHistory")
    }

    // MARK: - Context Filter

    private var contextFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                filterChip(label: "All", icon: "line.3.horizontal", isSelected: selectedContext == nil) {
                    selectedContext = nil
                }
                ForEach(PostureContext.allCases) { ctx in
                    filterChip(label: ctx.displayName, icon: ctx.icon, isSelected: selectedContext == ctx) {
                        selectedContext = selectedContext == ctx ? nil : ctx
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xs)
        }
    }

    private func filterChip(label: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption)
                Text(label).font(.caption.weight(.medium))
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? AppColors.accent : AppColors.cardBackground)
            .foregroundColor(isSelected ? .white : AppColors.secondaryText)
            .cornerRadius(AppCorners.pill)
            .shadow(color: AppColors.cardShadowColor, radius: 2, y: 1)
        }
    }

    // MARK: - Score Chart

    @ViewBuilder
    private var scoreChart: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Score Over Time")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.mutedText)
                .textCase(.uppercase)
                .tracking(0.5)

            let sorted = filteredResults.sorted { $0.captureDate < $1.captureDate }

            Chart(sorted) { result in
                LineMark(
                    x: .value("Date", result.captureDate),
                    y: .value("Score", result.score)
                )
                .foregroundStyle(AppColors.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))

                PointMark(
                    x: .value("Date", result.captureDate),
                    y: .value("Score", result.score)
                )
                .foregroundStyle(AppColors.accent)
                .symbolSize(40)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(AppColors.subtleBorder)
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("\(v)").font(.caption2).foregroundColor(AppColors.mutedText)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(AppColors.subtleBorder)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.caption2)
                        .foregroundStyle(AppColors.mutedText)
                }
            }
            .frame(height: 160)

            // Average badge
            let avg = sorted.map(\.score).reduce(0, +) / max(sorted.count, 1)
            HStack(spacing: AppSpacing.xs) {
                Text("Average score: ")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                Text("\(avg)")
                    .font(.caption.weight(.bold))
                    .foregroundColor(AppColors.accent)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 6, x: 0, y: 2)
    }

    // MARK: - History List

    private var historyList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Recent Checks")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.mutedText)
                .textCase(.uppercase)
                .tracking(0.5)

            ForEach(filteredResults) { result in
                historyRow(result)
            }
        }
    }

    private func historyRow(_ result: PostureCheckResult) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Score badge
            ZStack {
                Circle()
                    .fill(scoreColor(result).opacity(0.12))
                    .frame(width: 46, height: 46)
                Text("\(result.score)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(result))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: result.context.icon)
                        .font(.caption)
                        .foregroundColor(AppColors.mutedText)
                    Text(result.context.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                Text(result.scoreLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.primaryText)
                if let obs = result.observations.first {
                    Text(obs)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(relativeDate(result.captureDate))
                .font(.caption2)
                .foregroundColor(AppColors.mutedText)
        }
        .padding(AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 3, x: 0, y: 1)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()
            Image(systemName: "person.fill.viewfinder")
                .font(.system(size: 56))
                .foregroundColor(AppColors.accentTint)

            VStack(spacing: AppSpacing.sm) {
                Text("No Posture Checks Yet")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                Text("Complete your first check-in to start tracking your alignment over time.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ result: PostureCheckResult) -> Color {
        switch result.score {
        case 80...100: return AppColors.success
        case 60..<80:  return AppColors.accent
        case 40..<60:  return AppColors.warning
        default:       return AppColors.danger
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
