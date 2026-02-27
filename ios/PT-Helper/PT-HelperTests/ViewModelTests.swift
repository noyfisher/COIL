import XCTest
@testable import PT_Helper

// MARK: - NotesViewModel Tests

@MainActor
final class NotesViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = NotesViewModel()
        XCTAssertTrue(vm.notes.isEmpty)
        XCTAssertEqual(vm.newNoteContent, "")
    }

    func testAddNote_Success() {
        let vm = NotesViewModel()
        vm.newNoteContent = "Feeling better today"
        vm.addNote()

        XCTAssertEqual(vm.notes.count, 1)
        XCTAssertEqual(vm.notes.first?.content, "Feeling better today")
        XCTAssertEqual(vm.newNoteContent, "", "Content should be cleared after adding")
    }

    func testAddNote_EmptyContentIgnored() {
        let vm = NotesViewModel()
        vm.newNoteContent = ""
        vm.addNote()

        XCTAssertTrue(vm.notes.isEmpty, "Empty notes should not be added")
    }

    func testAddMultipleNotes() {
        let vm = NotesViewModel()

        vm.newNoteContent = "Note 1"
        vm.addNote()
        vm.newNoteContent = "Note 2"
        vm.addNote()
        vm.newNoteContent = "Note 3"
        vm.addNote()

        XCTAssertEqual(vm.notes.count, 3)
        // Notes are inserted at front (newest first)
        XCTAssertEqual(vm.notes[0].content, "Note 3")
        XCTAssertEqual(vm.notes[1].content, "Note 2")
        XCTAssertEqual(vm.notes[2].content, "Note 1")
    }

    func testAddNote_ClearsContentAfterAdd() {
        let vm = NotesViewModel()
        vm.newNoteContent = "Test"
        vm.addNote()
        XCTAssertEqual(vm.newNoteContent, "")
    }

    func testAddNote_EachHasUniqueId() {
        let vm = NotesViewModel()
        vm.newNoteContent = "A"
        vm.addNote()
        vm.newNoteContent = "B"
        vm.addNote()

        XCTAssertNotEqual(vm.notes[0].id, vm.notes[1].id)
    }
}

// MARK: - WorkoutViewModel Tests

@MainActor
final class WorkoutViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = WorkoutViewModel()
        XCTAssertTrue(vm.sessions.isEmpty)
    }

    func testAddSession() {
        let vm = WorkoutViewModel()
        let session = WorkoutSession(
            id: UUID(), date: Date(),
            duration: 1800, painLevel: 5.0, isCompleted: true
        )
        vm.addSession(session: session)

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.painLevel, 5.0)
    }

    func testAddMultipleSessions() {
        let vm = WorkoutViewModel()
        for i in 1...5 {
            vm.addSession(session: WorkoutSession(
                id: UUID(), date: Date(),
                duration: Double(i * 600),
                painLevel: Double(i), isCompleted: true
            ))
        }
        XCTAssertEqual(vm.sessions.count, 5)
        // Sessions are inserted at front (newest first)
        XCTAssertEqual(vm.sessions.first?.painLevel, 5.0)
    }
}

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

// MARK: - RehabPlanViewModel Tests (non-Firebase, non-API parts)

