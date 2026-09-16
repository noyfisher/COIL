import SwiftUI

/// Tab 3: Profile — "Who am I here and how am I doing?" A dark masthead built from
/// `ProfileSummary`, then the grouped settings body. Owns the Edit Health Info sheet.
struct ProfileTab: View {
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @ObservedObject private var profileService = UserProfileService.shared
    @ObservedObject private var streakService = StreakService.shared
    @State private var showEditProfile = false

    private var summary: ProfileSummary {
        ProfileSummaryBuilder.build(profile: profileService.profile,
                                    plans: savedPlansVM.rehabPlans,
                                    streak: streakService.streakData,
                                    sessionCount: workoutViewModel.sessions.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ProfileHeroCard(summary: summary) { showEditProfile = true }
                            .modifier(RevealOnAppear(index: 0))

                        SettingsView()
                            .padding(.top, AppSpacing.lg)
                    }
                    .floatingTabBarClearance()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .coilNavBar()
        }
        .sheet(isPresented: $showEditProfile) {
            OnboardingEditView()
        }
        .trackScreen("ProfileTab")
    }
}

// MARK: - Reveal

/// One fade-and-rise per section on first appearance, staggered by `index`.
/// Under Reduce Motion the offset is dropped and only the opacity animates.
struct RevealOnAppear: ViewModifier {
    let index: Int
    static let staggerSeconds: Double = 0.05

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : AppSpacing.md)
            .animation(AppAnimations.springy.delay(Double(index) * Self.staggerSeconds), value: appeared)
            .onAppear { appeared = true }
    }
}
