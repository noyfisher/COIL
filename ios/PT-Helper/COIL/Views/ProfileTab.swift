import SwiftUI

/// Tab 3: Profile — "Who am I here and how am I doing?" A dark masthead built from
/// `ProfileSummary`, then the grouped settings body. Owns the Edit Health Info sheet.
struct ProfileTab: View {
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @ObservedObject private var profileService = UserProfileService.shared
    @ObservedObject private var streakService = StreakService.shared
    @State private var showEditProfile = false
    @State private var isDeletingAccount = false

    private var summary: ProfileSummary {
        ProfileSummaryBuilder.build(profile: profileService.profile,
                                    plans: savedPlansVM.rehabPlans,
                                    streak: streakService.streakData,
                                    sessionCount: workoutViewModel.sessions.count)
    }

    /// Full-viewport shield while the server deletes the account. Lives here, outside the
    /// scroll view, so it covers the screen wherever Delete Account was tapped and blocks
    /// every touch beneath it.
    private var deletingAccountOverlay: some View {
        ZStack {
            AppColors.primaryText.opacity(0.4).ignoresSafeArea()
            VStack(spacing: AppSpacing.md) {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(AppColors.ctaText)
                Text("Deleting account...")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.primaryText)
            }
            .padding(AppSpacing.xxl)
            .background(.ultraThinMaterial)
            .cornerRadius(AppCorners.large)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Deleting account")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ProfileHeroCard(summary: summary) { showEditProfile = true }
                            .modifier(RevealOnAppear(index: 0))

                        SettingsView(isDeletingAccount: $isDeletingAccount)
                            .padding(.top, AppSpacing.lg)
                    }
                    .floatingTabBarClearance()
                }

                if isDeletingAccount {
                    deletingAccountOverlay
                        .transition(.opacity)
                }
            }
            .animation(AppAnimations.smooth, value: isDeletingAccount)
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