@MainActor
final class RehabPlanViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = RehabPlanViewModel()
        XCTAssertNil(vm.rehabPlan)
        XCTAssertFalse(vm.isSaving)
        XCTAssertFalse(vm.showSaveSuccess)
        XCTAssertNil(vm.saveError)
        XCTAssertFalse(vm.isGenerating)
        XCTAssertNil(vm.generationError)
    }

    func testSettingRehabPlanDirectly() {
        let vm = RehabPlanViewModel()
        let plan = RehabPlan(
            id: UUID(),
            planName: "Test Plan",
            conditions: ["Test"],
            exercises: [],
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 4,
            createdDate: Date(),
            notes: nil
        )

        vm.rehabPlan = plan
        XCTAssertNotNil(vm.rehabPlan)
        XCTAssertEqual(vm.rehabPlan?.planName, "Test Plan")
    }

    func testRehabPlanWithExercises() {
        let vm = RehabPlanViewModel()
        let exercise = RehabExercise(
            id: UUID(),
            name: "Wall Sits",
            targetArea: "Knee",
            description: "Lean against a wall.",
            sets: 3,
            reps: "30 seconds",
            restSeconds: 45,
            difficulty: .intermediate,
            demonstrationIcon: "figure.cooldown",
            tips: ["Keep knees behind toes."],
            contraindications: ["Avoid deep bending."]
        )

        let plan = RehabPlan(
            id: UUID(),
            planName: "Knee Rehab Plan",
            conditions: ["Patellofemoral Pain Syndrome"],
            exercises: [exercise],
            weeklySchedule: [[], ["id1"], [], ["id1"], [], ["id1"], []],
            totalWeeks: 6,
            createdDate: Date(),
            notes: "Progress gradually."
        )

        vm.rehabPlan = plan
        XCTAssertEqual(vm.rehabPlan?.exercises.count, 1)
        XCTAssertEqual(vm.rehabPlan?.exercises.first?.name, "Wall Sits")
        XCTAssertEqual(vm.rehabPlan?.exercises.first?.difficulty, .intermediate)
        XCTAssertEqual(vm.rehabPlan?.totalWeeks, 6)
        XCTAssertEqual(vm.rehabPlan?.notes, "Progress gradually.")
    }

    func testSavingStateFlags() {
        let vm = RehabPlanViewModel()

        // Simulate saving states
        vm.isSaving = true
        XCTAssertTrue(vm.isSaving)

        vm.isSaving = false
        vm.showSaveSuccess = true
        XCTAssertTrue(vm.showSaveSuccess)

        vm.showSaveSuccess = false
        vm.saveError = "Network error"
        XCTAssertEqual(vm.saveError, "Network error")
    }

    func testGeneratingStateFlags() {
        let vm = RehabPlanViewModel()

        vm.isGenerating = true
        XCTAssertTrue(vm.isGenerating)

        vm.isGenerating = false
        vm.generationError = "API error"
        XCTAssertEqual(vm.generationError, "API error")
    }
}

// MARK: - OnboardingViewModel Tests (non-Firebase parts)

final class OnboardingViewModelTests: XCTestCase {

    /// Helper to fill in valid step 1 data so nextStep() can proceed
    private func fillValidBasicInfo(_ vm: OnboardingViewModel) {
        vm.userProfile.firstName = "Test"
        vm.userProfile.lastName = "User"
        vm.userProfile.sex = "Male"
        vm.userProfile.heightFeet = 5
        vm.userProfile.heightInches = 10
        vm.userProfile.weight = 175
    }

    /// Helper to fill valid step 5 data
    private func fillValidActivityLevel(_ vm: OnboardingViewModel) {
        vm.userProfile.activityLevel = "Active"
    }

