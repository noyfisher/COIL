import SwiftUI

struct DashActivePlansList: View {
    let plans: [RehabPlan]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            DashSectionHeader(title: "Active Plans")

            if plans.isEmpty {
                Text("No plans yet")
                    .font(.caption)
                    .foregroundColor(AppColors.dashTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpacing.lg)
            } else {
                ForEach(plans.prefix(3)) { plan in
                    HStack(spacing: 0) {
                        NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                            planInfo(plan)
                        }
                        .buttonStyle(.plain)

                        NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.dashAccent)
                                .frame(width: 32, height: 32)
                                .background(AppColors.dashAccent.opacity(0.15))
                                .cornerRadius(AppCorners.pill)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .dashWidget()
    }

    private func planInfo(_ plan: RehabPlan) -> some View {
        HStack(spacing: AppSpacing.md) {
            // Plan icon
            Image(systemName: "list.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.dashAccent)
                .frame(width: 32, height: 32)
                .background(AppColors.dashAccent.opacity(0.15))
                .cornerRadius(AppCorners.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.planName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.dashTextPrimary)
                    .lineLimit(1)

                HStack(spacing: AppSpacing.sm) {
                    Text("\(plan.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(AppColors.dashTextSecondary)

                    if let week = plan.currentWeek {
                        Text("Week \(week)/\(plan.totalWeeks)")
                            .font(AppFonts.dataSmall)
                            .foregroundColor(AppColors.dashAccent)
                    }
                }
            }

            Spacer()
        }
    }
}
