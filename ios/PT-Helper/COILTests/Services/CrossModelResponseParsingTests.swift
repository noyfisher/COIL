import XCTest
@testable import COIL

/// Covers `CrossModelVerificationService.parseCrossModelResponse` — the mapping from the
/// verification service's JSON onto `CrossModelResult`, which decides whether an exercise
/// the knowledge graph didn't recognise gets flagged as unsafe (tier 2 of the safety
/// pipeline).
///
/// `CrossModelVerificationRetryTests` covers only the pure `withRetry` / `isRetryable`
/// helpers; its doc comment claims it exercises `verify()` end to end, which is stale —
/// `sendBatch` requires `Auth.auth().currentUser` and throws `.authenticationRequired`
/// in a unit-test process before reaching the injectable `HTTPSession`.
///
/// KNOWN LIMITATION, stated rather than faked: the auth-gated request construction,
/// header assembly, and status-code-to-error mapping inside `sendBatch` remain untested.
/// Closing that needs an injectable auth-token provider (the same shape as the existing
/// `HTTPSession` seam) or a Firebase Auth emulator.
final class CrossModelResponseParsingTests: XCTestCase {

    private let service = CrossModelVerificationService.shared

    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    private let onePair = [(name: "Wall Sits", condition: "patellofemoral pain syndrome")]

    // MARK: - Single-exercise ("safe") shape

    func testSingleExerciseResponse_mapsAllFields() throws {
        let json = """
        {"safe": true, "confidence": 0.92, "reasoning": "Low joint load", "concerns": []}
        """

        let results = try service.parseCrossModelResponse(data(json), exercises: onePair)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].exerciseName, "Wall Sits")
        XCTAssertEqual(results[0].conditionName, "patellofemoral pain syndrome")
        XCTAssertTrue(results[0].isSafe)
        XCTAssertEqual(results[0].confidence, 0.92, accuracy: 0.001)
        XCTAssertEqual(results[0].reasoning, "Low joint load")
        XCTAssertTrue(results[0].concerns.isEmpty)
    }

    func testSingleExerciseResponse_unsafeCarriesConcerns() throws {
        let json = """
        {"safe": false, "confidence": 0.8, "reasoning": "High patellar load", "concerns": ["Deep knee flexion"]}
        """

        let results = try service.parseCrossModelResponse(data(json), exercises: onePair)

        XCTAssertFalse(results[0].isSafe)
        XCTAssertEqual(results[0].concerns, ["Deep knee flexion"])
    }

    func testSingleExerciseResponse_missingOptionalFields_useDefaults() throws {
        let results = try service.parseCrossModelResponse(data(#"{"safe": true}"#), exercises: onePair)

        XCTAssertEqual(results[0].confidence, 0.5, accuracy: 0.001, "Absent confidence defaults to 0.5")
        XCTAssertEqual(results[0].reasoning, "")
        XCTAssertTrue(results[0].concerns.isEmpty)
    }

    /// The single-exercise shape reads `exercises.first` for its labels; with no pairs
    /// there is nothing to attribute the verdict to.
    func testSingleExerciseResponse_withNoExercises_throws() {
        XCTAssertThrowsError(try service.parseCrossModelResponse(data(#"{"safe": true}"#), exercises: []))
    }

    // MARK: - Batched ("results") shape

    func testBatchedResponse_zipsResultsToExercisesInOrder() throws {
        let json = """
        {"results": [
            {"safe": true,  "confidence": 0.9, "reasoning": "Fine",  "concerns": []},
            {"safe": false, "confidence": 0.4, "reasoning": "Risky", "concerns": ["Impact"]}
        ]}
        """
        let pairs = [
            (name: "Wall Sits", condition: "patellofemoral pain syndrome"),
            (name: "Jump Squat", condition: "osteoporosis"),
        ]

        let results = try service.parseCrossModelResponse(data(json), exercises: pairs)

        XCTAssertEqual(results.map(\.exerciseName), ["Wall Sits", "Jump Squat"])
        XCTAssertEqual(results.map(\.conditionName), ["patellofemoral pain syndrome", "osteoporosis"])
        XCTAssertEqual(results.map(\.isSafe), [true, false],
                       "Verdicts must stay aligned with the exercise they were issued for")
        XCTAssertEqual(results[1].concerns, ["Impact"])
    }

    /// Defaulting a missing `safe` to `false` is the safe direction — an ambiguous verdict
    /// should flag rather than silently pass.
    func testBatchedResponse_missingSafeFlag_defaultsToUnsafe() throws {
        let json = #"{"results": [{"confidence": 0.7, "reasoning": "Unclear"}]}"#

        let results = try service.parseCrossModelResponse(data(json), exercises: onePair)

        XCTAssertFalse(results[0].isSafe, "A verdict without an explicit `safe` must not be treated as safe")
    }

    func testBatchedResponse_usesTestFixtureShape() throws {
        let results = try service.parseCrossModelResponse(
            data(TestFixtures.makeCrossModelResponseJSON(safe: false, confidence: 0.31)),
            exercises: onePair
        )

        XCTAssertFalse(results[0].isSafe)
        XCTAssertEqual(results[0].confidence, 0.31, accuracy: 0.001)
        XCTAssertEqual(results[0].concerns, ["Test concern"])
    }

    // MARK: - Malformed input

    /// `CrossModelError` carries an associated `Error` on one case and so isn't
    /// `Equatable`; match the case instead of comparing values.
    private func assertDecodingError(_ error: Error, file: StaticString = #file, line: UInt = #line) {
        guard let crossModelError = error as? CrossModelError,
              case .decodingError = crossModelError else {
            return XCTFail("Expected CrossModelError.decodingError, got \(error)", file: file, line: line)
        }
    }

    /// Syntactically invalid JSON surfaces `JSONSerialization`'s own `NSCocoaErrorDomain`
    /// error rather than `CrossModelError.decodingError`: the `try` on
    /// `JSONSerialization.jsonObject` throws before the `guard` that maps to the domain
    /// error, so only *well-formed but wrong-shaped* payloads reach that conversion.
    ///
    /// Consequence worth knowing: callers matching on `CrossModelError` won't recognise
    /// this case, so the user-facing "Failed to parse verification response." string never
    /// applies to a truncated or corrupt body. Asserting current behaviour here rather
    /// than changing production error handling inside a testing pass.
    func testMalformedJSON_throwsRawSerializationError_notCrossModelError() {
        XCTAssertThrowsError(try service.parseCrossModelResponse(data("{ not json"), exercises: onePair)) { error in
            XCTAssertNil(error as? CrossModelError,
                         "If this now maps to CrossModelError, the parser gained a catch — update this test")
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
        }
    }

    func testResponseWithNeitherSafeNorResults_throwsDecodingError() {
        XCTAssertThrowsError(
            try service.parseCrossModelResponse(data(#"{"unexpected": "shape"}"#), exercises: onePair)
        ) { error in
            assertDecodingError(error)
        }
    }

    /// A JSON array at the top level is valid JSON but not the expected object shape.
    func testTopLevelArray_throwsDecodingError() {
        XCTAssertThrowsError(try service.parseCrossModelResponse(data("[]"), exercises: onePair))
    }
}
