import SwiftUI

/// Shows a celebratory overlay the instant an achievement is earned, then clears
/// it. `StreakService` already publishes `newlyEarned` and exposes
/// `clearNewlyEarned()` ("call after displaying celebration") but nothing observed
/// it, so earned badges were silent (audit #31). Apply `.achievementCelebration()`
/// to the screens where achievements get earned (workout summary, manual log).
struct AchievementCelebrationModifier: ViewModifier {
    @ObservedObject private var streakService = StreakService.shared

    func body(content: Content) -> some View {
        content.overlay {
            if let earned = streakService.newlyEarned {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    CelebrationOverlay(
                        icon: earned.iconName,
                        message: "\(earned.title) unlocked!",
                        iconColor: AppColors.accent
                    )
                }
                .transition(.opacity)
                .onAppear {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(AppAnimations.smooth) { streakService.clearNewlyEarned() }
                    }
                }
                .onTapGesture {
                    withAnimation(AppAnimations.smooth) { streakService.clearNewlyEarned() }
                }
                .accessibilityElement()
                .accessibilityLabel("Achievement unlocked: \(earned.title)")
            }
        }
        .animation(AppAnimations.springy, value: streakService.newlyEarned?.id)
    }
}

extension View {
    /// Overlays an achievement celebration whenever `StreakService.newlyEarned` is set.
    func achievementCelebration() -> some View {
        modifier(AchievementCelebrationModifier())
    }
}
