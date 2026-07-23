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

    // MARK: - Central metadata scrub (P1-05): applied in log() so no call site bypasses it

    func testSanitizeMetadata_redactsHealthNameKeys() {
        // These are the exact keys that ExerciseSwap / FormAnalysis / Recovery
        // Insights call sites were passing raw into uploaded telemetry.
        let input = [
            "exercise": "Barbell Back Squat",
            "newExercise": "Goblet Squat",
            "originalExercise": "Barbell Back Squat",
            "droppedNames": "Deadlift, Lunge",
            "headline": "Your lower-back pain is trending down this week",
            "painTrend": "improving",
        ]
        let out = SessionLogger.sanitizeMetadata(input)!
        for key in input.keys {
            XCTAssertEqual(out[key], "<redacted>", "\(key) should be redacted")
        }
        XCTAssertFalse(out.values.contains { $0.contains("Squat") || $0.contains("pain") })
    }

    func testSanitizeMetadata_scrubsRawErrorValuesUnderAnyKey() {
        // A raw error.localizedDescription passed under a non-sensitive key must
        // still be stripped of URLs/tokens — the P3-05 raw-error leak.
        let out = SessionLogger.sanitizeMetadata([
            "error": "upload failed: https://api.example.com/v1?token=abcdef1234567890abcdef"
        ])!
        XCTAssertFalse(out["error"]!.contains("https://"))
        XCTAssertFalse(out["error"]!.contains("token=abcdef1234567890abcdef"))
        XCTAssertTrue(out["error"]!.contains("<redacted>"))
    }

    func testSanitizeMetadata_passesCleanNonSensitiveValues() {
        let out = SessionLogger.sanitizeMetadata([
            "screen": "GuidedWorkout",
            "count": "5",
        ])!
        XCTAssertEqual(out["screen"], "GuidedWorkout")
        XCTAssertEqual(out["count"], "5")
    }

    func testSanitizeMetadata_nilAndEmptyPassThrough() {
        XCTAssertNil(SessionLogger.sanitizeMetadata(nil))
        XCTAssertEqual(SessionLogger.sanitizeMetadata([:]), [:])
    }
}
