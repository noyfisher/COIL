import XCTest
@testable import PT_Helper

// MARK: - RehabPlanViewModel Tests

@MainActor
final class RehabPlanViewModelTests: XCTestCase {

    // MARK: - Initial State

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
        let plan = TestFixtures.makePlan(name: "Test Plan")

        vm.rehabPlan = plan
        XCTAssertNotNil(vm.rehabPlan)
        XCTAssertEqual(vm.rehabPlan?.planName, "Test Plan")
    }

    func testRehabPlanWithExercises() {
        let vm = RehabPlanViewModel()
        let exercise = TestFixtures.makeExercise(name: "Wall Sits", difficulty: .intermediate)
        let plan = TestFixtures.makePlan(
            name: "Knee Rehab Plan",
            conditions: ["Patellofemoral Pain Syndrome"],
            exercises: [exercise],
            totalWeeks: 6
        )

        vm.rehabPlan = plan
        XCTAssertEqual(vm.rehabPlan?.exercises.count, 1)
        XCTAssertEqual(vm.rehabPlan?.exercises.first?.name, "Wall Sits")
        XCTAssertEqual(vm.rehabPlan?.exercises.first?.difficulty, .intermediate)
        XCTAssertEqual(vm.rehabPlan?.totalWeeks, 6)
    }

    func testSavingStateFlags() {
        let vm = RehabPlanViewModel()

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

    // MARK: - buildRehabUserMessage Tests

    func testBuildRehabUserMessage_containsProfile() {
        let vm = RehabPlanViewModel()
        let result = TestFixtures.makeAnalysisResult()

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("PATIENT PROFILE:"))
        XCTAssertTrue(message.contains("Age: 30"))
        XCTAssertTrue(message.contains("Activity Level: Moderate"))
    }

    func testBuildRehabUserMessage_containsConditions() {
        let vm = RehabPlanViewModel()
        let condition = TestFixtures.makeCondition(name: "Patellofemoral Pain Syndrome", confidence: 75)
        let result = TestFixtures.makeAnalysisResult(conditions: [condition])

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("IDENTIFIED CONDITIONS:"))
        XCTAssertTrue(message.contains("Patellofemoral Pain Syndrome"))
        XCTAssertTrue(message.contains("75%"))
    }

    func testBuildRehabUserMessage_includesMedications() {
        let vm = RehabPlanViewModel()
        let profile = TestFixtures.makeProfile(medications: ["Blood Thinners"])
        let result = TestFixtures.makeAnalysisResult(profile: profile)

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("Current Medications: Blood Thinners"))
    }

    func testBuildRehabUserMessage_includesRelevantSurgery() {
        let vm = RehabPlanViewModel()
        let surgery = UserProfile.Surgery(
            name: "ACL Reconstruction", year: 2024,
            bodyArea: "Right Knee",
            recoveryStatus: "Still recovering"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let result = TestFixtures.makeAnalysisResult(profile: profile)

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("SURGICAL HISTORY"))
        XCTAssertTrue(message.contains("ACL Reconstruction"))
    }

    func testBuildRehabUserMessage_activeRestrictions_ownSection() {
        let vm = RehabPlanViewModel()
        let surgery = UserProfile.Surgery(
            name: "Spinal Fusion", year: 2023,
            bodyArea: "Lower Back",
            recoveryStatus: "Have restrictions",
            restrictions: "No heavy lifting"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Lower Back", zoneKey: "lower_back")
        )
        let result = TestFixtures.makeAnalysisResult(profile: profile, assessments: [assessment])

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("ACTIVE POST-SURGICAL RESTRICTIONS:"))
        XCTAssertTrue(message.contains("No heavy lifting"))
    }

    func testBuildRehabUserMessage_endsWithPlanRequest() {
        let vm = RehabPlanViewModel()
        let result = TestFixtures.makeAnalysisResult()

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("create a personalized rehabilitation exercise plan"))
    }

    func testBuildRehabUserMessage_equipmentConstraintHeader_present() {
        let vm = RehabPlanViewModel()
        let result = TestFixtures.makeAnalysisResult()

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("STRICT CONSTRAINTS"), "Equipment preference header must use strict constraint language")
        XCTAssertTrue(message.contains("select ONLY exercises that require this equipment level or less"), "Equipment line must include enforcement directive")
    }

    func testBuildRehabUserMessage_equipmentConstraint_reflectsSelection() {
        let vm = RehabPlanViewModel()
        vm.preferences.equipment = .fullGym
        let result = TestFixtures.makeAnalysisResult()

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("Full gym"), "Message must reflect selected equipment tier")
        XCTAssertFalse(message.contains("No equipment"), "Message must not contain default equipment when overridden")
    }

    // MARK: - Async Generation Tests (with MockClaudeAPIService)

    func testGenerateRehabPlan_setsIsGenerating() {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeRehabPlanResponseJSON()
        let vm = RehabPlanViewModel(apiService: mock)
        let result = TestFixtures.makeAnalysisResult()

        vm.generateRehabPlan(from: result)

        XCTAssertTrue(vm.isGenerating, "Should be generating immediately after call")
    }

    func testGenerateRehabPlan_success_populatesPlan() async throws {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeRehabPlanResponseJSON(planName: "AI Knee Plan", exerciseCount: 3)
        let vm = RehabPlanViewModel(apiService: mock)
        let result = TestFixtures.makeAnalysisResult()

        vm.generateRehabPlan(from: result)

        // Wait for the internal Task to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(vm.isGenerating)
        XCTAssertNil(vm.generationError)
        XCTAssertNotNil(vm.rehabPlan)
        XCTAssertEqual(vm.rehabPlan?.planName, "AI Knee Plan")
        XCTAssertEqual(vm.rehabPlan?.exercises.count, 3)
    }

    func testGenerateRehabPlan_success_callsAPIWithCorrectType() async throws {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeRehabPlanResponseJSON()
        let vm = RehabPlanViewModel(apiService: mock)
        let result = TestFixtures.makeAnalysisResult()

        vm.generateRehabPlan(from: result)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(mock.sendMessageCallCount, 1)
        XCTAssertEqual(mock.lastRequestType, .rehab_plan)
        XCTAssertNotNil(mock.lastUserMessage)
    }

    func testGenerateRehabPlan_apiError_fallsBackToExercises() async throws {
        let mock = MockClaudeAPIService()
        mock.errorToThrow = ClaudeAPIError.rateLimited
        let vm = RehabPlanViewModel(apiService: mock)
        let condition = TestFixtures.makeCondition(name: "Patellofemoral Pain Syndrome")
        let result = TestFixtures.makeAnalysisResult(conditions: [condition])

        vm.generateRehabPlan(from: result)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(vm.isGenerating)
        // Should have a fallback plan (either from exerciseDatabase or region-aware fallback)
        XCTAssertNotNil(vm.rehabPlan, "Should fallback to hardcoded exercises on API error")
    }

    func testGenerateRehabPlan_apiError_unknownCondition_usesRegionAwareFallback() async throws {
        let mock = MockClaudeAPIService()
        mock.errorToThrow = ClaudeAPIError.networkError(NSError(domain: "", code: -1))
        let vm = RehabPlanViewModel(apiService: mock)
        let condition = TestFixtures.makeCondition(name: "Rare Unknown Condition")
        let result = TestFixtures.makeAnalysisResult(conditions: [condition])

        vm.generateRehabPlan(from: result)
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertFalse(vm.isGenerating)
        XCTAssertNotNil(vm.rehabPlan, "Should fallback to region-aware exercises")
        XCTAssertGreaterThan(vm.rehabPlan?.exercises.count ?? 0, 0)
    }

    func testGenerateRehabPlan_validationWarnings_populated() async throws {
        let mock = MockClaudeAPIService()
        mock.responseToReturn = TestFixtures.makeRehabPlanResponseJSON()
        let vm = RehabPlanViewModel(apiService: mock)
        let result = TestFixtures.makeAnalysisResult()

        vm.generateRehabPlan(from: result)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Warnings array should exist (may be empty for valid plans)
        XCTAssertNotNil(vm.rehabPlanWarnings)
    }

    // MARK: - Prompt Builder Tests (New Health Fields)

    func testBuildRehabUserMessage_includesDominantSide() {
        let vm = RehabPlanViewModel()
        let profile = TestFixtures.makeProfile(dominantSide: "Right")
        let result = TestFixtures.makeAnalysisResult(profile: profile)

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("Dominant Side: Right"))
    }

    func testBuildRehabUserMessage_includesMedicationHistory() {
        let vm = RehabPlanViewModel()
        let change = TestFixtures.makeMedicationChange(medication: "Ibuprofen", action: "started")
        let profile = TestFixtures.makeProfile(medicationHistory: [change])
        let result = TestFixtures.makeAnalysisResult(profile: profile)

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("MEDICATION HISTORY:"))
        XCTAssertTrue(message.contains("Started Ibuprofen"))
    }

    func testBuildRehabUserMessage_includesSurgeryType() {
        let vm = RehabPlanViewModel()
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            surgeryType: "Arthroscopic with graft",
            causingInjury: "Basketball injury"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )
        let result = TestFixtures.makeAnalysisResult(profile: profile, assessments: [assessment])

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("[Type: Arthroscopic with graft]"))
        XCTAssertTrue(message.contains("[Caused by: Basketball injury]"))
    }

    func testBuildRehabUserMessage_includesHardwareInfo() {
        let vm = RehabPlanViewModel()
        let surgery = TestFixtures.makeSurgery(
            name: "ACL Repair",
            hasHardware: true,
            hardwareDetails: "Two titanium screws"
        )
        let profile = TestFixtures.makeProfile(surgeries: [surgery])
        let assessment = TestFixtures.makeAssessment(
            region: TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee")
        )
        let result = TestFixtures.makeAnalysisResult(profile: profile, assessments: [assessment])

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertTrue(message.contains("[Hardware present: Two titanium screws]"))
    }

    func testBuildRehabUserMessage_noDominantSide_omitted() {
        let vm = RehabPlanViewModel()
        let profile = TestFixtures.makeProfile(dominantSide: nil)
        let result = TestFixtures.makeAnalysisResult(profile: profile)

        let message = vm.buildRehabUserMessage(from: result)

        XCTAssertFalse(message.contains("Dominant Side"))
    }
}

