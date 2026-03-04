import XCTest
@testable import PT_Helper

// MARK: - InjuryAnalysisViewModel Tests

final class InjuryAnalysisViewModelTests: XCTestCase {

    private func makeProfile() -> UserProfile {
        UserProfile(
            userId: "test-uid",
            firstName: "Test", lastName: "User",
            dateOfBirth: Date(), sex: "Male",
            heightFeet: 5, heightInches: 10, weight: 175,
            medicalConditions: [], otherMedicalConditions: nil,
            surgeries: [], injuries: [],
            activityLevel: "Active", primarySport: nil
        )
    }

    private func makeRegion(name: String) -> BodyRegion {
        BodyRegion(
            name: name, zoneKey: name.lowercased().replacingOccurrences(of: " ", with: "_"),
            sides: [.front],
            frontPosition: CGPoint(x: 0.5, y: 0.5),
            backPosition: nil
        )
    }

    private func makeAssessment(region: BodyRegion) -> PainAssessment {
        PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painType: .sharp,
            customPainDescription: nil,
            painIntensity: 7,
            painDuration: .twoToFourWeeks,
            painFrequency: .onlyWithActivity,
            painOnset: .gradual,
            aggravatingFactors: ["Running"],
            relievingFactors: ["Rest"],
            additionalNotes: nil
        )
    }

    // MARK: - Initialization

    func testInitialState_SingleRegion() {
        let profile = makeProfile()
        let regions = [makeRegion(name: "Right Knee")]
        let vm = InjuryAnalysisViewModel(userProfile: profile, selectedRegions: regions)

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
        let regions = [makeRegion(name: "Right Knee"), makeRegion(name: "Lower Back"), makeRegion(name: "Left Shoulder")]
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: regions)

        XCTAssertEqual(vm.totalRegions, 3)
        XCTAssertEqual(vm.assessments.count, 3)
        XCTAssertTrue(vm.assessments.allSatisfy { $0 == nil })
    }

    // MARK: - Navigation

    func testIsLastRegion_SingleRegion() {
        let vm = InjuryAnalysisViewModel(
            userProfile: makeProfile(),
            selectedRegions: [makeRegion(name: "Knee")]
        )
        XCTAssertTrue(vm.isLastRegion)
    }

    func testIsLastRegion_MultipleRegions() {
        let regions = [makeRegion(name: "A"), makeRegion(name: "B")]
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: regions)

        XCTAssertFalse(vm.isLastRegion, "Should not be last on first region")
    }

    func testCurrentRegion() {
        let r1 = makeRegion(name: "Knee")
        let r2 = makeRegion(name: "Back")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [r1, r2])

        XCTAssertEqual(vm.currentRegion?.name, "Knee")
    }

    // MARK: - Save and Navigate

    func testSaveCurrentAssessment() {
        let region = makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [region])
        let assessment = makeAssessment(region: region)

        vm.saveCurrentAssessment(assessment)

        XCTAssertNotNil(vm.assessments[0])
        XCTAssertEqual(vm.assessments[0]?.painType, .sharp)
        XCTAssertEqual(vm.assessments[0]?.painIntensity, 7)
    }

    func testSaveAndAdvance() {
        let r1 = makeRegion(name: "Knee")
        let r2 = makeRegion(name: "Back")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [r1, r2])

        vm.saveAndAdvance(makeAssessment(region: r1))

        XCTAssertEqual(vm.currentRegionIndex, 1, "Should advance to next region")
        XCTAssertNotNil(vm.assessments[0], "First region should be saved")
    }

    func testSaveAndAdvance_DoesNotGoOutOfBounds() {
        let region = makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [region])

        vm.saveAndAdvance(makeAssessment(region: region))

        XCTAssertEqual(vm.currentRegionIndex, 0, "Should not advance past last region")
    }

    func testSaveAndGoBack() {
        let r1 = makeRegion(name: "Knee")
        let r2 = makeRegion(name: "Back")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [r1, r2])

        // Advance to second region
        vm.saveAndAdvance(makeAssessment(region: r1))
        XCTAssertEqual(vm.currentRegionIndex, 1)

        // Go back
        vm.saveAndGoBack(makeAssessment(region: r2))
        XCTAssertEqual(vm.currentRegionIndex, 0, "Should go back to first region")
        XCTAssertNotNil(vm.assessments[1], "Second region should still be saved")
    }

    func testSaveAndGoBack_DoesNotGoNegative() {
        let region = makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [region])

        vm.saveAndGoBack(makeAssessment(region: region))
        XCTAssertEqual(vm.currentRegionIndex, 0, "Should not go below 0")
    }

    // MARK: - Cancel and Reset

    func testCancelAnalysis() {
        let vm = InjuryAnalysisViewModel(
            userProfile: makeProfile(),
            selectedRegions: [makeRegion(name: "Knee")]
        )

        // Simulate analysis started
        vm.cancelAnalysis()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    func testResetAnalysisState() {
        let vm = InjuryAnalysisViewModel(
            userProfile: makeProfile(),
            selectedRegions: [makeRegion(name: "Knee")]
        )

        vm.resetAnalysisState()

        XCTAssertFalse(vm.isAnalyzing)
        XCTAssertNil(vm.analysisError)
        XCTAssertNil(vm.analysisResult)
        XCTAssertFalse(vm.showAnalyzingScreen)
    }

    // MARK: - Selected Region Names

    func testSelectedRegionNames() {
        let regions = [makeRegion(name: "Right Knee"), makeRegion(name: "Lower Back")]
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: regions)

        XCTAssertEqual(vm.selectedRegionNames, ["Right Knee", "Lower Back"])
    }

    // MARK: - Current Assessment Restore

    func testCurrentAssessment_NilBeforeSave() {
        let vm = InjuryAnalysisViewModel(
            userProfile: makeProfile(),
            selectedRegions: [makeRegion(name: "Knee")]
        )
        XCTAssertNil(vm.currentAssessment)
    }

    func testCurrentAssessment_AfterSave() {
        let region = makeRegion(name: "Knee")
        let vm = InjuryAnalysisViewModel(userProfile: makeProfile(), selectedRegions: [region])
        let assessment = makeAssessment(region: region)

        vm.saveCurrentAssessment(assessment)

        XCTAssertNotNil(vm.currentAssessment)
        XCTAssertEqual(vm.currentAssessment?.painIntensity, 7)
    }
}
