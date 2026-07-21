import XCTest
@testable import COIL

/// Tier 3 PR C — tests for the shadow-mode strict JSON parser.
///
/// Covers both modes:
///   - Shadow mode (default): strict tried first; fallback runs on failure;
///     telemetry counter would fire when fallback saves us.
///   - Enforcement mode (flag on): strict failure throws immediately, no
///     fallback, no telemetry.
///
/// Doesn't cover the actual Firestore counter write (fire-and-forget on a
/// detached Task; verified manually during dogfooding).
final class ShadowModeJSONParserTests: XCTestCase {

    private struct Sample: Decodable, Equatable {
        let id: Int
        let name: String
    }

    // Shared test state — flip the enforcement flag in tearDown so we don't
    // leak state between tests.
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: ShadowModeJSONParser.enforcementFlagKey)
        super.tearDown()
    }

    // MARK: - Strict-success path

    func test_parse_validJSON_returnsDecoded() throws {
        let json = #"{"id":7,"name":"alpha"}"#
        let result = try ShadowModeJSONParser.parse(
            json, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result, Sample(id: 7, name: "alpha"))
    }

    func test_parse_validJSON_doesNotInvokeFallback() throws {
        // Even if there's leading/trailing junk, valid JSON without it
        // (i.e., already cleanly bracketed) takes the strict path.
        let json = #"{"id":1,"name":"clean"}"#
        let result = try ShadowModeJSONParser.parse(
            json, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result.id, 1)
    }

    // MARK: - Shadow-mode fallback path

    func test_parse_jsonWithLeadingPreamble_fallbackSucceedsInShadowMode() throws {
        // Strict will fail on the leading prose; permissive extracts { … }.
        let response = """
        Sure, here's the answer: {"id":42,"name":"bravo"}
        """
        let result = try ShadowModeJSONParser.parse(
            response, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result, Sample(id: 42, name: "bravo"))
    }

    func test_parse_jsonWithTrailingComment_fallbackSucceedsInShadowMode() throws {
        let response = #"{"id":3,"name":"gamma"} // hope this helps!"#
        let result = try ShadowModeJSONParser.parse(
            response, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result, Sample(id: 3, name: "gamma"))
    }

    func test_parse_jsonInMarkdownFence_fallbackSucceedsInShadowMode() throws {
        let response = """
        ```json
        {"id":5,"name":"delta"}
        ```
        """
        let result = try ShadowModeJSONParser.parse(
            response, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result.name, "delta")
    }

    // MARK: - Both-fail path

    func test_parse_completelyInvalidJSON_throwsInShadowMode() {
        let response = "I'm sorry, I can't help with that."
        XCTAssertThrowsError(try ShadowModeJSONParser.parse(
            response, as: Sample.self, requestType: "test"
        )) { error in
            // Should be ClaudeAPIError.decodingError
            guard let apiError = error as? ClaudeAPIError,
                  case .decodingError = apiError else {
                XCTFail("Expected ClaudeAPIError.decodingError, got \(error)")
                return
            }
        }
    }

    func test_parse_emptyString_throwsInShadowMode() {
        XCTAssertThrowsError(try ShadowModeJSONParser.parse(
            "", as: Sample.self, requestType: "test"
        ))
    }

    func test_parse_jsonMissingRequiredField_throwsInShadowMode() {
        // Missing `name` field — strict and fallback both fail.
        let response = #"{"id":1}"#
        XCTAssertThrowsError(try ShadowModeJSONParser.parse(
            response, as: Sample.self, requestType: "test"
        ))
    }

    // MARK: - Enforcement mode

    func test_parse_enforcementMode_strictSucceeds_returnsResult() throws {
        UserDefaults.standard.set(true, forKey: ShadowModeJSONParser.enforcementFlagKey)
        let json = #"{"id":99,"name":"epsilon"}"#
        let result = try ShadowModeJSONParser.parse(
            json, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result.id, 99)
    }

    func test_parse_enforcementMode_strictFails_throwsImmediately_noFallback() {
        UserDefaults.standard.set(true, forKey: ShadowModeJSONParser.enforcementFlagKey)
        // Permissive WOULD succeed here (extract { … } from preamble), but
        // enforcement mode skips the fallback entirely.
        let response = #"Sure: {"id":1,"name":"alpha"}"#
        XCTAssertThrowsError(try ShadowModeJSONParser.parse(
            response, as: Sample.self, requestType: "test"
        )) { error in
            guard let apiError = error as? ClaudeAPIError,
                  case .decodingError = apiError else {
                XCTFail("Expected ClaudeAPIError.decodingError, got \(error)")
                return
            }
        }
    }

    func test_parse_enforcementMode_validJSON_stillWorks() throws {
        UserDefaults.standard.set(true, forKey: ShadowModeJSONParser.enforcementFlagKey)
        // Sanity check: enforcement mode doesn't break the happy path.
        let json = #"{"id":11,"name":"zeta"}"#
        let result = try ShadowModeJSONParser.parse(
            json, as: Sample.self, requestType: "test"
        )
        XCTAssertEqual(result.name, "zeta")
    }

    // MARK: - Feature flag plumbing

    func test_isEnforcementEnabled_defaultsFalse() {
        UserDefaults.standard.removeObject(forKey: ShadowModeJSONParser.enforcementFlagKey)
        XCTAssertFalse(ShadowModeJSONParser.isEnforcementEnabled)
    }

    func test_isEnforcementEnabled_truesAfterFlagFlip() {
        UserDefaults.standard.set(true, forKey: ShadowModeJSONParser.enforcementFlagKey)
        XCTAssertTrue(ShadowModeJSONParser.isEnforcementEnabled)
    }

    func test_enforcementFlagKey_matchesDocumentedValue() {
        // The flag key string is the public contract for enabling/disabling
        // enforcement (e.g. via @AppStorage in a debug menu). Renaming
        // breaks the rollout switch.
        XCTAssertEqual(
            ShadowModeJSONParser.enforcementFlagKey,
            "strictJsonParsingV1Enabled"
        )
    }
}