    func testInitialStep() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.currentStep, 1)
    }

    func testNextStep_BlockedWithoutValidation() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.currentStep, 1)

        // Try to advance without filling in required fields
        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 1, "Should not advance without valid basic info")
    }

    func testNextStep_AdvancesWithValidData() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)

        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 2)

        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 3)
    }

    func testNextStep_DoesNotExceedMax() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)

        // Advance to step 6 (max)
        for _ in 1..<6 {
            vm.nextStep()
        }
        XCTAssertEqual(vm.currentStep, 6)

        // Try to go past max
        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 6, "Should not exceed step 6")
    }

    func testPreviousStep_DecreasesStep() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        vm.nextStep()
        vm.nextStep()
        XCTAssertEqual(vm.currentStep, 3)

        vm.previousStep()
        XCTAssertEqual(vm.currentStep, 2)
    }

    func testPreviousStep_DoesNotGoBelowOne() {
        let vm = OnboardingViewModel()
        XCTAssertEqual(vm.currentStep, 1)

        vm.previousStep()
        XCTAssertEqual(vm.currentStep, 1, "Should not go below step 1")
    }

    func testFullStepNavigation() {
        let vm = OnboardingViewModel()
        fillValidBasicInfo(vm)
        fillValidActivityLevel(vm)

        // Walk through all steps forward
        for expectedStep in 2...6 {
            vm.nextStep()
            XCTAssertEqual(vm.currentStep, expectedStep)
        }

        // Walk back to step 1
        for expectedStep in stride(from: 5, through: 1, by: -1) {
            vm.previousStep()
            XCTAssertEqual(vm.currentStep, expectedStep)
        }
    }

    func testCanProceedFromStep1_RequiresAllFields() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Empty profile should not pass validation")

        vm.userProfile.firstName = "Test"
        XCTAssertFalse(vm.canProceedFromCurrentStep, "Missing last name, sex, weight")

        vm.userProfile.lastName = "User"
        vm.userProfile.sex = "Male"
        vm.userProfile.heightFeet = 5
        vm.userProfile.weight = 175
        XCTAssertTrue(vm.canProceedFromCurrentStep, "All required fields filled")
    }

    func testUserProfileModification() {
        let vm = OnboardingViewModel()

        vm.userProfile.firstName = "Jane"
        vm.userProfile.lastName = "Smith"
        vm.userProfile.sex = "Female"
        vm.userProfile.heightFeet = 5
        vm.userProfile.heightInches = 6
        vm.userProfile.weight = 135
        vm.userProfile.activityLevel = "Very Active"
        vm.userProfile.primarySport = "Running"
        vm.userProfile.medicalConditions = ["Asthma"]

        XCTAssertEqual(vm.userProfile.firstName, "Jane")
        XCTAssertEqual(vm.userProfile.lastName, "Smith")
        XCTAssertEqual(vm.userProfile.sex, "Female")
        XCTAssertEqual(vm.userProfile.heightFeet, 5)
        XCTAssertEqual(vm.userProfile.heightInches, 6)
        XCTAssertEqual(vm.userProfile.weight, 135)
        XCTAssertEqual(vm.userProfile.activityLevel, "Very Active")
        XCTAssertEqual(vm.userProfile.primarySport, "Running")
        XCTAssertEqual(vm.userProfile.medicalConditions, ["Asthma"])
    }

    func testUserProfileSurgeriesAndInjuries() {
        let vm = OnboardingViewModel()

        vm.userProfile.surgeries = [
            UserProfile.Surgery(name: "ACL Repair", year: 2020),
            UserProfile.Surgery(name: "Meniscus Repair", year: 2022)
        ]
        vm.userProfile.injuries = [
            UserProfile.Injury(bodyArea: "Right Knee", description: "ACL tear", isCurrent: false),
            UserProfile.Injury(bodyArea: "Lower Back", description: "Disc herniation", isCurrent: true)
        ]

        XCTAssertEqual(vm.userProfile.surgeries.count, 2)
        XCTAssertEqual(vm.userProfile.injuries.count, 2)

        let currentInjuries = vm.userProfile.injuries.filter { $0.isCurrent }
        XCTAssertEqual(currentInjuries.count, 1)
        XCTAssertEqual(currentInjuries.first?.bodyArea, "Lower Back")
    }
}

// MARK: - BodyMapViewModel Tests (non-Firebase parts)

final class BodyMapViewModelTests: XCTestCase {

    // Note: BodyMapViewModel calls Firebase in init(), so we test
    // properties/methods on a fresh instance where Firebase is not authenticated.

    func testInitialSideIsFront() {
        let vm = BodyMapViewModel()
        XCTAssertEqual(vm.currentSide, .front)
    }

    func testRegionsAreLoaded() {
        let vm = BodyMapViewModel()
        XCTAssertFalse(vm.regions.isEmpty, "Regions should be loaded on init")
        // We know the body map has 17 regions from the source
        XCTAssertEqual(vm.regions.count, 17, "Should have 17 body regions")
    }

    func testAllRegionsStartUnselected() {
        let vm = BodyMapViewModel()
        XCTAssertTrue(vm.regions.allSatisfy { !$0.isSelected }, "All regions should start unselected")
    }

    func testSelectedRegionsInitiallyEmpty() {
        let vm = BodyMapViewModel()
        XCTAssertTrue(vm.selectedRegions.isEmpty, "No regions should be selected initially")
    }

