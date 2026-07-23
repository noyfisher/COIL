import Foundation

/// Central coordinator for account-scoped state across authentication
/// transitions. Services that hold per-account state route their teardown
/// through here so a single sign-out path resets all of it — preventing one
/// account's data from bleeding into the next account on a shared device
/// (P1-03).
///
/// Introduced in PR-2 (SessionLogger). PR-9a extends it to reset the streak
/// singleton, workout checkpoint, and outcome/warning caches. Note: FCM-token
/// removal needs Firestore auth, so it happens at the sign-out ACTION while the
/// user is still signed in (see `SettingsView`), NOT here — this coordinator
/// runs from the auth listener, which fires only after `Auth.signOut()`.
@MainActor
enum AccountSessionContext {

    /// Runs all account-scoped LOCAL teardown when the user signs out. Invoked
    /// from the auth-state listener's sign-out branch (`RootView`), which fires
    /// AFTER `Auth.signOut()` — so everything here is local-only. Idempotent.
    static func signOutCleanup() {
        SessionLogger.shared.finalizeForSignOut()
        // Reset account-scoped singletons + local caches so the next account on a
        // shared device starts clean rather than briefly inheriting the previous
        // user's streak, workout checkpoint, or outcome/warning state (P2-04).
        StreakService.shared.reset()
        GuidedWorkoutViewModel.clearAllLocalWorkoutState()
        OutcomeRecorder.shared.clearLocalCache()
        SeriousWarningAcknowledgements.clearAll()
    }
}
