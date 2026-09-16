import SwiftUI

/// The Profile masthead: avatar, name, condition chips, three stats and the chosen
/// plan on the fixed-dark ink. It sits directly under the nav bar so the ink is
/// continuous (the same construction as Home's `WeekCompletionStrip`). Everything
/// comes in through `summary`; the card does no data access.
struct ProfileHeroCard: View {
    let summary: ProfileSummary
    var onEditHealthInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            identityRow

            if !summary.conditionChips.isEmpty {
                chips
            }

            statsRow

            if let plan = summary.activePlan {
                planRow(plan)
            }

            Button("Edit Health Info", action: onEditHealthInfo)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("settings.editProfileButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xxl)
        .background(AppColors.darkSurface)
    }

    // MARK: - Rows

    private var identityRow: some View {
        HStack(alignment: .top, spacing: AppSpacing.lg) {
            Text(summary.initials)
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.ctaText)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppColors.primaryGradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(summary.displayName)
                    .font(AppFonts.heroTitle)
                    .foregroundColor(AppColors.textOnDark)
                    .accessibilityIdentifier("profile.name")
                    .accessibilityAddTraits(.isHeader)
                if let detail = summary.detailLine {
                    Text(detail)
                        .font(AppFonts.small)
                        .foregroundColor(AppColors.textOnDarkMuted)
                        .accessibilityIdentifier("profile.detailLine")
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        FlowLayout(spacing: AppSpacing.sm) {
            ForEach(summary.conditionChips, id: \.self) { chip in
                Text(chip)
                    .font(AppFonts.smallMedium)
                    .foregroundColor(AppColors.textOnDark)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.tight)
                    .background(AppColors.onDarkChip)
                    .cornerRadius(AppCorners.small)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCorners.small)
                            .stroke(AppColors.onDarkChipBorder, lineWidth: 1)
                    )
            }
        }
        // Informational: one spoken element rather than four fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conditions: " + summary.conditionChips.joined(separator: ", "))
    }

    private var statsRow: some View {
        HStack(spacing: AppSpacing.md) {
            statColumn(value: "\(summary.stats.streak)", suffix: nil, label: "Day streak",
                       spoken: "\(summary.stats.streak) day streak",
                       identifier: "profile.streakStat")

            if let week = summary.stats.planWeek {
                statColumn(value: "\(week.current)", suffix: " / \(week.total)", label: "Plan week",
                           spoken: "Plan week \(week.current) of \(week.total)",
                           identifier: "profile.planWeekStat")
            } else {
                statColumn(value: "—", suffix: nil, label: "Plan week",
                           spoken: "No active plan week",
                           identifier: "profile.planWeekStat",
                           isPlaceholder: true)
            }

            statColumn(value: "\(summary.stats.sessions)", suffix: nil, label: "Sessions",
                       spoken: summary.stats.sessions == 1 ? "1 session" : "\(summary.stats.sessions) sessions",
                       identifier: "profile.sessionsStat")
        }
    }

    private func statColumn(value: String, suffix: String?, label: String,
                            spoken: String, identifier: String,
                            isPlaceholder: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(AppFonts.statNumber)
                    .foregroundColor(isPlaceholder ? AppColors.textOnDarkMuted : AppColors.accent)
                if let suffix {
                    Text(suffix)
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.textOnDarkMuted)
                }
            }
            Text(label)
                .font(AppFonts.micro)
                .textCase(.uppercase)
                .kerning(1)
                .foregroundColor(AppColors.textOnDarkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(identifier)
    }

    private func planRow(_ plan: ProfileSummary.ActivePlan) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if plan.isActive {
                CoilBadge(text: "Active")
            }
            VStack(alignment: .leading, spacing: AppSpacing.nano) {
                Text(plan.name)
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.textOnDark)
                Text(plan.statusText)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.textOnDarkMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.planRow")
    }
}

#if DEBUG
struct ProfileHeroCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.lg) {
            ProfileHeroCard(
                summary: ProfileSummary(
                    displayName: "Test User",
                    initials: "TU",
                    detailLine: "34 · Moderately Active",
                    conditionChips: ["Right Knee · Patellar tendinopathy", "Asthma"],
                    activePlan: .init(name: "Knee Rehab Plan", statusText: "Week 2 of 6", isActive: true),
                    stats: .init(streak: 3, planWeek: .init(current: 2, total: 6), sessions: 12)
                ),
                onEditHealthInfo: {}
            )

            ProfileHeroCard(
                summary: ProfileSummary(
                    displayName: "Your profile",
                    initials: "?",
                    detailLine: nil,
                    conditionChips: [],
                    activePlan: nil,
                    stats: .init(streak: 0, planWeek: nil, sessions: 0)
                ),
                onEditHealthInfo: {}
            )
        }
        .previewLayout(.sizeThatFits)
    }
}
#endif
