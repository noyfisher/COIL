import SwiftUI

/// Subtle background that visibly "grows" as the user moves through the pain
/// wizard — a soft accent tint rises from the bottom in step with progress, so a
/// wall of forms feels like momentum (audit #79). Previously it took a `step`
/// parameter and ignored it, rendering a flat fill.
struct AssessmentGrowthBackground: View {
    let step: Int
    /// The pain wizard is a fixed 8-step (0-indexed) flow.
    private let totalSteps = 8

    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()

            GeometryReader { geo in
                let progress = min(1.0, Double(step + 1) / Double(totalSteps))
                LinearGradient(
                    colors: [AppColors.accent.opacity(0.07), AppColors.accent.opacity(0.0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(height: geo.size.height * progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(AppAnimations.smooth, value: step)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}
