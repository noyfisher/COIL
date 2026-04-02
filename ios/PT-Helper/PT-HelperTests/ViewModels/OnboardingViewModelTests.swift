import XCTest
@testable import PT_Helper

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
        vm.hasAcceptedTerms = true
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
