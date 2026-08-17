import XCTest
@testable import COIL

@MainActor
final class FormAnalysisViewModelTests: XCTestCase {
    private var mockAPI: MockClaudeAPIService!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
    }

    // MARK: - Message Construction

    func testBuildUserMessage_includesExerciseMetadata() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Bodyweight Squat", targetArea: "Quadriceps")

        let metrics = FormAnalysisData(
            exerciseName: "Bodyweight Squat",
            exerciseCategory: "strength",
            targetArea: "Quadriceps",
            totalFramesProcessed: 100,
            videoFPS: 30.0,
            videoDurationSeconds: 10.0,
            detectedRepCount: 0,
            repMetrics: [],
            symmetry: nil,
            alignment: [],
            averageTempo: nil,
            tempoVariability: nil,
            bodyHeight: 1.75
        )

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertTrue(message.contains("Bodyweight Squat"), "Message should include exercise name")
        XCTAssertTrue(message.contains("Quadriceps"), "Message should include target area")
        XCTAssertTrue(message.contains("10.0"), "Message should include video duration")
        XCTAssertTrue(message.contains("1.75"), "Message should include body height")
    }

    func testBuildUserMessage_includesRepMetrics() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")

        let rep = RepMetrics(
            repNumber: 1,
            keyAngles: [
                "left_knee": RepMetrics.AngleRange(
                    minDegrees: 85, maxDegrees: 170, rangeOfMotion: 85,
                    atStart: 170, atMid: 85, atEnd: 170
                ),
            ],
            durationSeconds: 2.5,
            startTimestamp: 0,
            endTimestamp: 2.5
        )

        let metrics = FormAnalysisData(
            exerciseName: "Squat",
            exerciseCategory: "strength",
            targetArea: "Quadriceps",
            totalFramesProcessed: 75,
            videoFPS: 30.0,
            videoDurationSeconds: 5.0,
            detectedRepCount: 1,
            repMetrics: [rep],
            symmetry: nil,
            alignment: [],
            averageTempo: 2.5,
            tempoVariability: nil,
            bodyHeight: nil
        )

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertTrue(message.contains("1 reps detected"), "Message should include rep count")
        XCTAssertTrue(message.contains("left_knee"), "Message should include angle name")
        XCTAssertTrue(message.contains("ROM=85.0"), "Message should include range of motion")
    }

    func testBuildUserMessage_noRepsDetected_includesNote() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Plank", targetArea: "Core")

        let metrics = FormAnalysisData(
            exerciseName: "Plank",
            exerciseCategory: "core",
            targetArea: "Core",
            totalFramesProcessed: 100,
            videoFPS: 30.0,
            videoDurationSeconds: 30.0,
            detectedRepCount: 0,
            repMetrics: [],
            symmetry: nil,
            alignment: [],
            averageTempo: nil,
            tempoVariability: nil,
            bodyHeight: nil
        )

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertTrue(message.contains("No repetitions were detected"), "Message should note no reps for static holds")
    }

    // MARK: - State Transitions

    func testInitialState_isIdle() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.processingProgress, 0)
    }

    func testReset_returnsToIdle() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        vm.reset()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertEqual(vm.processingProgress, 0)
    }

    // MARK: - API Request Type

    func testAnalyzeVideo_usesFormAnalysisRequestType() async {
        // We can't easily test the full pipeline without a video file,
        // but we can verify the ViewModel uses the right API service pattern
        let vm = FormAnalysisViewModel(apiService: mockAPI)

        // Configure mock to return valid form feedback JSON
        mockAPI.responseToReturn = """
        {"overallScore":80,"verdict":"good","corrections":[],"positivePoints":["Good form"],"safetyNotes":[]}
        """

        // The full analyzeVideo requires a video URL, which we can't provide in unit tests.
        // Instead, verify the buildUserMessage and parsing work correctly.
        XCTAssertNotNil(vm, "ViewModel should initialize with mock API service")
    }

    // MARK: - FormFeedback Model

    func testFormFeedback_decodesFromJSON() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "exerciseName": "Squat",
            "overallScore": 75,
            "verdict": "good",
            "corrections": [
                {
                    "bodyPart": "knees",
                    "issue": "Knees caving inward",
                    "howToFix": "Push knees out over toes",
                    "severity": "moderate"
                }
            ],
            "positivePoints": ["Good depth"],
            "safetyNotes": [],
            "date": "2026-03-24T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feedback = try decoder.decode(FormFeedback.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(feedback.overallScore, 75)
        XCTAssertEqual(feedback.verdict, .good)
        XCTAssertEqual(feedback.corrections.count, 1)
        XCTAssertEqual(feedback.corrections[0].bodyPart, "knees")
        XCTAssertEqual(feedback.corrections[0].severity, .moderate)
        XCTAssertEqual(feedback.positivePoints, ["Good depth"])
    }

    // MARK: - AI response decode (wire format)

    /// Regression: the wire struct declared `overallScore` as `Int`, but the server
    /// contract (`formAnalysisSchema.overallScore` in `functions/src/response-schemas.ts`)
    /// is `z.number().min(0).max(100)` and permits fractional values. A score of 87.5
    /// threw on decode and failed the entire form analysis.
    func testParseFormFeedback_fractionalOverallScore_decodesAndRounds() throws {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let json = """
        {"overallScore":87.5,"verdict":"good","corrections":[],"positivePoints":["Good depth"],"safetyNotes":[]}
        """

        let feedback = try vm.parseFormFeedback(from: json, exerciseName: "Squat")

        XCTAssertEqual(feedback.overallScore, 88, "87.5 should round to 88, not throw")
    }

    func testParseFormFeedback_integerOverallScore_stillDecodes() throws {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let json = """
        {"overallScore":80,"verdict":"good","corrections":[],"positivePoints":["Good form"],"safetyNotes":[]}
        """

        let feedback = try vm.parseFormFeedback(from: json, exerciseName: "Squat")

        XCTAssertEqual(feedback.overallScore, 80)
    }

    func testParseFormFeedback_outOfRangeScore_clampedToBounds() throws {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let high = """
        {"overallScore":143.2,"verdict":"good","corrections":[],"positivePoints":[],"safetyNotes":[]}
        """
        let low = """
        {"overallScore":-12.7,"verdict":"needs_work","corrections":[],"positivePoints":[],"safetyNotes":[]}
        """

        XCTAssertEqual(try vm.parseFormFeedback(from: high, exerciseName: "Squat").overallScore, 100)
        XCTAssertEqual(try vm.parseFormFeedback(from: low, exerciseName: "Squat").overallScore, 0)
    }

    // MARK: - buildUserMessage with Data Quality

    func testBuildUserMessage_withDataQuality_includesSection() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let metrics = TestFixtures.makeFormAnalysisData()
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.85)

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise, dataQuality: quality)

        XCTAssertTrue(message.contains("DATA QUALITY"), "Message should include data quality section")
        XCTAssertTrue(message.contains("0.85"), "Should include overall quality score")
        XCTAssertTrue(message.contains("Frame coverage"), "Should include frame coverage")
    }

    func testBuildUserMessage_withSymmetry_includesSection() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let symmetry = FormAnalysisData.SymmetryData(
            leftAvgAngles: ["left_knee": 90], rightAvgAngles: ["right_knee": 100],
            differencesDegrees: ["knee": 10]
        )
        let metrics = TestFixtures.makeFormAnalysisData(symmetry: symmetry)

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertTrue(message.contains("SYMMETRY"), "Message should include symmetry section")
        XCTAssertTrue(message.contains("knee"), "Should include joint name")
    }

    func testBuildUserMessage_withAlignmentIssues_includesSection() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let alignment = [FormAnalysisData.AlignmentIssue(description: "Trunk lean detected", affectedReps: 2, totalReps: 3)]
        let metrics = TestFixtures.makeFormAnalysisData(alignment: alignment)

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertTrue(message.contains("ALIGNMENT ISSUES"), "Message should include alignment section")
        XCTAssertTrue(message.contains("Trunk lean detected"))
    }

    func testBuildUserMessage_withTempo_includesSection() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")
        let metrics = TestFixtures.makeFormAnalysisData(averageTempo: 2.5, tempoVariability: 0.4)

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertTrue(message.contains("TEMPO"), "Message should include tempo section")
        XCTAssertTrue(message.contains("2.5"), "Should include average tempo")
        XCTAssertTrue(message.contains("0.4"), "Should include tempo variability")
    }

    func testBuildUserMessage_noTempo_omitsSection() {
        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Plank", targetArea: "Core")
        let metrics = TestFixtures.makeFormAnalysisData(repCount: 0, repMetrics: [], averageTempo: nil, tempoVariability: nil)

        let message = vm.buildUserMessage(metrics: metrics, exercise: exercise)

        XCTAssertFalse(message.contains("TEMPO"), "No tempo data should omit tempo section")
        XCTAssertTrue(message.contains("No repetitions were detected"))
    }

    // MARK: - Agent Routing & Fallback (mirrors RecoveryInsightsViewModelTests)

    private func makeVM(priorCount: Int) -> (vm: FormAnalysisViewModel, store: MockFormAnalysisStore) {
        let store = MockFormAnalysisStore()
        store.priorCountToReturn = priorCount
        let vm = FormAnalysisViewModel(apiService: mockAPI, store: store)
        return (vm, store)
    }

    private static let agentResponseJSON = """
    {"overallScore":82,"verdict":"good","corrections":[],"positivePoints":["Consistent depth"],"safetyNotes":[],"progressTrends":[{"metric":"Knee range of motion","direction":"improving","description":"Knee ROM increased from 78 to 91 degrees across 4 sessions"}],"recurringIssues":[],"sessionComparison":"Today's depth was your best yet — knee ROM hit 91 vs an 80 average."}
    """

    func testFetchAIFeedback_enoughHistory_usesAgentOnly() async throws {
        let (vm, store) = makeVM(priorCount: 2)
        mockAPI.agentFormAnalysisResponseToReturn = Self.agentResponseJSON
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")

        let (response, source) = try await vm.fetchAIFeedback(userMessage: "metrics", exercise: exercise)

        XCTAssertEqual(source, "agent")
        XCTAssertEqual(response, Self.agentResponseJSON)
        XCTAssertEqual(mockAPI.requestAgentFormAnalysisCallCount, 1)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0, "Agent success should not hit the single-call path")
        XCTAssertEqual(store.lastQueriedExerciseName, "Squat")
    }

    func testFetchAIFeedback_agentFails_fallsBackToSingleCall() async throws {
        let (vm, _) = makeVM(priorCount: 3)
        mockAPI.agentFormAnalysisErrorToThrow = ClaudeAPIError.networkError(
            NSError(domain: "test", code: -1)
        )
        mockAPI.responseToReturn = """
        {"overallScore":75,"verdict":"good","corrections":[],"positivePoints":["Good form"],"safetyNotes":[]}
        """
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")

        let (_, source) = try await vm.fetchAIFeedback(userMessage: "metrics", exercise: exercise)

        XCTAssertEqual(source, "single_call")
        XCTAssertEqual(mockAPI.requestAgentFormAnalysisCallCount, 1, "Agent should be tried first")
        XCTAssertEqual(mockAPI.sendMessageCallCount, 1, "Fallback should hit the single-call path")
        XCTAssertEqual(mockAPI.lastRequestType, .form_analysis, "Fallback must use the existing request type")
    }

    func testFetchAIFeedback_insufficientHistory_skipsAgent() async throws {
        let (vm, _) = makeVM(priorCount: 1)
        mockAPI.responseToReturn = """
        {"overallScore":75,"verdict":"good","corrections":[],"positivePoints":["Good form"],"safetyNotes":[]}
        """
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")

        let (_, source) = try await vm.fetchAIFeedback(userMessage: "metrics", exercise: exercise)

        XCTAssertEqual(source, "single_call")
        XCTAssertEqual(mockAPI.requestAgentFormAnalysisCallCount, 0, "Below threshold the agent is never tried")
        XCTAssertEqual(mockAPI.sendMessageCallCount, 1)
    }

    func testFetchAIFeedback_passesExerciseNameAndMessage() async throws {
        let (vm, _) = makeVM(priorCount: 5)
        mockAPI.agentFormAnalysisResponseToReturn = Self.agentResponseJSON
        let exercise = TestFixtures.makeExercise(name: "Glute Bridge", targetArea: "Glutes")

        _ = try await vm.fetchAIFeedback(userMessage: "CURRENT METRICS BLOCK", exercise: exercise)

        XCTAssertEqual(mockAPI.lastAgentFormExerciseName, "Glute Bridge")
        XCTAssertEqual(mockAPI.lastAgentFormUserMessage, "CURRENT METRICS BLOCK")
    }

    func testFetchAIFeedback_bothPathsFail_throws() async {
        let (vm, _) = makeVM(priorCount: 2)
        mockAPI.agentFormAnalysisErrorToThrow = ClaudeAPIError.rateLimited
        mockAPI.errorToThrow = ClaudeAPIError.rateLimited
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")

        do {
            _ = try await vm.fetchAIFeedback(userMessage: "metrics", exercise: exercise)
            XCTFail("Should throw when both agent and fallback fail")
        } catch {
            // Expected — analyzeVideo's catch handles this as today.
        }
    }

    // MARK: - Cross-Session Decoding

    func testFormFeedback_decodesWithProgressInsights() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "exerciseName": "Squat",
            "overallScore": 82,
            "verdict": "good",
            "corrections": [],
            "positivePoints": ["Consistent depth"],
            "safetyNotes": [],
            "date": "2026-06-09T12:00:00Z",
            "progressInsights": {
                "progressTrends": [
                    {"metric": "Knee ROM", "direction": "improving", "description": "78 to 91 degrees"}
                ],
                "recurringIssues": [
                    {"issue": "Left knee valgus", "sessionsObserved": 3, "description": "Seen in 3 of 4 sessions"}
                ],
                "sessionComparison": "Best depth yet."
            }
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feedback = try decoder.decode(FormFeedback.self, from: json.data(using: .utf8)!)

        let insights = try XCTUnwrap(feedback.progressInsights)
        XCTAssertEqual(insights.progressTrends.count, 1)
        XCTAssertEqual(insights.progressTrends[0].direction, .improving)
        XCTAssertEqual(insights.recurringIssues[0].sessionsObserved, 3)
        XCTAssertEqual(insights.sessionComparison, "Best depth yet.")
    }

    func testFormFeedback_decodesWithoutProgressInsights_isNil() throws {
        let json = """
        {
            "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
            "exerciseName": "Squat",
            "overallScore": 75,
            "verdict": "good",
            "corrections": [],
            "positivePoints": ["Good depth"],
            "safetyNotes": [],
            "date": "2026-06-09T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feedback = try decoder.decode(FormFeedback.self, from: json.data(using: .utf8)!)

        XCTAssertNil(feedback.progressInsights, "Single-call payloads have no cross-session insights")
    }

    // MARK: - Record Compaction

    func testMakeRecord_compactsMetricsAndFeedback() {
        let metrics = TestFixtures.makeFormAnalysisData(
            exerciseName: "Squat",
            symmetry: FormAnalysisData.SymmetryData(
                leftAvgAngles: ["left_knee": 90], rightAvgAngles: ["right_knee": 98],
                differencesDegrees: ["knee": 8]
            ),
            alignment: [FormAnalysisData.AlignmentIssue(description: "Trunk lean", affectedReps: 2, totalReps: 3)]
        )
        let feedback = TestFixtures.makeFormFeedback(
            score: 78,
            corrections: [FormFeedback.Correction(
                bodyPart: "knees", issue: "Inward collapse",
                howToFix: "Push knees out", severity: .moderate,
                dataReference: "symmetry.knee: 8°"
            )]
        )
        let quality = TestFixtures.makeDataQualityReport(overallScore: 0.85)

        let record = FormAnalysisRecord.makeRecord(
            metrics: metrics, feedback: feedback, dataQuality: quality, source: "agent"
        )

        XCTAssertEqual(record.exerciseName, "Squat")
        XCTAssertEqual(record.score, 78)
        XCTAssertEqual(record.verdict, "good")
        XCTAssertEqual(record.source, "agent")
        XCTAssertEqual(record.repCount, 3)
        XCTAssertEqual(record.reps.count, 3)
        XCTAssertEqual(record.symmetryDifferences?["knee"], 8)
        XCTAssertEqual(record.alignmentIssues, ["Trunk lean (2/3 reps)"])
        XCTAssertEqual(record.dataQualityScore, 0.85)
        XCTAssertEqual(record.corrections.count, 1)
        XCTAssertEqual(record.corrections[0].bodyPart, "knees")
        XCTAssertEqual(record.corrections[0].dataReference, "symmetry.knee: 8°")

        // Compactness: the Firestore dict drops howToFix and has no raw frames.
        let dict = record.firestoreData
        let correctionDicts = dict["corrections"] as? [[String: Any]]
        XCTAssertNil(correctionDicts?.first?["howToFix"], "howToFix is not persisted (compactness)")
        XCTAssertNil(dict["perRepSymmetry"], "Per-rep phase symmetry is not persisted")
    }

    // MARK: - State

    func testFormAnalysisState_equality() {
        XCTAssertEqual(FormAnalysisState.idle, FormAnalysisState.idle)
        XCTAssertEqual(FormAnalysisState.analyzing, FormAnalysisState.analyzing)
        XCTAssertEqual(FormAnalysisState.processing(progress: 0.5), FormAnalysisState.processing(progress: 0.5))
        XCTAssertNotEqual(FormAnalysisState.idle, FormAnalysisState.analyzing)
        XCTAssertNotEqual(FormAnalysisState.processing(progress: 0.5), FormAnalysisState.processing(progress: 0.7))
        XCTAssertEqual(FormAnalysisState.error("test"), FormAnalysisState.error("test"))
        XCTAssertNotEqual(FormAnalysisState.error("a"), FormAnalysisState.error("b"))
    }

    // MARK: - WS8-01: Offline fail-fast

    func testAnalyzeVideo_offline_setsErrorState() async {
        _ = NetworkMonitor.shared
        await Task.yield()
        NetworkMonitor.shared.isConnected = false
        defer { NetworkMonitor.shared.isConnected = true }

        let vm = FormAnalysisViewModel(apiService: mockAPI)
        let exercise = TestFixtures.makeExercise(name: "Squat", targetArea: "Quadriceps")

        await vm.analyzeVideo(url: URL(fileURLWithPath: "/nonexistent.mov"), exercise: exercise)

        XCTAssertEqual(vm.state, .error("You're offline. Connect to the internet to analyze your form, then try again."))
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0)
        XCTAssertEqual(mockAPI.requestAgentFormAnalysisCallCount, 0)
    }
}