// MARK: - Medication Diff Tests

@MainActor
final class MedicationDiffTests: XCTestCase {

    func testUpdateMedicationHistory_addNewMed_createsStartedEntry() {
        let vm = OnboardingViewModel()
        vm.userProfile.medications = ["Ibuprofen"]

        vm.updateMedicationHistory(previousMedications: nil)

        XCTAssertEqual(vm.userProfile.medicationHistory?.count, 1)
        XCTAssertEqual(vm.userProfile.medicationHistory?[0].medication, "Ibuprofen")
        XCTAssertEqual(vm.userProfile.medicationHistory?[0].action, "started")
    }

    func testUpdateMedicationHistory_removeMed_createsStoppedEntry() {
        let vm = OnboardingViewModel()
        vm.userProfile.medications = nil

        vm.updateMedicationHistory(previousMedications: ["Blood Thinners"])

        XCTAssertEqual(vm.userProfile.medicationHistory?.count, 1)
        XCTAssertEqual(vm.userProfile.medicationHistory?[0].medication, "Blood Thinners")
        XCTAssertEqual(vm.userProfile.medicationHistory?[0].action, "stopped")
    }

    func testUpdateMedicationHistory_noChange_noNewEntries() {
        let vm = OnboardingViewModel()
        vm.userProfile.medications = ["Ibuprofen"]

        vm.updateMedicationHistory(previousMedications: ["Ibuprofen"])

        // Should be nil or empty since no changes
        let count = vm.userProfile.medicationHistory?.count ?? 0
        XCTAssertEqual(count, 0)
    }