    func testToggleSelection() {
        let vm = BodyMapViewModel()
        let firstRegion = vm.regions[0]
        XCTAssertFalse(firstRegion.isSelected)

        vm.toggleSelection(for: firstRegion)
        XCTAssertTrue(vm.regions[0].isSelected)
        XCTAssertEqual(vm.selectedRegions.count, 1)

        // Toggle back off
        vm.toggleSelection(for: vm.regions[0])
        XCTAssertFalse(vm.regions[0].isSelected)
        XCTAssertTrue(vm.selectedRegions.isEmpty)
    }

    func testToggleMultipleRegions() {
        let vm = BodyMapViewModel()

        // Select first 3 regions
        for i in 0..<3 {
            vm.toggleSelection(for: vm.regions[i])
        }
        XCTAssertEqual(vm.selectedRegions.count, 3)
    }

    func testClearAll() {
        let vm = BodyMapViewModel()

        // Select several regions
        for i in 0..<5 {
            vm.toggleSelection(for: vm.regions[i])
        }
        XCTAssertEqual(vm.selectedRegions.count, 5)

        vm.clearAll()
        XCTAssertTrue(vm.selectedRegions.isEmpty, "All selections should be cleared")
        XCTAssertTrue(vm.regions.allSatisfy { !$0.isSelected })
    }

    func testRegionsForCurrentSide_Front() {
        let vm = BodyMapViewModel()
        vm.currentSide = .front

        let frontRegions = vm.regionsForCurrentSide
        XCTAssertFalse(frontRegions.isEmpty)

        // All returned regions should include .front in their sides
        for region in frontRegions {
            XCTAssertTrue(region.sides.contains(.front), "\(region.name) should be on the front side")
        }
    }

    func testRegionsForCurrentSide_Back() {
        let vm = BodyMapViewModel()
        vm.currentSide = .back

        let backRegions = vm.regionsForCurrentSide
        XCTAssertFalse(backRegions.isEmpty)

        // All returned regions should include .back in their sides
        for region in backRegions {
            XCTAssertTrue(region.sides.contains(.back), "\(region.name) should be on the back side")
        }
    }

    func testFrontOnlyRegionsNotOnBack() {
        let vm = BodyMapViewModel()

        // "Chest" and "Abdomen" should be front-only
        let chest = vm.regions.first(where: { $0.name == "Chest" })
        XCTAssertNotNil(chest)
        XCTAssertTrue(chest!.sides.contains(.front))
        XCTAssertFalse(chest!.sides.contains(.back))

        let abdomen = vm.regions.first(where: { $0.name == "Abdomen" })
        XCTAssertNotNil(abdomen)
        XCTAssertTrue(abdomen!.sides.contains(.front))
        XCTAssertFalse(abdomen!.sides.contains(.back))
    }

    func testBackOnlyRegionsNotOnFront() {
        let vm = BodyMapViewModel()

        let upperBack = vm.regions.first(where: { $0.name == "Upper Back" })
        XCTAssertNotNil(upperBack)
        XCTAssertFalse(upperBack!.sides.contains(.front))
        XCTAssertTrue(upperBack!.sides.contains(.back))

        let lowerBack = vm.regions.first(where: { $0.name == "Lower Back" })
        XCTAssertNotNil(lowerBack)
        XCTAssertFalse(lowerBack!.sides.contains(.front))
        XCTAssertTrue(lowerBack!.sides.contains(.back))
    }

    func testBothSideRegions() {
        let vm = BodyMapViewModel()

        // Knees, shoulders, etc. should appear on both sides
        let rightKnee = vm.regions.first(where: { $0.name == "Right Knee" })
        XCTAssertNotNil(rightKnee)
        XCTAssertTrue(rightKnee!.sides.contains(.front))
        XCTAssertTrue(rightKnee!.sides.contains(.back))
    }

    func testRegionNamesAreUnique() {
        let vm = BodyMapViewModel()
        let names = vm.regions.map { $0.name }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "All region names should be unique")
    }

    func testRegionZoneKeysAreUnique() {
        let vm = BodyMapViewModel()
        let keys = vm.regions.map { $0.zoneKey }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "All zone keys should be unique")
    }
}
