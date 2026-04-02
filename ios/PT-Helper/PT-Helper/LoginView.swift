import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

struct LoginView: View {
    var onSignedIn: () -> Void
    @StateObject private var vm = LoginVM()
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Branding
                VStack(spacing: AppSpacing.xl) {
                    // Pill badge
                    Text("PT Helper")
                        .font(AppFonts.badge)
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.accentTint)
                        .clipShape(Capsule())

                    // App icon
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 72))
                        .foregroundColor(AppColors.accent)

                    // Motivational headline
                    VStack(spacing: AppSpacing.sm) {
                        (Text("Your body has ")
                            + Text("goals").italic()
                            + Text(",\nnot just problems."))
                            .font(AppFonts.heroTitle)
                            .foregroundColor(AppColors.primaryText)
                            .multilineTextAlignment(.center)

                        Text("AI-powered recovery, personalized for you")
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                    }
                }

                Spacer().frame(height: AppSpacing.xxxl)

                // Feature highlights
                HStack(spacing: AppSpacing.lg) {
                    featurePill(icon: "brain.head.profile", text: "AI Analysis")
                    featurePill(icon: "list.clipboard", text: "Custom Plans")
                    featurePill(icon: "chart.line.uptrend.xyaxis", text: "Track Progress")
                }
                .padding(.horizontal, AppSpacing.xl)

                Spacer()

                // Sign in section
                VStack(spacing: AppSpacing.lg) {
                    SignInWithAppleButton(.signIn) { req in
                        vm.prepare(req)
                    } onCompletion: { result in
                        vm.handle(result) { onSignedIn() }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("login.appleSignInButton")

                    // Google Sign-In
                    Button {
                        vm.signInWithGoogle { onSignedIn() }
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "g.circle.fill")
                                .font(.title2)
                            Text("Sign in with Google")
                                .font(.body.weight(.medium))
                        }
                        .foregroundColor(AppColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppColors.cardBackground)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                    }
                    .accessibilityIdentifier("login.googleSignInButton")

                    if let msg = vm.msg {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(AppColors.secondaryText)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, AppSpacing.xxl)

                Spacer().frame(height: AppSpacing.xxxl)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
        .trackScreen("Login")
    }

    private func featurePill(icon: String, text: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(AppColors.accent)
                .frame(width: 40, height: 40)
                .background(AppColors.accentTint)
                .clipShape(Circle())

            Text(text)
                .font(AppFonts.badge)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}

final class LoginVM: NSObject, ObservableObject {
    @Published var msg: String?
    private var nonce: String?

    func prepare(_ req: ASAuthorizationAppleIDRequest) {
        let n = randomNonce()
        nonce = n
        req.requestedScopes = [.fullName, .email]
        req.nonce = sha256(n)
        msg = "Preparing sign in…"
        Task { @MainActor in SessionLogger.shared.log(.signInStarted, category: .auth, message: "Apple sign-in started") }
    }

    func handle(_ result: Result<ASAuthorization, Error>, onSuccess: @escaping () -> Void) {
        switch result {
        case .failure(let e):
            msg = "Apple error: \(e.localizedDescription)"
            Task { @MainActor in
                SessionLogger.shared.log(.signInFailed, category: .auth, message: "Apple sign-in failed",
                                          metadata: ["error": e.localizedDescription])
            }

        case .success(let auth):
            guard
                let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = cred.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let nonce
            else { msg = "Missing Apple token/nonce"; return }

            let fcred = OAuthProvider.appleCredential(withIDToken: idToken,
                                                      rawNonce: nonce,
                                                      fullName: cred.fullName) // fullName is optional; helps store display name on first sign-in


            Auth.auth().signIn(with: fcred) { res, err in
                if let err = err {
                    self.msg = "Firebase error: \(err.localizedDescription)"
                    Task { @MainActor in
                        SessionLogger.shared.log(.signInFailed, category: .auth, message: "Firebase sign-in failed",
                                                  metadata: ["error": err.localizedDescription])
                    }
                    return
                }
                self.msg = "Signed in ✅"
                Task { @MainActor in
                    SessionLogger.shared.log(.signInSucceeded, category: .auth, message: "Sign-in succeeded")
                }

                if let uid = res?.user.uid {
                    self.ensureUser(uid: uid,
                                    name: cred.fullName?.givenName ?? res?.user.displayName ?? "User")
                }
                onSuccess()
            }
        }
    }

    private func ensureUser(uid: String, name: String) {
        let db = Firestore.firestore()
        let ref = db.collection("users").document(uid)
        ref.getDocument { snap, _ in
            guard snap?.exists != true else { return }
            ref.setData([
                "name": name,
                "role": "athlete",                 // you can add a role picker later
                "created_at": FieldValue.serverTimestamp()
            ])
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle(onSuccess: @escaping () -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            msg = "Missing Firebase client ID"
            return
        }

        msg = "Preparing Google sign in…"
        Task { @MainActor in
            SessionLogger.shared.log(.signInStarted, category: .auth, message: "Google sign-in started")
        }

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else {
            msg = "Cannot find root view controller"
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        GIDSignIn.sharedInstance.signIn(withPresenting: rootVC) { [weak self] result, error in
            guard let self else { return }

            if let error {
                self.msg = "Google error: \(error.localizedDescription)"
                Task { @MainActor in
                    SessionLogger.shared.log(.signInFailed, category: .auth, message: "Google sign-in failed",
                                              metadata: ["error": error.localizedDescription])
                }
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                self.msg = "Missing Google token"
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { res, err in
                if let err {
                    self.msg = "Firebase error: \(err.localizedDescription)"
                    Task { @MainActor in
                        SessionLogger.shared.log(.signInFailed, category: .auth, message: "Firebase sign-in failed (Google)",
                                                  metadata: ["error": err.localizedDescription])
                    }
                    return
                }

                self.msg = "Signed in ✅"
                Task { @MainActor in
                    SessionLogger.shared.log(.signInSucceeded, category: .auth, message: "Google sign-in succeeded")
                }

                if let uid = res?.user.uid {
                    let displayName = user.profile?.givenName ?? user.profile?.name ?? "User"
                    self.ensureUser(uid: uid, name: displayName)
                }
                onSuccess()
            }
        }
    }

    // MARK: - nonce helpers
    private func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var out = ""; var left = length
        while left > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            for b in bytes where left > 0 {
                if b < chars.count { out.append(chars[Int(b)]); left -= 1 }
            }
        }
        return out
    }

    private func sha256(_ s: String) -> String {
        let h = SHA256.hash(data: Data(s.utf8))
        return h.map { String(format: "%02x", $0) }.joined()
    }
}
