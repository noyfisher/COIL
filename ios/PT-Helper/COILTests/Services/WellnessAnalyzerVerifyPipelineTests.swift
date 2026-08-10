import XCTest
@testable import COIL

/// Covers `WellnessAnalyzer.analyze` — the two-call primary+verify pipeline, its
/// graceful degradation, and the validation that runs on whichever result it lands on.
///
/// `WellnessAnalyzerBuildMessageTests` covers prompt construction (what goes *out*).
/// This covers what comes *back*: call sequencing, fallback, parsing failures, and the
/// red-flag scan on the server response — none of which had coverage. The injury-side
/// equivalent is `InjuryAnalyzerVerifyPipelineTests`.
final class WellnessAnalyzerVerifyPipelineTests: XCTestCase {

    private var mockAPI: MockClaudeAPIService!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
    }

    private func assessment(notes: String? = nil) -> WellnessAssessment {
        TestFixtures.makeWellnessAssessment(additionalNotes: notes)
    }

    // MARK: - Call sequencing

    func testAnalyze_makesTwoCalls() async throws {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()

        _ = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertEqual(mockAPI.sendMessageCallCount, 2, "Primary + verification")
    }

    /// A copy-paste of the injury pipeline's `.analysis` / `.analysis_verify` types would
    /// route wellness traffic to the wrong server prompt while still returning parseable
    /// JSON, so pin the exact request types and their order.
    func testAnalyze_usesWellnessRequestTypes_inOrder() async throws {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()

        _ = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertEqual(mockAPI.allRequestTypes, [.wellness_analysis, .wellness_verify])
    }

    /// The verification prompt must carry the primary response forward, otherwise the
    /// second call is reviewing nothing.
    func testAnalyze_verificationMessage_includesPrimaryResponse() async throws {
        let primary = TestFixtures.makeWellnessAnalysisResponseJSON(title: "Primary Plan")
        mockAPI.responsesQueue = [primary, TestFixtures.makeWellnessAnalysisResponseJSON(title: "Verified Plan")]

        _ = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        let verificationMessage = try XCTUnwrap(mockAPI.allUserMessages.last)
        XCTAssertTrue(verificationMessage.contains("Primary Plan"),
                      "Verification call should include the primary response for review")
    }

    // MARK: - Verification outcome

    /// Unlike `InjuryAnalyzer`, which merges primary and verify via `synthesize` and
    /// deliberately preserves red-flag-bearing content from the primary call, the wellness
    /// pipeline replaces the primary result with the verify result wholesale. Pinned
    /// because it is a real behavioural difference, not an oversight to be "fixed" silently:
    /// anything the verify call drops is gone.
    func testAnalyze_verificationSucceeds_usesVerifyResultWholesale() async throws {
        mockAPI.responsesQueue = [
            TestFixtures.makeWellnessAnalysisResponseJSON(title: "Primary Only"),
            TestFixtures.makeWellnessAnalysisResponseJSON(title: "Verified Replacement"),
        ]

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertEqual(analysis.result.recommendations.map(\.title), ["Verified Replacement"],
                       "Verify result replaces primary entirely — no merge")
    }

    func testAnalyze_verificationThrows_fallsBackToPrimary() async throws {
        mockAPI.responsesQueue = [TestFixtures.makeWellnessAnalysisResponseJSON(title: "Primary Only")]
        mockAPI.errorsQueue = [nil, ClaudeAPIError.networkError(URLError(.timedOut))]

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertEqual(analysis.result.recommendations.map(\.title), ["Primary Only"],
                       "A failed verification must degrade to the primary result, not throw")
    }

    /// Distinct from a thrown network error: the call succeeds but returns junk, so the
    /// failure surfaces from the parser inside the `do` block instead.
    func testAnalyze_verificationReturnsMalformedJSON_fallsBackToPrimary() async throws {
        mockAPI.responsesQueue = [
            TestFixtures.makeWellnessAnalysisResponseJSON(title: "Primary Only"),
            "{ this is not valid json",
        ]

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertEqual(analysis.result.recommendations.map(\.title), ["Primary Only"])
    }

    // MARK: - Primary failure propagates

    func testAnalyze_primaryThrows_propagatesError() async {
        mockAPI.errorToThrow = ClaudeAPIError.networkError(URLError(.notConnectedToInternet))

        do {
            _ = try await WellnessAnalyzer.analyze(
                assessments: [assessment()],
                profile: TestFixtures.makeProfile(),
                apiService: mockAPI
            )
            XCTFail("A failed primary call has nothing to fall back to and must throw")
        } catch {
            XCTAssertEqual(mockAPI.sendMessageCallCount, 1, "Should not attempt verification after a failed primary")
        }
    }

    func testAnalyze_primaryReturnsMalformedJSON_throws() async {
        mockAPI.responseToReturn = "not json at all"

        do {
            _ = try await WellnessAnalyzer.analyze(
                assessments: [assessment()],
                profile: TestFixtures.makeProfile(),
                apiService: mockAPI
            )
            XCTFail("An unparseable primary response must throw")
        } catch {
            // expected
        }
    }

    // MARK: - Validation on the final result

    /// `WellnessAnalysisViewModelRoutingTests` covers the *client-side* pre-screen that
    /// runs before any API call. This covers the scan that runs on the way back out, which
    /// is what catches a red flag the user only disclosed in free text.
    func testAnalyze_regionAgnosticRedFlagInFreeText_surfacesEmergencyWarning() async throws {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment(notes: "Lately I get sudden weakness and numbness down one side of my body")],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertFalse(analysis.warnings.isEmpty, "A red flag in free text must surface a warning")
        XCTAssertEqual(analysis.worstSeverity, .emergency,
                       "Stroke-pattern red flags must reach emergency severity so the caller can route to EmergencyRedirectView")
    }

    /// DOCUMENTS A KNOWN GAP — this asserts current behaviour, not desired behaviour.
    ///
    /// `MedicalRedFlagDetector.check(symptomStrings:)` iterates
    /// `symptomPatterns where pattern.region == nil`, so every region-scoped pattern is
    /// skipped on the free-text path. Three of the six `.emergency` patterns are
    /// region-scoped — cardiac (`chest`) and both cauda equina variants — which makes them
    /// unreachable for wellness users, who never select a body region. The same function
    /// backs the pre-screen in `WellnessAnalysisViewModel` (line ~105), so the gap exists
    /// on both the way in and the way out.
    ///
    /// The injury flow is unaffected: it calls `check(assessments:)`, which has region
    /// context and evaluates these patterns normally.
    ///
    /// Fixing this means deciding whether an unknown region should match region-scoped
    /// patterns anyway — a false emergency referral is far cheaper than a missed cardiac
    /// event, but it is a clinical call, not one to make inside a testing pass. When it is
    /// fixed, this test will fail and should be inverted.
    func testAnalyze_regionScopedCardiacRedFlag_isNotDetectedInWellnessFlow_knownGap() async throws {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment(notes: "I get crushing chest pain and shortness of breath climbing stairs")],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertNotEqual(analysis.worstSeverity, .emergency, """
            Cardiac free text now reaches emergency severity — the region-scoped pattern gap \
            has been fixed. Invert this test: it exists only to make the gap visible.
            """)
    }

    func testAnalyze_benignAssessment_producesNoEmergencyWarning() async throws {
        mockAPI.responseToReturn = TestFixtures.makeWellnessAnalysisResponseJSON()

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment(notes: "I sit at a desk most of the day and want better posture")],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertNotEqual(analysis.worstSeverity, .emergency)
    }

    /// The content-bounds fix is reachable through the full pipeline, not just by calling
    /// the validator directly.
    func testAnalyze_appliesContentBounds_toTheReturnedResult() async throws {
        mockAPI.responseToReturn = Self.responseJSON(recommendationCount: 8)

        let analysis = try await WellnessAnalyzer.analyze(
            assessments: [assessment()],
            profile: TestFixtures.makeProfile(),
            apiService: mockAPI
        )

        XCTAssertEqual(analysis.result.recommendations.count, 5,
                       "The 1–5 bound must be enforced on what actually reaches the caller")
    }

    // MARK: - Helpers

    private static func responseJSON(recommendationCount: Int) -> String {
        let recs = (0..<recommendationCount).map { i in
            """
            {
                "goalCategory": "improve_posture",
                "title": "Recommendation \(i)",
                "currentStateAssessment": "Assessment \(i)",
                "rootCauses": ["Cause"],
                "expectedTimeline": "4 weeks",
                "keyInsight": "Insight \(i)",
                "priorityLevel": "high",
                "relatedGoals": []
            }
            """
        }.joined(separator: ",\n")

        return """
        {
            "recommendations": [\(recs)],
            "overallSummary": "Summary.",
            "disclaimerText": "Educational guidance, not medical advice."
        }
        """
    }
}
