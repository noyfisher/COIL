import Foundation

/// Central coordinator for account-scoped state across authentication
/// transitions. Services that hold per-account state route their teardown
/// through here so a single sign-out path resets all of it — preventing one
/// account's data from bleeding into the next account on a shared device
/// (P1-03).
///
/// Introduced in PR-2 wiring in `SessionLogger`. Later work (PR-9a) extends
/// `signOutCleanup()` to also capture the outgoing UID for FCM-token removal
/// and to reset streak/outcome caches and workout checkpoints, so that all of
/// the shared-device isolation lives behind this one entry point.
@MainActor
enum AccountSessionContext {

    /// Runs all account-scoped teardown when the user signs out. Invoked from
    /// the auth-state listener's sign-out branch (`RootView`). Idempotent —
    /// safe to call more than once for the same transition.
    static func signOutCleanup() {
        SessionLogger.shared.finalizeForSignOut()
    }
}
