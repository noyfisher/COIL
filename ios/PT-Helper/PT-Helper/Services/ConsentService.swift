import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Records and mirrors the user's legal-document acceptance (Terms of Service /
/// Privacy Policy). The canonical record lives at `users/{uid}/consents/legal`;
/// a UserDefaults mirror lets the launch-time re-acceptance gate decide without
/// waiting on a network round-trip and keeps working offline.
@MainActor
final class ConsentService: ObservableObject {
    static let shared = ConsentService()

    /// The ToS version the user has on record (nil until loaded / never accepted).
    @Published var recordedTosVersion: String?
    /// True once `load()` has finished (from Firestore or the offline mirror).
    @Published var isLoaded = false

    private let db = Firestore.firestore()

    // MARK: - UserDefaults mirror keys

    private enum MirrorKeys {
        static let tosVersion = "consent.tosVersion"
        static let healthDataPolicyVersion = "consent.healthDataPolicyVersion"
    }

    private init() {}

    // MARK: - Re-acceptance

    /// Whether the recorded ToS version is missing or older than the current one.
    var needsLegalReacceptance: Bool {
        ConsentPolicy.needsLegalReacceptance(recordedVersion: recordedTosVersion)
    }

    // MARK: - Load

    /// Hydrates from the offline mirror first (so the gate can decide immediately),
    /// then reads the authoritative record from Firestore and updates the mirror.
    /// Offline / errors fall back to the mirror. Always sets `isLoaded = true`.
    func load() async {
        // Hydrate from the mirror first.
        recordedTosVersion = UserDefaults.standard.string(forKey: MirrorKeys.tosVersion)

        guard let uid = Auth.auth().currentUser?.uid else {
            isLoaded = true
            return
        }

        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("consents").document("legal").getDocument()
            if let data = snapshot.data(), let version = data["tosVersion"] as? String {
                recordedTosVersion = version
                UserDefaults.standard.set(version, forKey: MirrorKeys.tosVersion)
            }
        } catch {
            AppLogger.data.error("Error loading consent record: \(error.localizedDescription)")
            // Fall back to the already-hydrated mirror value.
        }
        isLoaded = true
    }

    // MARK: - Record

    /// Writes (merge) the current legal acceptance to Firestore and updates the
    /// published value + mirror. `source` is "onboarding", "reacceptance", or
    /// "skip_gate". `dateOfBirth` is recorded only from the skip gate.
    func recordLegalAcceptance(source: String, dateOfBirth: Date? = nil) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        var data: [String: Any] = [
            "tosVersion": LegalContent.tosVersion,
            "privacyPolicyVersion": LegalContent.privacyPolicyVersion,
            "acceptedAt": FieldValue.serverTimestamp(),
            "source": source,
            "appVersion": appVersion
        ]
        if let dateOfBirth {
            data["dateOfBirth"] = Timestamp(date: dateOfBirth)
        }

        db.collection("users").document(uid)
            .collection("consents").document("legal")
            .setData(data, merge: true)

        recordedTosVersion = LegalContent.tosVersion
        UserDefaults.standard.set(LegalContent.tosVersion, forKey: MirrorKeys.tosVersion)
    }

    // MARK: - Local mirror lifecycle

    /// Removes both mirror keys (sign-out and account deletion).
    static func clearLocalMirrors() {
        UserDefaults.standard.removeObject(forKey: MirrorKeys.tosVersion)
        UserDefaults.standard.removeObject(forKey: MirrorKeys.healthDataPolicyVersion)
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
