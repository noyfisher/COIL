import SwiftUI
import FirebaseAuth

struct RootView: View {
    @State private var signedIn = (Auth.auth().currentUser != nil)
    @State private var profileCompleted = false
    @State private var isCheckingProfile = true
    @State private var showError = false
    @State private var errorMessage = ""
    @StateObject private var profileService = UserProfileService.shared

    /// UI testing mode: bypass Firebase Auth and route based on launch arguments.
    private var isUITesting: Bool {
        TestDataSeeder.isUITesting
    }

    var body: some View {
        Group {
            if isUITesting {
                uiTestingContent
            } else {
                productionContent
            }
        }
        .alert("Connection Error", isPresented: $showError) {
            Button("Retry") {
                isCheckingProfile = true
                checkProfileCompletion()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            guard !isUITesting else { return }
            _ = Auth.auth().addStateDidChangeListener { _, user in
                signedIn = (user != nil)
                if let user = user {
                    SessionLogger.shared.startSession(userId: user.uid)
                    AnalyticsService.shared.setUserId(user.uid)
                    AnalyticsService.shared.log(.signInCompleted)
                    checkProfileCompletion()
                } else {
                    SessionLogger.shared.log(.signedOut, category: .auth, message: "User signed out")
                    AnalyticsService.shared.setUserId(nil)
                    profileCompleted = false
                    isCheckingProfile = true
                    profileService.clear()
                }
            }
        }
    }

    // MARK: - UI Testing Content

    @ViewBuilder
    private var uiTestingContent: some View {
        if TestDataSeeder.shouldSkipOnboarding {
            MainTabView()
        } else {
            OnboardingView(onComplete: {
                profileCompleted = true
            }, onSkip: {
                profileCompleted = true
            })
        }
    }

    // MARK: - Production Content

    @ViewBuilder
    private var productionContent: some View {
        if signedIn {
            if isCheckingProfile {
                ZStack {
                    AppColors.bgGradient
                        .ignoresSafeArea()
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 56))
                            .foregroundColor(AppColors.accent)
                            .symbolEffect(.pulse.byLayer, options: .repeating)

                        Text("Loading your profile...")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }
            } else if profileCompleted {
                MainTabView()
            } else {
                OnboardingView(onComplete: {
                    profileCompleted = true
                }, onSkip: {
                    profileCompleted = true
                })
            }
        } else {
            LoginView(onSignedIn: { signedIn = true })
        }
    }

    private func checkProfileCompletion() {
        Task {
            let exists = await profileService.checkProfileExists()
            if let error = profileService.loadError {
                errorMessage = error
                showError = true
            }
            profileCompleted = exists
            isCheckingProfile = false
            if exists, let profile = profileService.profile {
                AnalyticsService.shared.setUserProperties(
                    activityLevel: profile.activityLevel,
                    hasProfile: true
                )
            }
        }
    }
}
