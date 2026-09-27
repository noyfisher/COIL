import XCTest
@testable import COIL

/// P1-03: a session log is bound to the account that created it. Only that
/// account may upload it; on an account switch (A signs out, B signs in on a
/// shared device) A's log must be quarantined, never uploaded into B's path.
final class SessionLogUploadDecisionTests: XCTestCase {

    func testOwnerMatchesCurrentUser_uploadsUnderOwner() {
        XCTAssertEqual(
            SessionLogger.uploadDecision(logOwner: "userA", currentUser: "userA"),
            .upload(owner: "userA"))
    }

    func testForeignOwner_isQuarantined_neverUploaded() {
        // The core leak guard: A's log while B is signed in must NOT upload.
        let decision = SessionLogger.uploadDecision(logOwner: "userA", currentUser: "userB")
        XCTAssertEqual(decision, .quarantineForeignOwner)
        XCTAssertNotEqual(decision, .upload(owner: "userA"))
        XCTAssertNotEqual(decision, .upload(owner: "userB"))
    }

    func testNoCurrentUser_isSkipped_notUploaded() {
        XCTAssertEqual(
            SessionLogger.uploadDecision(logOwner: "userA", currentUser: nil),
            .skipNoUser)
    }

    func testAnonymousOwner_isQuarantined_evenWithSignedInUser() {
        // A pre-auth "anonymous" trail must not be attributed to a real account.
        XCTAssertEqual(
            SessionLogger.uploadDecision(logOwner: "anonymous", currentUser: "userA"),
            .quarantineForeignOwner)
    }

    func testAnonymousOwner_noUser_isSkipped() {
        XCTAssertEqual(
            SessionLogger.uploadDecision(logOwner: "anonymous", currentUser: nil),
            .skipNoUser)
    }
}
