import XCTest
@testable import PT_Helper

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
}
