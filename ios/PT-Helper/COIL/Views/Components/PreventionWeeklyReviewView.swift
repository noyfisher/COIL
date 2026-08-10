import SwiftUI

/// Read-only weekly summary — deterministic, transparent, local-data-only.
/// No risk scores or predictive/diagnostic language (product constraint).
struct PreventionWeeklyReviewView: View {
    @ObservedObject var viewModel: PreventionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var review: PreventionWeeklyReview?

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let review {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        Text("\(Self.rangeFormatter.string(from: review.weekStart)) – \(Self.rangeFormatter.string(from: review.weekEnd))")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.mutedText)

                        HStack(spacing: AppSpacing.sm) {
                            Text("\(review.sessionCount)")
                                .font(AppFonts.statNumber)
                                .foregroundColor(AppColors.accent)
                                .accessibilityIdentifier("prevention.weeklyReview.sessionCount")
                            Text("prevention session\(review.sessionCount == 1 ? "" : "s") completed")
                                .font(AppFonts.small)
                                .foregroundColor(AppColors.secondaryText)
                        }
                        .cardStyle()

                        if !review.completionsByCategory.isEmpty {
                            CardSection(icon: "chart.bar.fill", color: AppColors.accent, title: "By Category") {
                                VStack(spacing: AppSpacing.sm) {
                                    ForEach(PreventionCategory.allCases) { category in
                                        if let count = review.completionsByCategory[category], count > 0 {
                                            categoryRow(category, count: count)
                                        }
                                    }
                                }
                            }
                        }

                        CardSection(icon: "checkmark.seal.fill", color: AppColors.success, title: "What's Working") {
                            Text(review.positiveInsight)
                                .font(AppFonts.body)
                                .foregroundColor(AppColors.primaryText)
                                .accessibilityIdentifier("prevention.weeklyReview.insight")
                        }

                        CardSection(icon: "arrow.forward.circle.fill", color: AppColors.info, title: "Next Week") {
                            Text(review.nextWeekAdjustment)
                                .font(AppFonts.body)
                                .foregroundColor(AppColors.primaryText)
                                .accessibilityIdentifier("prevention.weeklyReview.adjustment")
                        }
                    }
                    .padding(AppSpacing.lg)
                }
            }
            .background(AppColors.pageBackground.ignoresSafeArea())
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if review == nil { review = viewModel.weeklyReview() }
            }
        }
        .trackScreen("PreventionWeeklyReview")
    }

    private func categoryRow(_ category: PreventionCategory, count: Int) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: category.icon)
                .foregroundColor(AppColors.accent)
                .frame(width: 24)
            Text(category.displayName)
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.primaryText)
            Spacer()
            Text("\(count)")
                .font(AppFonts.bodySemiBold)
                .foregroundColor(AppColors.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.displayName): \(count) completed this week")
    }
}
