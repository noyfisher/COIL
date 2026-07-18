import SwiftUI

/// Banner prompting user to re-assess their pain levels at plan milestones.
struct ReAssessmentPromptView: View {
    let plan: RehabPlan
    let assessmentType: AssessmentSnapshot.AssessmentType
    var onStartAssessment: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "clipboard.fill")
                    .font(.title3)
                    .foregroundColor(AppColors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(AppFonts.smallSemiBold)
                    Text(subtitleText)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }

            Button(action: onStartAssessment) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Start Re-Assessment")
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppColors.ctaText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(AppColors.accent)
                .cornerRadius(AppCorners.medium)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.accentTint)
        .cornerRadius(AppCorners.card)
        .trackScreen("ReAssessmentPrompt")
    }

    private var titleText: String {
        switch assessmentType {
        case .midpoint: return "Midpoint Check-In"
        case .completion: return "Plan Complete!"
        case .initial: return "Initial Assessment"
        }
    }

    private var subtitleText: String {
        switch assessmentType {
        case .midpoint: return "You're halfway through! Let's check your progress."
        case .completion: return "Congratulations! Let's see how far you've come."
        case .initial: return "Record your starting pain levels."
        }
    }
}
