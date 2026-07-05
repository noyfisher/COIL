import SwiftUI

struct DashDifferentialsTable: View {
    let conditions: [ConditionResult]
    @State private var expandedId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Possible Explanations")

            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(conditions.enumerated()), id: \.element.id) { index, condition in
                    differentialRow(rank: index + 1, condition: condition)
                }
            }

            Text("Match strength reflects how well each explanation fits the symptoms you reported — it's capped below certainty, because AI analysis should always be verified by a healthcare professional. These are possible explanations, not a diagnosis.")
                .font(.caption2)
                .foregroundColor(AppColors.dashTextSecondary)
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

                    // Qualitative match strength
                    let strength = ConfidenceCalibrator.matchStrength(for: condition.confidence)
                    Text(strength.rawValue)
                        .font(AppFonts.dataSmall)
                        .foregroundColor(strength == .strong ? AppColors.success
                            : strength == .moderate ? AppColors.warning : AppColors.dashTextSecondary)

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
}
