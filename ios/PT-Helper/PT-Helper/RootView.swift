import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct RootView: View {
    @State private var signedIn = (Auth.auth().currentUser != nil)
    @State private var profileCompleted = false
    @State private var isCheckingProfile = true
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Group {
            if signedIn {
                if isCheckingProfile {
                    // Loading state while checking profile
                    ZStack {
                        Color(.systemGroupedBackground)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if profileCompleted {
                    ContentView()
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
            Auth.auth().addStateDidChangeListener { _, user in
                signedIn = (user != nil)
                if signedIn {
                    checkProfileCompletion()
                } else {
                    profileCompleted = false
                    isCheckingProfile = true
                }
            }
        }
    }

    private func checkProfileCompletion() {
        guard let uid = Auth.auth().currentUser?.uid else {
            isCheckingProfile = false
            return
        }
        let db = Firestore.firestore()
        db.collection("users").document(uid).collection("profile").document("health").getDocument { snapshot, error in
            if let error = error {
                AppLogger.auth.error("Error checking profile: \(error.localizedDescription)")
                errorMessage = "We couldn't load your profile. Please check your internet connection and try again."
                showError = true
                isCheckingProfile = false
            } else {
                profileCompleted = snapshot?.exists ?? false
                isCheckingProfile = false
            }
        }
    }
}
