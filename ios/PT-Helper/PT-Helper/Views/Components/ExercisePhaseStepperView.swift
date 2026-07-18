import SwiftUI

/// Interactive 3-step instruction stepper showing Setup → Move → Return
/// one phase at a time. Handles nil fields gracefully — only shows
/// non-nil phases, and falls back to exercise description if all are nil.
struct ExercisePhaseStepperView: View {
    let startPosition: String?
    let movement: String?
    let endPosition: String?
    let exerciseDescription: String?
    @Binding var isExpanded: Bool
    @State private var activePhase: Int = 0

    private var phases: [(label: String, text: String)] {
        var result: [(String, String)] = []
        if let start = startPosition { result.append(("Setup", start)) }
        if let move = movement { result.append(("Move", move)) }
        if let end = endPosition { result.append(("Return", end)) }
        return result
    }

    private var hasPhases: Bool { !phases.isEmpty }

    var body: some View {
        if isExpanded {
            if hasPhases {
                phaseStepperContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let desc = exerciseDescription, !desc.isEmpty {
                descriptionFallback(desc)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Phase Stepper

    private var phaseStepperContent: some View {
        VStack(spacing: AppSpacing.md) {
            // Phase pills
            HStack(spacing: 6) {
                ForEach(Array(phases.enumerated()), id: \.offset) { index, phase in
                    Button {
                        withAnimation(AppAnimations.smooth) {
                            activePhase = index
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text("STEP \(index + 1)")
                                .font(AppFonts.badge)
                                .opacity(0.7)
                            Text(phase.label)
                                .font(AppFonts.captionSemiBold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(index == activePhase ? AppColors.accent : AppColors.accentTint)
                        .foregroundColor(index == activePhase ? .white : AppColors.accent)
                        .cornerRadius(AppCorners.small)
                    }
                }
            }

            // Active phase content
            if activePhase < phases.count {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(phases[activePhase].text)
                        .font(AppFonts.small)
                        .foregroundColor(AppColors.primaryText)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
            }
        }
    }

    // MARK: - Description Fallback

    private func descriptionFallback(_ description: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(description)
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 4, y: 1)
    }
}
