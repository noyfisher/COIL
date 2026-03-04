import SwiftUI
import FirebaseAuth

struct RootView: View {
    @State private var signedIn = (Auth.auth().currentUser != nil)
    @State private var profileCompleted = false
    @State private var isCheckingProfile = true
    @State private var showError = false
    @State private var errorMessage = ""
    @StateObject private var profileService = UserProfileService.shared

    var body: some View {
        Group {
            if signedIn {
                if isCheckingProfile {
                    // Branded loading state
                    ZStack {
                        AppColors.pageBackground
                            .ignoresSafeArea()
                        VStack(spacing: AppSpacing.xl) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.system(size: 56))
                                .foregroundStyle(AppColors.coolGradient)
                                .symbolEffect(.pulse.byLayer, options: .repeating)

                            Text("Loading your profile...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
            _ = Auth.auth().addStateDidChangeListener { _, user in
                signedIn = (user != nil)
                if let user = user {
                    SessionLogger.shared.startSession(userId: user.uid)
                    checkProfileCompletion()
                } else {
                    SessionLogger.shared.log(.signedOut, category: .auth, message: "User signed out")
                    profileCompleted = false
                    isCheckingProfile = true
                    profileService.clear()
                }
            }
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
        }
    }
}
