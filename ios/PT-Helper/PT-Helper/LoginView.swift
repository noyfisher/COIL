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
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Ink background (fixed dark)
            AppColors.darkSurface.ignoresSafeArea()

            // Diagonal red accent — top-right
            GeometryReader { geo in
                LinearGradient(
                    colors: [AppColors.accent.opacity(0.18), .clear],
                    startPoint: .topTrailing, endPoint: .bottomLeading
                )
                .frame(width: geo.size.width * 0.7, height: geo.size.height * 0.45)
                .offset(x: geo.size.width * 0.35, y: 0)

                // Bottom-left radial glow
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.12), .clear],
                    center: .bottomLeading, startRadius: 0, endRadius: 240
                )
                .frame(width: geo.size.width, height: geo.size.height * 0.5)
                .offset(y: geo.size.height * 0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: AppSpacing.xxxl)

                // COIL wordmark
                CoilWordmark(fontSize: 40, glyph: 46)
                    .padding(.horizontal, AppSpacing.xxl)

                Spacer()

                // Hero headline
                VStack(alignment: .leading, spacing: 0) {
                    Text("ASSESS.")
                        .font(Font.custom("Industry-Bold", size: 44))
                        .foregroundColor(AppColors.textOnDark)
                        .kerning(0.5)
                    Text("PLAN.")
                        .font(Font.custom("Industry-Bold", size: 44))
                        .foregroundColor(AppColors.accent)
                        .kerning(0.5)
                    Text("RECOVER.")
                        .font(Font.custom("Industry-Bold", size: 44))
                        .foregroundColor(AppColors.textOnDark)
                        .kerning(0.5)
                }
                .padding(.horizontal, AppSpacing.xxl)

                Spacer().frame(height: AppSpacing.lg)

                // Subhead
                Text("AI-powered recovery, built for COIL athletes.")
                    .font(AppFonts.body)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, AppSpacing.xxl)

                Spacer()

                // Sign-in buttons
                VStack(spacing: AppSpacing.md) {
                    SignInWithAppleButton(.signIn) { req in
                        vm.prepare(req)
                    } onCompletion: { result in
                        vm.handle(result) { onSignedIn() }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 52)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("login.appleSignInButton")

                    Button {
                        vm.signInWithGoogle { onSignedIn() }
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "g.circle.fill").font(.title2)
                            Text("Sign in with Google")
                                .font(Font.custom("Inter-SemiBold", size: 15))
                        }
                        .foregroundColor(AppColors.textOnDark)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.09))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    }
                    .accessibilityIdentifier("login.googleSignInButton")

                    if let msg = vm.msg {
                        Text(msg)
                            .font(AppFonts.caption)
                            .foregroundColor(.white.opacity(0.5))
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, AppSpacing.xxl)

                Spacer().frame(height: AppSpacing.lg)

                // Footer
                Text("For authorized COIL athletes only")
                    .font(AppFonts.micro)
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(height: AppSpacing.xxl)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
        .trackScreen("Login")
        .preferredColorScheme(.dark) // hero screen is intentionally dark in both app modes
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
