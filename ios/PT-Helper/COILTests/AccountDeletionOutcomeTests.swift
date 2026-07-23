import XCTest
@testable import COIL

/// P1-01: the account-deletion client must treat ONLY a confirmed HTTP 200 as a
/// successful server-side deletion. A 401 (the server authenticates before it
/// deletes anything, so a 401 means nothing was deleted) must never be reported
/// as success — it triggers exactly one force-refreshed-token retry, then fails.
final class AccountDeletionOutcomeTests: XCTestCase {

    func testStatus200_isDeleted_regardlessOfRefreshState() {
        XCTAssertEqual(
            SettingsView.AccountDeletionOutcome.classify(status: 200, didRefreshToken: false),
            .deleted)
        XCTAssertEqual(
            SettingsView.AccountDeletionOutcome.classify(status: 200, didRefreshToken: true),
            .deleted)
    }

    func testFirst401_retriesWithFreshToken() {
        XCTAssertEqual(
            SettingsView.AccountDeletionOutcome.classify(status: 401, didRefreshToken: false),
            .retryWithFreshToken)
    }

    func testSecond401_afterRefresh_fails_neverDeleted() {
        // The core regression guard: a 401 must NOT map to `.deleted`.
        let outcome = SettingsView.AccountDeletionOutcome.classify(status: 401, didRefreshToken: true)
        XCTAssertEqual(outcome, .failed(status: 401))
        XCTAssertNotEqual(outcome, .deleted)
    }

    func testServerAndTransportErrors_fail_andNeverRetry() {
        XCTAssertEqual(
            SettingsView.AccountDeletionOutcome.classify(status: 500, didRefreshToken: false),
            .failed(status: 500))
        // status 0 == no HTTP response (transport failure) — also a failure, not success.
        XCTAssertEqual(
            SettingsView.AccountDeletionOutcome.classify(status: 0, didRefreshToken: false),
            .failed(status: 0))
        XCTAssertEqual(
            SettingsView.AccountDeletionOutcome.classify(status: 403, didRefreshToken: true),
            .failed(status: 403))
    }
}
