import SwiftUI
import FirebaseAuth
import FirebaseCrashlytics

struct RootView: View {
    @State private var signedIn = (Auth.auth().currentUser != nil)
    @State private var profileCompleted = false
    @State private var isCheckingProfile = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasLoggedSignIn = false
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var consentService = ConsentService.shared
    /// Drives the launch-time ToS re-acceptance gate (production branch only).
    @State private var showLegalGate = false
    @AppStorage("hasSeenIntroCarousel") private var hasSeenIntroCarousel = false
    /// Set when the user taps Skip on onboarding, so the choice survives a
    /// relaunch instead of re-trapping them in the questionnaire every launch.
    @AppStorage("skippedOnboarding") private var skippedOnboarding = false
    /// Set when the user *completes* onboarding, so the app hands them straight
    /// into their first assessment (consumed + cleared by ThreeTabView).
    @AppStorage("pendingFirstAssessment") private var pendingFirstAssessment = false

    /// UI testing mode: bypass Firebase Auth and route based on launch arguments.
    /// Virtual user mode (`--virtual-user-token`) takes precedence: it must use
    /// the real production auth path, so the uitesting bypass is disabled.
    private var isUITesting: Bool {
        TestDataSeeder.isUITesting && TestDataSeeder.virtualUserToken == nil
    }

    @State private var hasAttemptedVirtualSignIn = false

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
                    Crashlytics.crashlytics().setUserID(user.uid)
                    AnalyticsService.shared.setUserId(user.uid)
                    if !hasLoggedSignIn {
                        hasLoggedSignIn = true
                        AnalyticsService.shared.log(.signInCompleted)
                    }
                    Task { await ConsentService.shared.load() }
                    checkProfileCompletion()
                } else {
                    SessionLogger.shared.log(.signedOut, category: .auth, message: "User signed out")
                    Crashlytics.crashlytics().setUserID("")
                    AnalyticsService.shared.setUserId(nil)
                    NotificationService.shared.clearFCMToken()
                    OnboardingViewModel.clearDraft()
                    profileCompleted = false
                    // Reset the skip flag so a different account on this device
                    // isn't silently auto-skipped past onboarding.
                    skippedOnboarding = false
                    isCheckingProfile = true
                    profileService.clear()
                    ConsentService.clearLocalMirrors()
                }
            }
            attemptVirtualUserSignInIfNeeded()
        }
    }

    /// Signs in with a custom token when launched in virtual user mode.
    /// Runs after the auth state listener is registered so the resulting
    /// state change is observed like any real sign-in. Signs out any
    /// previously persisted user so the token's vuser always wins.
    private func attemptVirtualUserSignInIfNeeded() {
        guard let token = TestDataSeeder.virtualUserToken, !hasAttemptedVirtualSignIn else { return }
        hasAttemptedVirtualSignIn = true
        Task {
            do {
                if Auth.auth().currentUser != nil {
                    try Auth.auth().signOut()
                }
                let result = try await Auth.auth().signIn(withCustomToken: token)
                print("[VirtualUser] signed in as \(result.user.uid)")
            } catch {
                print("[VirtualUser] sign-in failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UI Testing Content

    @ViewBuilder
    private var uiTestingContent: some View {
        if TestDataSeeder.showIntroCarousel {
            IntroCarouselView(onComplete: {})
        } else if TestDataSeeder.shouldSkipOnboarding || profileCompleted {
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
            } else if profileCompleted || skippedOnboarding {
                MainTabView()
                    .fullScreenCover(isPresented: $showLegalGate) {
                        LegalAcceptanceGateView(mode: .reacceptance) { _ in showLegalGate = false }
                    }
                    .onChange(of: consentService.isLoaded) { _, loaded in
                        if loaded && consentService.needsLegalReacceptance { showLegalGate = true }
                    }
                    .onAppear {
                        if consentService.isLoaded && consentService.needsLegalReacceptance { showLegalGate = true }
                    }
            } else if !hasSeenIntroCarousel {
                IntroCarouselView(onComplete: {
                    hasSeenIntroCarousel = true
                })
            } else {
                OnboardingView(onComplete: {
                    pendingFirstAssessment = true
                    profileCompleted = true
                }, onSkip: {
                    skippedOnboarding = true
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