    func testUpdateMedicationHistory_multipleChanges() {
        let vm = OnboardingViewModel()
        vm.userProfile.medications = ["Ibuprofen", "Tylenol"]

        vm.updateMedicationHistory(previousMedications: ["Blood Thinners", "Ibuprofen"])

        // Blood Thinners removed (stopped), Tylenol added (started), Ibuprofen unchanged
        let history = vm.userProfile.medicationHistory ?? []
        XCTAssertEqual(history.count, 2)

        let actions = Set(history.map { "\($0.action):\($0.medication)" })
        XCTAssertTrue(actions.contains("started:Tylenol"))
        XCTAssertTrue(actions.contains("stopped:Blood Thinners"))
    }

    func testUpdateMedicationHistory_appendsToExistingHistory() {
        let vm = OnboardingViewModel()
        let existingChange = UserProfile.MedicationChange(
            medication: "OldMed", action: "stopped", date: Date().addingTimeInterval(-86400)
        )
        vm.userProfile.medicationHistory = [existingChange]
        vm.userProfile.medications = ["NewMed"]

        vm.updateMedicationHistory(previousMedications: nil)

        XCTAssertEqual(vm.userProfile.medicationHistory?.count, 2, "Should append to existing history")
        XCTAssertEqual(vm.userProfile.medicationHistory?[0].medication, "OldMed")
        XCTAssertEqual(vm.userProfile.medicationHistory?[1].medication, "NewMed")
    }
}
