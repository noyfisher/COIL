import XCTest
@testable import COIL

// MARK: - InjuryAnalysisViewModel Tests

@MainActor
final class InjuryAnalysisViewModelTests: XCTestCase {

    // MARK: - Initialization

    func testInitialState_SingleRegion() {
        let regions = [TestFixtures.makeRegion(name: "Right Knee")]
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: regions)

        XCTAssertEqual(vm.currentRegionIndex, 0)
        XCTAssertEqual(vm.totalRegions, 1)
        XCTAssertEqual(vm.assessments.count, 1, "Should pre-allocate one slot per region")
        XCTAssertNil(vm.assessments[0], "Assessment slots should start nil")
        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    func testInitialState_MultipleRegions() {
        let regions = [
            TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee"),
            TestFixtures.makeRegion(name: "Lower Back", zoneKey: "lower_back"),
            TestFixtures.makeRegion(name: "Left Shoulder", zoneKey: "left_shoulder")
        ]
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: regions)

        XCTAssertEqual(vm.totalRegions, 3)
        XCTAssertEqual(vm.assessments.count, 3)
        XCTAssertTrue(vm.assessments.allSatisfy { $0 == nil })
    }

    // MARK: - Navigation

    func testIsLastRegion_SingleRegion() {
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [TestFixtures.makeRegion(name: "Knee")]
        )
        XCTAssertTrue(vm.isLastRegion)
    }

    func testIsLastRegion_MultipleRegions() {
        let regions = [TestFixtures.makeRegion(name: "A", zoneKey: "a"), TestFixtures.makeRegion(name: "B", zoneKey: "b")]
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: regions)

        XCTAssertFalse(vm.isLastRegion, "Should not be last on first region")
    }

    func testCurrentRegion() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [r1, r2])

        XCTAssertEqual(vm.currentRegion?.name, "Knee")
    }

    // MARK: - Save and Navigate

    func testSaveCurrentAssessment() {
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [region])
        let assessment = TestFixtures.makeAssessment(region: region)

        vm.saveCurrentAssessment(assessment)

        XCTAssertNotNil(vm.assessments[0])
        XCTAssertEqual(vm.assessments[0]?.painTypes, ["Aching"])
        XCTAssertEqual(vm.assessments[0]?.painIntensity, 5)
    }

    func testSaveAndAdvance() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [r1, r2])

        vm.saveAndAdvance(TestFixtures.makeAssessment(region: r1))

        XCTAssertEqual(vm.currentRegionIndex, 1, "Should advance to next region")
        XCTAssertNotNil(vm.assessments[0], "First region should be saved")
    }

    func testSaveAndAdvance_DoesNotGoOutOfBounds() {
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [region])

        vm.saveAndAdvance(TestFixtures.makeAssessment(region: region))

        XCTAssertEqual(vm.currentRegionIndex, 0, "Should not advance past last region")
    }

    func testSaveAndGoBack() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [r1, r2])

        vm.saveAndAdvance(TestFixtures.makeAssessment(region: r1))
        XCTAssertEqual(vm.currentRegionIndex, 1)

        vm.saveAndGoBack(TestFixtures.makeAssessment(region: r2))
        XCTAssertEqual(vm.currentRegionIndex, 0, "Should go back to first region")
        XCTAssertNotNil(vm.assessments[1], "Second region should still be saved")
    }

    func testSaveAndGoBack_DoesNotGoNegative() {
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [region])

        vm.saveAndGoBack(TestFixtures.makeAssessment(region: region))
        XCTAssertEqual(vm.currentRegionIndex, 0, "Should not go below 0")
    }

    // MARK: - Cancel and Reset

    func testCancelAnalysis() {
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [TestFixtures.makeRegion(name: "Knee")]
        )

        vm.cancelAnalysis()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    func testResetAnalysisState() {
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [TestFixtures.makeRegion(name: "Knee")]
        )

        vm.resetAnalysisState()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    // MARK: - Selected Region Names

    func testSelectedRegionNames() {
        let regions = [
            TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee"),
            TestFixtures.makeRegion(name: "Lower Back", zoneKey: "lower_back")
        ]
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: regions)

        XCTAssertEqual(vm.selectedRegionNames, ["Right Knee", "Lower Back"])
    }

    // MARK: - Current Assessment Restore

    func testCurrentAssessment_NilBeforeSave() {
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [TestFixtures.makeRegion(name: "Knee")]
        )
        XCTAssertNil(vm.currentAssessment)
    }

    func testCurrentAssessment_AfterSave() {
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: [region])
        let assessment = TestFixtures.makeAssessment(region: region, painIntensity: 7)

        vm.saveCurrentAssessment(assessment)

        XCTAssertNotNil(vm.currentAssessment)
        XCTAssertEqual(vm.currentAssessment?.painIntensity, 7)
    }

    // MARK: - Apply to All Regions

    func testIsFirstRegion() {
        let regions = [TestFixtures.makeRegion(name: "A", zoneKey: "a"), TestFixtures.makeRegion(name: "B", zoneKey: "b")]
        let vm = InjuryAnalysisViewModel(userProfile: TestFixtures.makeProfile(), selectedRegions: regions)

        XCTAssertTrue(vm.isFirstRegion)

        vm.saveAndAdvance(TestFixtures.makeAssessment(region: regions[0]))
        XCTAssertFalse(vm.isFirstRegion)
    }

    func testHasMultipleRegions() {
        let singleVM = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [TestFixtures.makeRegion(name: "A")]
        )
        XCTAssertFalse(singleVM.hasMultipleRegions)

        let multiVM = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [TestFixtures.makeRegion(name: "A", zoneKey: "a"), TestFixtures.makeRegion(name: "B", zoneKey: "b")]
        )
        XCTAssertTrue(multiVM.hasMultipleRegions)
    }

    func testApplyToAllRegions_FillsAllAssessments() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let r3 = TestFixtures.makeRegion(name: "Shoulder", zoneKey: "shoulder")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [r1, r2, r3]
        )

        let template = TestFixtures.makeAssessment(region: r1)
        vm.applyToAllRegionsAndAnalyze(template)

        XCTAssertEqual(vm.assessments.compactMap { $0 }.count, 3)
    }

    func testApplyToAllRegions_PreservesRegionIdentity() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [r1, r2]
        )

        let template = TestFixtures.makeAssessment(region: r1)
        vm.applyToAllRegionsAndAnalyze(template)

        XCTAssertEqual(vm.assessments[0]?.selectedRegion.name, "Knee")
        XCTAssertEqual(vm.assessments[1]?.selectedRegion.name, "Back")
    }

    func testApplyToAllRegions_CopiesPainData() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [r1, r2]
        )

        let template = TestFixtures.makeAssessment(region: r1, painTypes: ["Sharp"], painIntensity: 7)
        vm.applyToAllRegionsAndAnalyze(template)

        XCTAssertEqual(vm.assessments[1]?.painTypes, template.painTypes)
        XCTAssertEqual(vm.assessments[1]?.painIntensity, template.painIntensity)
        XCTAssertEqual(vm.assessments[1]?.painDurations, template.painDurations)
        XCTAssertEqual(vm.assessments[1]?.painFrequencies, template.painFrequencies)
        XCTAssertEqual(vm.assessments[1]?.painOnsets, template.painOnsets)
    }

    func testApplyToAllRegions_UniqueIDs() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let r3 = TestFixtures.makeRegion(name: "Shoulder", zoneKey: "shoulder")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [r1, r2, r3]
        )

        vm.applyToAllRegionsAndAnalyze(TestFixtures.makeAssessment(region: r1))

        let ids = vm.assessments.compactMap { $0?.id }
        XCTAssertEqual(Set(ids).count, 3, "Each assessment should have a unique ID")
    }

    func testApplyToAllRegions_TriggersAnalysis() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [r1, r2]
        )

        vm.applyToAllRegionsAndAnalyze(TestFixtures.makeAssessment(region: r1))

        XCTAssertTrue(vm.isAnalyzing)
        XCTAssertTrue(vm.showAnalyzingScreen)
    }

    func testApplyToAllRegions_DoesNotChangeIndex() {
        let r1 = TestFixtures.makeRegion(name: "Knee", zoneKey: "knee")
        let r2 = TestFixtures.makeRegion(name: "Back", zoneKey: "back")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [r1, r2]
        )

        vm.applyToAllRegionsAndAnalyze(TestFixtures.makeAssessment(region: r1))

        XCTAssertEqual(vm.currentRegionIndex, 0, "Index should remain at 0 after apply-to-all")
    }

    // MARK: - Async Analysis Tests (with MockClaudeAPIService)

    func testStartAnalysis_setsAnalyzingState() {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeAnalysisResponseJSON()
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        vm.saveAndAnalyze(TestFixtures.makeAssessment(region: region))

        XCTAssertTrue(vm.isAnalyzing)
        XCTAssertTrue(vm.showAnalyzingScreen)
        XCTAssertNil(vm.analysisError)
    }

    func testStartAnalysis_success_populatesResult() async throws {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeAnalysisResponseJSON(
            conditionName: "Patellofemoral Pain Syndrome",
            confidence: 80
        )
        let region = TestFixtures.makeRegion(name: "Right Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        vm.saveAndAnalyze(TestFixtures.makeAssessment(region: region))
        await vm.analysisTask?.value

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNotNil(vm.analysisResult)
        XCTAssertNil(vm.analysisError)
        XCTAssertEqual(vm.analysisResult?.conditions.first?.conditionName, "Patellofemoral Pain Syndrome")
    }

    func testStartAnalysis_success_callsAPIWithAnalysisType() async throws {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeAnalysisResponseJSON()
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        vm.saveAndAnalyze(TestFixtures.makeAssessment(region: region))
        await vm.analysisTask?.value

        // Two-call pipeline: primary analysis + verification
        XCTAssertEqual(mock.sendMessageCallCount, 2)
        XCTAssertEqual(mock.allRequestTypes.first, .analysis, "First call should be .analysis")
        XCTAssertEqual(mock.lastRequestType, .analysis_verify, "Second call should be .analysis_verify")
    }

    func testStartAnalysis_apiError_setsError() async throws {
        let mock = MockClaudeAPIService()
        mock.errorToThrow = ClaudeAPIError.rateLimited
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        vm.saveAndAnalyze(TestFixtures.makeAssessment(region: region))
        await vm.analysisTask?.value

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNotNil(vm.analysisError)
        XCTAssertNil(vm.analysisResult)
    }

    func testCancelAnalysis_stopsInFlightRequest() async throws {
        let mock = MockClaudeAPIService()
        mock.simulatedDelay = 5 // Long delay to ensure cancel happens during request
        mock.responseToReturn = TestFixtures.makeAnalysisResponseJSON()
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        vm.saveAndAnalyze(TestFixtures.makeAssessment(region: region))
        XCTAssertTrue(vm.isAnalyzing)

        vm.cancelAnalysis()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertFalse(vm.showAnalyzingScreen)
        XCTAssertNil(vm.analysisError)
    }

    func testRetryAnalysis_afterError() async throws {
        let mock = MockClaudeAPIService()
        mock.errorToThrow = ClaudeAPIError.networkError(NSError(domain: "", code: -1))
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        // First attempt fails (primary call throws, 1 API call)
        vm.saveAndAnalyze(TestFixtures.makeAssessment(region: region))
        await vm.analysisTask?.value
        XCTAssertNotNil(vm.analysisError)

        // Retry succeeds (primary + verification = 2 API calls)
        mock.errorToThrow = nil
        mock.responseToReturn = TestFixtures.makeAnalysisResponseJSON()
        vm.retryAnalysis()
        await vm.analysisTask?.value

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertNotNil(vm.analysisResult)
        // Total: 1 (failed primary) + 2 (successful primary + verify) = 3
        XCTAssertEqual(mock.sendMessageCallCount, 3)
    }

    // MARK: - WP-2.2 — Emergency pre-screen (no API call for 911-pattern data)

    func testStartAnalysis_EmergencySymptoms_MakesNoAPICall() {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeAnalysisResponseJSON()
        // Cardiac 911 pattern requires "chest pain" + "shortness of breath" in free text
        // AND a chest region key. Put it in the free-text notes field.
        let chestRegion = TestFixtures.makeRegion(name: "Chest", zoneKey: "chest")
        let emergencyAssessment = PainAssessment(
            id: UUID(),
            selectedRegion: chestRegion,
            painTypes: ["Aching"],
            customPainDescription: nil,
            painIntensity: 5,
            painDurations: ["Over a Month"],
            painFrequencies: ["Intermittent"],
            painOnsets: ["Gradual"],
            aggravatingFactors: [],
            relievingFactors: [],
            additionalNotes: "chest pain and shortness of breath",
            currentTreatment: nil
        )
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [chestRegion],
            apiService: mock
        )

        vm.saveAndAnalyze(emergencyAssessment)

        XCTAssertEqual(mock.sendMessageCallCount, 0, "911-pattern data must never leave the device")
        XCTAssertFalse(vm.redFlagAlerts.isEmpty, "Emergency red-flag alerts should be populated")
        XCTAssertEqual(vm.redFlagAlerts.map(\.severity).max(), .emergency)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertTrue(vm.showAnalyzingScreen, "Analyzing screen shows so AnalyzingView can route to the emergency redirect")
    }

    func testStartAnalysis_noCompletedAssessments_doesNotCallAPI() {
        let mock = MockClaudeAPIService()
        let region = TestFixtures.makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(
            userProfile: TestFixtures.makeProfile(),
            selectedRegions: [region],
            apiService: mock
        )

        // Don't save any assessment, just try to start analysis directly
        // Since startAnalysis is private, we go through saveAndAnalyze but without saving first
        // Actually, saveAndAnalyze saves first then calls startAnalysis, so let's call retryAnalysis
        // with no assessments filled.
        vm.retryAnalysis()

        // Should not have called the API since there are no completed assessments
        XCTAssertEqual(mock.sendMessageCallCount, 0)
        XCTAssertFalse(vm.isAnalyzing)
    }
}
