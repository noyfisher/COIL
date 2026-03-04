import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    var onSignedIn: () -> Void
    @StateObject private var vm = LoginVM()
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Background
            AppColors.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top gradient section with branding
                ZStack {
                    // Gradient background
                    RoundedRectangle(cornerRadius: AppCorners.xxl)
                        .fill(AppColors.coolGradient)
                        .ignoresSafeArea(edges: .top)

                    VStack(spacing: AppSpacing.lg) {
                        Spacer()

                        // App icon
                        Image(systemName: "figure.run.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                        VStack(spacing: AppSpacing.sm) {
                            Text("PT Helper")
                                .font(AppFonts.heroTitle)
                                .foregroundColor(.white)

                            Text("Your personal recovery companion")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                        }

                        Spacer()
                    }
                    .padding(.bottom, AppSpacing.xxl)
                }
                .frame(height: UIScreen.main.bounds.height * 0.42)

                Spacer().frame(height: AppSpacing.xxl)

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
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 52)
                    .cornerRadius(AppCorners.card)

                    if let msg = vm.msg {
                        Text(msg)
                            .font(.footnote)
                            .foregroundColor(.secondary)
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
    }

    private func featurePill(icon: String, text: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
                .background(Color.blue.opacity(0.1))
                .clipShape(Circle())

            Text(text)
                .font(AppFonts.badge)
                .foregroundColor(.secondary)
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
