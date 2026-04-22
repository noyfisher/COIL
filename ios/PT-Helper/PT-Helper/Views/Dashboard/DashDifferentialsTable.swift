import SwiftUI

struct DashDifferentialsTable: View {
    let conditions: [ConditionResult]
    @State private var expandedId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Differential Analysis")

            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                    differentialRow(rank: index + 1, condition: condition)
                }
            }
        }
        .dashWidget()
    }

    @ViewBuilder
    private func differentialRow(rank: Int, condition: ConditionResult) -> some View {
        let isExpanded = expandedId == condition.id

        VStack(alignment: .leading, spacing: isExpanded ? AppSpacing.sm : 0) {
            Button {
                withAnimation(AppAnimations.smooth) {
                    expandedId = isExpanded ? nil : condition.id
                }
            } label: {
                HStack(spacing: AppSpacing.md) {
                    // Rank
                    Text("\(rank)")
                        .font(AppFonts.dataSmall)
                        .foregroundColor(AppColors.dashAccent)
                        .frame(width: 20)

                    // Name + red flag
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: AppSpacing.xs) {
                            Text(condition.commonName)
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(AppColors.dashTextPrimary)
                                .lineLimit(1)
                            if condition.isRedFlag {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundColor(AppColors.dashDanger)
                            }
                        }
                    }

                    Spacer()

                    // Confidence bar + %
                    HStack(spacing: AppSpacing.sm) {
                        confidenceBar(condition.confidence)
                        Text("\(Int(condition.confidence))%")
                            .font(AppFonts.dataSmall)
                            .foregroundColor(AppColors.dashTextPrimary)
                            .frame(width: 36, alignment: .trailing)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(AppColors.dashTextSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }

            if isExpanded {
                Text(condition.explanation)
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
                    .padding(.leading, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if rank < conditions.count {
                Divider()
                    .background(AppColors.dashBorder)
            }
        }
    }

    private func confidenceBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.dashBorder)
                    .frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(AppColors.dashAccentGradient)
                    .frame(width: geo.size.width * value / 100, height: 4)
            }
        }
        .frame(width: 60, height: 4)
    }
}
