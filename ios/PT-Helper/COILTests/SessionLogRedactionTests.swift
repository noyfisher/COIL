import XCTest
@testable import COIL

/// P3-05: error descriptions can embed URLs, tokens, emails, or fragments of
/// user input before they enter an uploaded session log. redactedErrorSummary
/// strips the common offenders and bounds length.
final class SessionLogRedactionTests: XCTestCase {

    func testRedactsURLs() {
        let out = SessionLogger.redactedErrorSummary(
            "request failed: https://api.example.com/v1/users/abc?token=secret")
        XCTAssertFalse(out.contains("https://"))
        XCTAssertFalse(out.contains("token=secret"))
        XCTAssertTrue(out.contains("<redacted>"))
    }

    func testRedactsEmails() {
        let out = SessionLogger.redactedErrorSummary("account person@example.com not found")
        XCTAssertFalse(out.contains("@example.com"))
        XCTAssertTrue(out.contains("<redacted>"))
    }

    func testRedactsLongOpaqueTokens() {
        let token = String(repeating: "A1b2", count: 10) // 40 alphanumeric chars
        let out = SessionLogger.redactedErrorSummary("bearer \(token) rejected")
        XCTAssertFalse(out.contains(token))
        XCTAssertTrue(out.contains("<redacted>"))
    }

    func testTruncatesOverlongDescriptions() {
        // "ab " repeated — no single 20+ token, so nothing is redacted and the
        // length cap is what applies.
        let long = String(repeating: "ab ", count: 200) // 600 chars
        let out = SessionLogger.redactedErrorSummary(long, maxLength: 100)
        XCTAssertLessThanOrEqual(out.count, 101) // 100 + ellipsis
        XCTAssertTrue(out.hasSuffix("…"))
    }

    func testShortCleanMessagePassesThrough() {
        let msg = "The network connection was lost."
        XCTAssertEqual(SessionLogger.redactedErrorSummary(msg), msg)
    }
}
