import XCTest
@testable import PT_Helper

@MainActor
final class RecoveryInsightsViewModelTests: XCTestCase {

    private var mockAPI: MockClaudeAPIService!
    private var vm: RecoveryInsightsViewModel!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
        vm = RecoveryInsightsViewModel(apiService: mockAPI)
    }

    // MARK: - Helpers

    private func makeSessions(count: Int, daysAgoStart: Int = 0) -> [WorkoutSession] {
        (0..<count).map { i in
            TestFixtures.makeSession(
                daysAgo: daysAgoStart + i * 2,
                painLevel: Double(5 - min(i, 3)),
                exercisesPerformed: ["Wall Sits", "Quad Sets"]
            )
        }
    }

    private func makePlans() -> [RehabPlan] {
        [TestFixtures.makePlan(
            name: "Knee Rehab",
            conditions: ["knee pain"],
            exercises: [
                TestFixtures.makeExercise(name: "Wall Sits"),
                TestFixtures.makeExercise(name: "Quad Sets")
            ]
        )]
    }

    // MARK: - Data Eligibility

    func testHasEnoughData_belowMinimum_returnsFalse() {
        let sessions = makeSessions(count: 2)
        XCTAssertFalse(vm.hasEnoughData(sessions: sessions))
    }

    func testHasEnoughData_atMinimum_returnsTrue() {
        let sessions = makeSessions(count: 3)
        XCTAssertTrue(vm.hasEnoughData(sessions: sessions))
    }

    func testHasEnoughData_olderThanLookback_excluded() {
        // All sessions are 20+ days ago (beyond 14-day lookback)
        let sessions = makeSessions(count: 5, daysAgoStart: 20)
        XCTAssertFalse(vm.hasEnoughData(sessions: sessions))
    }

    func testRecentSessions_filtersToLookbackWindow() {
        var sessions = makeSessions(count: 3) // within range
        sessions += makeSessions(count: 2, daysAgoStart: 20) // outside range
        let recent = vm.recentSessions(from: sessions)
        XCTAssertEqual(recent.count, 3)
    }

    // MARK: - Generate Insights

    func testGenerateInsights_success_parsesResponse() async {
        mockAPI.responseToReturn = TestFixtures.makeRecoveryInsightsResponseJSON()
        let sessions = makeSessions(count: 4)

        await vm.generateInsights(sessions: sessions, plans: makePlans(), profile: TestFixtures.makeProfile())

        XCTAssertNotNil(vm.insight)
        XCTAssertEqual(vm.insight?.headline, "Great Progress This Week")
        XCTAssertEqual(vm.insight?.painAnalysis.trendDirection, "improving")
        XCTAssertEqual(vm.insight?.adherenceAnalysis.score, 85)
        XCTAssertEqual(vm.insight?.keyWins.count, 2)
        XCTAssertEqual(vm.insight?.focusAreas.count, 1)
        XCTAssertEqual(vm.insight?.recommendations.count, 2)
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.error)
    }

    func testGenerateInsights_apiError_setsError() async {
        mockAPI.errorToThrow = ClaudeAPIError.networkError(
            NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        )
        let sessions = makeSessions(count: 4)

        await vm.generateInsights(sessions: sessions, plans: makePlans(), profile: nil)

        XCTAssertNil(vm.insight)
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    func testGenerateInsights_invalidJSON_setsError() async {
        mockAPI.responseToReturn = "This is not valid JSON at all"
        let sessions = makeSessions(count: 4)

        await vm.generateInsights(sessions: sessions, plans: makePlans(), profile: nil)

        XCTAssertNil(vm.insight)
        XCTAssertNotNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    func testGenerateInsights_insufficientData_setsError() async {
        let sessions = makeSessions(count: 1)

        await vm.generateInsights(sessions: sessions, plans: makePlans(), profile: nil)

        XCTAssertNil(vm.insight)
        XCTAssertNotNil(vm.error)
        XCTAssertTrue(vm.error!.contains("at least"))
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0, "Should not call API with insufficient data")
    }

    func testGenerateInsights_correctRequestType() async {
        // Force agent path to fail so we hit the sendMessage fallback
        mockAPI.agentInsightsErrorToThrow = ClaudeAPIError.networkError(
            NSError(domain: "test", code: -1))
        mockAPI.responseToReturn = TestFixtures.makeRecoveryInsightsResponseJSON()
        let sessions = makeSessions(count: 4)

        await vm.generateInsights(sessions: sessions, plans: makePlans(), profile: nil)

        XCTAssertEqual(mockAPI.lastRequestType, .recovery_insights)
    }

    func testGenerateInsights_agentSuccess_doesNotCallSendMessage() async {
        mockAPI.agentInsightsResponseToReturn = TestFixtures.makeRecoveryInsightsResponseJSON()
        let sessions = makeSessions(count: 4)

        await vm.generateInsights(sessions: sessions, plans: makePlans(), profile: nil)

        XCTAssertEqual(mockAPI.requestAgentInsightsCallCount, 1)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0, "Should not fall back when agent succeeds")
        XCTAssertNotNil(vm.insight)
    }

    // MARK: - Caching

    func testGenerateInsights_cached_doesNotCallAPI() async {
        // Force agent path to fail so we hit the sendMessage fallback
        mockAPI.agentInsightsErrorToThrow = ClaudeAPIError.networkError(
            NSError(domain: "test", code: -1))
        mockAPI.responseToReturn = TestFixtures.makeRecoveryInsightsResponseJSON()
        let sessions = makeSessions(count: 4)
        let plans = makePlans()

        // First call
        await vm.generateInsights(sessions: sessions, plans: plans, profile: nil)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 1)

        // Second call (should be cached)
        await vm.generateInsights(sessions: sessions, plans: plans, profile: nil)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 1, "Should not re-call API within cache window")
    }

    func testGenerateInsights_forceRegenerate_bypassesCache() async {
        // Force agent path to fail so we hit the sendMessage fallback
        mockAPI.agentInsightsErrorToThrow = ClaudeAPIError.networkError(
            NSError(domain: "test", code: -1))
        mockAPI.responseToReturn = TestFixtures.makeRecoveryInsightsResponseJSON()
        let sessions = makeSessions(count: 4)
        let plans = makePlans()

        // First call
        await vm.generateInsights(sessions: sessions, plans: plans, profile: nil)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 1)

        // Force regenerate
        await vm.generateInsights(sessions: sessions, plans: plans, profile: nil, forceRegenerate: true)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 2, "Force regenerate should bypass cache")
    }

    // MARK: - Message Construction

    func testBuildUserMessage_includesSessionData() {
        let sessions = makeSessions(count: 3)
        let message = vm.buildUserMessage(sessions: sessions, plans: [], profile: nil)

        XCTAssertTrue(message.contains("WORKOUT SESSIONS (3 total)"))
        XCTAssertTrue(message.contains("exercises"))
        XCTAssertTrue(message.contains("pain"))
    }

    func testBuildUserMessage_includesPlanContext() {
        let plans = makePlans()
        let message = vm.buildUserMessage(sessions: [], plans: plans, profile: nil)

        XCTAssertTrue(message.contains("Knee Rehab"))
        XCTAssertTrue(message.contains("knee pain"))
        XCTAssertTrue(message.contains("Wall Sits"))
    }

    func testBuildUserMessage_includesProfileContext() {
        let profile = TestFixtures.makeProfile(
            age: 35,
            sex: "Female",
            activityLevel: "Active",
            medicalConditions: ["Diabetes"],
            medications: ["Metformin"]
        )
        let message = vm.buildUserMessage(sessions: [], plans: [], profile: profile)

        XCTAssertTrue(message.contains("35 year old Female"))
        XCTAssertTrue(message.contains("Active"))
        XCTAssertTrue(message.contains("Diabetes"))
        XCTAssertTrue(message.contains("Metformin"))
    }

    func testBuildUserMessage_handlesNilProfile() {
        let message = vm.buildUserMessage(sessions: [], plans: [], profile: nil)

        XCTAssertTrue(message.contains("Not available"))
    }

    func testBuildUserMessage_includesRegionPainLevels() {
        let session = WorkoutSession(
            id: UUID(),
            date: Date(),
            duration: 1800,
            painLevel: 4.0,
            isCompleted: true,
            exercisesPerformed: ["Wall Sits"],
            regionPainLevels: ["right_knee": 3.5, "left_hip": 5.0]
        )
        let message = vm.buildUserMessage(sessions: [session], plans: [], profile: nil)

        XCTAssertTrue(message.contains("right_knee"))
        XCTAssertTrue(message.contains("left_hip"))
        XCTAssertTrue(message.contains("regions:"))
    }

    // MARK: - Response Parsing

    func testParseInsight_validJSON_returnsInsight() throws {
        let json = TestFixtures.makeRecoveryInsightsResponseJSON()
        let insight = try vm.parseInsight(from: json)

        XCTAssertEqual(insight.headline, "Great Progress This Week")
        XCTAssertEqual(insight.painAnalysis.trendDirection, "improving")
        XCTAssertEqual(insight.painAnalysis.averagePain, 4.2, accuracy: 0.01)
        XCTAssertEqual(insight.adherenceAnalysis.score, 85)
        XCTAssertEqual(insight.recommendations.first?.icon, "figure.cooldown")
    }

    func testParseInsight_jsonWithMarkdownFences_stillParses() throws {
        let json = "```json\n" + TestFixtures.makeRecoveryInsightsResponseJSON() + "\n```"
        // Note: ClaudeAPIService.cleanJSONResponse strips fences before parseInsight sees it,
        // but our fallback { } extraction should still handle embedded JSON
        let insight = try vm.parseInsight(from: json)
        XCTAssertEqual(insight.headline, "Great Progress This Week")
    }

    func testParseInsight_invalidJSON_throws() {
        XCTAssertThrowsError(try vm.parseInsight(from: "not json"))
    }

    func testParseInsight_setsClientSideFields() throws {
        let json = TestFixtures.makeRecoveryInsightsResponseJSON()
        let insight = try vm.parseInsight(from: json)

        // id and generatedDate should be set client-side
        XCTAssertNotEqual(insight.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        XCTAssertTrue(Date().timeIntervalSince(insight.generatedDate) < 5, "generatedDate should be recent")
    }
}
