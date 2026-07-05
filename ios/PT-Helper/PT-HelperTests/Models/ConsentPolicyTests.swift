import XCTest
@testable import PT_Helper

final class ConsentPolicyTests: XCTestCase {

    func testNeedsLegalReacceptance_NilRecord_True() {
        XCTAssertTrue(
            ConsentPolicy.needsLegalReacceptance(recordedVersion: nil,
                                                 currentVersion: "2026.07")
        )
    }

    func testNeedsLegalReacceptance_OlderVersion_True() {
        XCTAssertTrue(
            ConsentPolicy.needsLegalReacceptance(recordedVersion: "2026.01",
                                                 currentVersion: "2026.07")
        )
    }

    func testNeedsLegalReacceptance_CurrentVersion_False() {
        XCTAssertFalse(
            ConsentPolicy.needsLegalReacceptance(recordedVersion: "2026.07",
                                                 currentVersion: "2026.07")
        )
    }
}
