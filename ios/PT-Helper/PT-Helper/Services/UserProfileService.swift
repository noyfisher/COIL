import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Shared singleton that loads and caches the user profile once per session.
/// Eliminates duplicate Firestore reads from RootView, HomeTab, BodyMapViewModel, etc.
@MainActor
class UserProfileService: ObservableObject {
    static let shared = UserProfileService()

    @Published var profile: UserProfile?
    @Published var isLoaded = false
    @Published var loadError: String?

    /// Quick accessor for the user's first name
    var firstName: String {
        profile?.firstName ?? profile?.name ?? ""
    }

    /// Whether the profile document exists in Firestore (i.e., onboarding is complete)
    var profileCompleted: Bool {
        profile != nil
    }

    private let db = Firestore.firestore()

    private init() {}

    /// Load the profile from Firestore. Calls completion when done.
    /// If already loaded, returns cached data immediately.
    func loadIfNeeded() async {
        guard !isLoaded else { return }
        await load()
    }

    /// Force-reload the profile from Firestore (e.g., after editing profile).
    func reload() async {
        await load()
    }

    /// Check if the profile document exists (lightweight check for routing).
    func checkProfileExists() async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }

        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("profile").document("health").getDocument()
            if snapshot.exists, let data = snapshot.data() {
                self.profile = UserProfile.from(firestoreData: data)
                self.isLoaded = true
                return true
            } else {
                self.isLoaded = true
                return false
            }
        } catch {
            AppLogger.data.error("Error checking profile: \(error.localizedDescription)")
            self.loadError = "We couldn't load your profile. Please check your internet connection and try again."
            self.isLoaded = true
            return false
        }
    }

    /// Clear cached profile (e.g., on sign-out).
    func clear() {
        profile = nil
        isLoaded = false
        loadError = nil
    }

    // MARK: - Private

    private func load() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoaded = true
            return
        }

        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("profile").document("health").getDocument()
            if let data = snapshot.data() {
                self.profile = UserProfile.from(firestoreData: data)
            }
            self.loadError = nil
            self.isLoaded = true
        } catch {
            AppLogger.data.error("Error loading profile: \(error.localizedDescription)")
            self.loadError = error.localizedDescription
            self.isLoaded = true
        }
    }
}
