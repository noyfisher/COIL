import XCTest
@testable import PT_Helper

// MARK: - Two-Call Verify Pipeline Tests

final class InjuryAnalyzerVerifyPipelineTests: XCTestCase {

    private var mock: MockClaudeAPIService!
    private var profile: UserProfile!
    private var assessment: PainAssessment!

    // Reusable JSON responses for primary (5 conditions) and verification (3 conditions)
    private var primaryJSON: String!
    private var verifyJSON: String!

    override func setUp() {
        super.setUp()
        mock = MockClaudeAPIService()
        profile = TestFixtures.makeProfile()
        assessment = TestFixtures.makeAssessment()

        primaryJSON = TestFixtures.makeMultiConditionResponseJSON(conditions: [
            (name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee", confidence: 70, isRedFlag: false),
            (name: "Meniscus Tear", commonName: "Torn Cartilage", confidence: 55, isRedFlag: false),
            (name: "IT Band Syndrome", commonName: "IT Band Pain", confidence: 40, isRedFlag: false),
            (name: "Patellar Tendinitis", commonName: "Jumper's Knee", confidence: 30, isRedFlag: false),
            (name: "Baker's Cyst", commonName: "Knee Cyst", confidence: 20, isRedFlag: false),
        ], summary: "Primary analysis summary")

        verifyJSON = TestFixtures.makeMultiConditionResponseJSON(conditions: [
            (name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee", confidence: 65, isRedFlag: false),
            (name: "Meniscus Tear", commonName: "Torn Cartilage", confidence: 50, isRedFlag: false),
            (name: "Chondromalacia Patella", commonName: "Cartilage Softening", confidence: 35, isRedFlag: false),
        ], summary: "Verified analysis summary")
    }

    // MARK: - 1. Verification Message Construction

    func testBuildVerificationMessage_containsOriginalPatientData() {
        let userMessage = InjuryAnalyzer.buildUserMessage(assessments: [assessment], profile: profile)
        let verifyMsg = InjuryAnalyzer.buildVerificationMessage(
            originalUserMessage: userMessage,
            primaryResponseJSON: "{}"
        )

        XCTAssertTrue(verifyMsg.contains("ORIGINAL PATIENT DATA:"))
        XCTAssertTrue(verifyMsg.contains("PATIENT PROFILE:"))
        XCTAssertTrue(verifyMsg.contains("PAIN ASSESSMENTS:"))
    }

    func testBuildVerificationMessage_containsPrimaryAnalysisJSON() {
        let primaryResponse = "{\"conditions\": [], \"overallSummary\": \"test\", \"disclaimerText\": \"test\"}"
        let verifyMsg = InjuryAnalyzer.buildVerificationMessage(
            originalUserMessage: "test patient data",
            primaryResponseJSON: primaryResponse
        )

        XCTAssertTrue(verifyMsg.contains("PRIMARY ANALYSIS (from initial review):"))
        XCTAssertTrue(verifyMsg.contains(primaryResponse))
    }

    func testBuildVerificationMessage_containsReviewInstruction() {
        let verifyMsg = InjuryAnalyzer.buildVerificationMessage(
            originalUserMessage: "test",
            primaryResponseJSON: "{}"
        )

        XCTAssertTrue(verifyMsg.contains("Challenge any anchoring bias"))
        XCTAssertTrue(verifyMsg.contains("check for missed red flags"))
    }

    // MARK: - 2. Two-Call Flow Integration

    func testAnalyze_makesTwoCalls() async throws {
        mock.responsesQueue = [primaryJSON, verifyJSON]

        _ = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        XCTAssertEqual(mock.sendMessageCallCount, 2, "Should make exactly 2 API calls")
    }

    func testAnalyze_firstCallIsAnalysis_secondCallIsVerify() async throws {
        mock.responsesQueue = [primaryJSON, verifyJSON]

        _ = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        XCTAssertEqual(mock.allRequestTypes.count, 2)
        XCTAssertEqual(mock.allRequestTypes[0], .analysis, "First call should be .analysis")
        XCTAssertEqual(mock.allRequestTypes[1], .analysis_verify, "Second call should be .analysis_verify")
    }

    func testAnalyze_verificationMessageContainsPrimaryResponse() async throws {
        mock.responsesQueue = [primaryJSON, verifyJSON]

        _ = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        XCTAssertEqual(mock.allUserMessages.count, 2)
        let verificationMessage = mock.allUserMessages[1]
        // The verification message should contain the primary JSON response
        XCTAssertTrue(verificationMessage.contains("PRIMARY ANALYSIS"), "Verification message should contain primary analysis")
        XCTAssertTrue(verificationMessage.contains("Patellofemoral Pain Syndrome"), "Verification message should contain primary conditions")
    }

    // MARK: - 3. Synthesis Logic

    func testSynthesize_agreementBoostsConfidence() {
        // Primary has PFPS at 70%, verification has PFPS at 65%
        // Agreement → verification's 65% + 10 bonus = 75%
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee", confidence: 70),
        ])
        let verification = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee", confidence: 65),
        ])

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verification,
            assessments: [assessment], profile: profile
        )

        XCTAssertEqual(result.conditions.count, 1)
        XCTAssertEqual(result.conditions[0].confidence, 75, "Agreement should boost confidence by 10")
    }

    func testSynthesize_noAgreementKeepsOriginalConfidence() {
        // Primary has condition A, verification has condition B (different)
        // No agreement → condition B stays at its original confidence
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Meniscus Tear", commonName: "Torn Cartilage", confidence: 60),
        ])
        let verification = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Chondromalacia Patella", commonName: "Cartilage Softening", confidence: 45),
        ])

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verification,
            assessments: [assessment], profile: profile
        )

        XCTAssertEqual(result.conditions.count, 1)
        XCTAssertEqual(result.conditions[0].conditionName, "Chondromalacia Patella")
        XCTAssertEqual(result.conditions[0].confidence, 45, "Non-agreement condition should keep original confidence")
    }

    func testSynthesize_redFlagPreservedFromPrimary() {
        // Primary has a red flag condition, verification drops it
        // Safety: red flag should be re-added
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Cauda Equina Syndrome", commonName: "Spinal Emergency", confidence: 25, isRedFlag: true),
        ])
        let verification = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Meniscus Tear", commonName: "Torn Cartilage", confidence: 60),
        ])

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verification,
            assessments: [assessment], profile: profile
        )

        let redFlagConditions = result.conditions.filter { $0.isRedFlag }
        XCTAssertFalse(redFlagConditions.isEmpty, "Red flag from primary should be preserved even if verifier dropped it")
        XCTAssertTrue(result.conditions.contains(where: { $0.conditionName == "Cauda Equina Syndrome" }))
    }

    func testSynthesize_nonRedFlagDroppedByVerifierStaysDropped() {
        // Primary has condition Y (not red flag), verification doesn't have it
        // Condition Y should NOT be in final result
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Baker's Cyst", commonName: "Knee Cyst", confidence: 20, isRedFlag: false),
        ])
        let verification = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Meniscus Tear", commonName: "Torn Cartilage", confidence: 60),
        ])

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verification,
            assessments: [assessment], profile: profile
        )

        XCTAssertFalse(result.conditions.contains(where: { $0.conditionName == "Baker's Cyst" }),
                        "Non-red-flag condition dropped by verifier should stay dropped")
    }

    func testSynthesize_returnsTopThreeByConfidence() {
        // Verification has 3 conditions + primary has red flag → 4 total
        // Should return top 3 by confidence
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "DVT", commonName: "Blood Clot", confidence: 15, isRedFlag: true),
        ])
        let verification = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee", confidence: 70),
            TestFixtures.makeCondition(name: "Meniscus Tear", commonName: "Torn Cartilage", confidence: 55),
            TestFixtures.makeCondition(name: "IT Band Syndrome", commonName: "IT Band Pain", confidence: 40),
        ])

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verification,
            assessments: [assessment], profile: profile
        )

        XCTAssertEqual(result.conditions.count, 3, "Should return at most 3 conditions")
    }

    func testSynthesize_usesVerificationSummary() {
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "PFPS", commonName: "Runner's Knee", confidence: 70),
        ])
        var verifyResult = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "PFPS", commonName: "Runner's Knee", confidence: 65),
        ])
        // We need to create a result with a specific summary
        verifyResult = AnalysisResult(
            id: verifyResult.id, assessments: verifyResult.assessments,
            conditions: verifyResult.conditions,
            overallSummary: "Verified summary from the challenger",
            disclaimerText: verifyResult.disclaimerText,
            generatedDate: verifyResult.generatedDate,
            userProfileSnapshot: verifyResult.userProfileSnapshot
        )

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verifyResult,
            assessments: [assessment], profile: profile
        )

        XCTAssertEqual(result.overallSummary, "Verified summary from the challenger",
                        "Should use verification's summary, not primary's")
    }

    func testSynthesize_agreementBonusCappedAt100() {
        // Verification confidence at 95%, agreement bonus should cap at 100, not 105
        let primary = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "PFPS", commonName: "Runner's Knee", confidence: 80),
        ])
        let verification = TestFixtures.makeAnalysisResult(conditions: [
            TestFixtures.makeCondition(name: "PFPS", commonName: "Runner's Knee", confidence: 95),
        ])

        let result = InjuryAnalyzer.synthesize(
            primary: primary, verification: verification,
            assessments: [assessment], profile: profile
        )

        XCTAssertEqual(result.conditions[0].confidence, 100, "Agreement bonus should cap at 100")
    }

    // MARK: - 4. Graceful Degradation

    func testAnalyze_verificationFails_fallsBackToPrimary() async throws {
        // Call 1 succeeds with primary JSON
        // Call 2 throws an error
        let singleConditionJSON = TestFixtures.makeAnalysisResponseJSON(
            conditionName: "Patellofemoral Pain Syndrome", confidence: 70
        )
        mock.responsesQueue = [singleConditionJSON]
        // After queue is empty, errorsQueue is checked — but we need the second call to fail.
        // Use errorsQueue: first call nil (no error), second call throws
        mock.responsesQueue = []
        mock.errorsQueue = [nil, ClaudeAPIError.networkError(NSError(domain: "test", code: -1))]
        // First call uses no error and responseToReturn:
        mock.responseToReturn = singleConditionJSON

        // This should NOT throw — graceful degradation
        let result = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        XCTAssertNotNil(result.result)
        XCTAssertFalse(result.result.conditions.isEmpty, "Should have conditions from primary analysis fallback")
    }

    func testAnalyze_verificationReturnsInvalidJSON_fallsBackToPrimary() async throws {
        let validPrimaryJSON = TestFixtures.makeAnalysisResponseJSON(
            conditionName: "Meniscus Tear", confidence: 60
        )
        mock.responsesQueue = [validPrimaryJSON, "this is not valid json at all"]

        let result = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        XCTAssertNotNil(result.result)
        // Should fall back to primary result since verification JSON is invalid
        XCTAssertTrue(result.result.conditions.contains(where: { $0.conditionName == "Meniscus Tear" }),
                       "Should fall back to primary analysis when verification returns invalid JSON")
    }

    func testAnalyze_primaryFails_throwsError() async {
        mock.errorToThrow = ClaudeAPIError.networkError(NSError(domain: "test", code: -1))

        do {
            _ = try await InjuryAnalyzer.analyze(
                assessments: [assessment],
                profile: profile,
                apiService: mock
            )
            XCTFail("Should throw when primary analysis fails")
        } catch {
            // Expected — primary failure should propagate
        }
    }

    // MARK: - 5. End-to-End Pipeline

    func testAnalyze_fullPipeline_producesValidatedResult() async throws {
        mock.responsesQueue = [primaryJSON, verifyJSON]

        let result = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        // Should have a valid result with conditions
        XCTAssertFalse(result.result.conditions.isEmpty)

        // Conditions should be capped at 3
        XCTAssertLessThanOrEqual(result.result.conditions.count, 3)

        // Confidence should be calibrated (capped at 85)
        for condition in result.result.conditions {
            XCTAssertLessThanOrEqual(condition.confidence, 85, "Confidence should be calibrated to max 85")
        }
    }

    func testAnalyze_fullPipeline_agreementConditionHasHigherConfidence() async throws {
        // PFPS appears in both primary (70) and verification (65)
        // After synthesis: 65 + 10 = 75, then capped at 85 by validation → 75
        // Chondromalacia only in verification at 35
        mock.responsesQueue = [primaryJSON, verifyJSON]

        let result = try await InjuryAnalyzer.analyze(
            assessments: [assessment],
            profile: profile,
            apiService: mock
        )

        let pfps = result.result.conditions.first(where: { $0.conditionName == "Patellofemoral Pain Syndrome" })
        let chondro = result.result.conditions.first(where: { $0.conditionName == "Chondromalacia Patella" })

        XCTAssertNotNil(pfps, "PFPS should be in final result")
        XCTAssertNotNil(chondro, "Chondromalacia should be in final result")

        if let pfps = pfps, let chondro = chondro {
            XCTAssertGreaterThan(pfps.confidence, chondro.confidence,
                                  "Agreement condition (PFPS) should have higher confidence than non-agreement (Chondromalacia)")
        }
    }
}
