import XCTest
@testable import COIL

@MainActor
final class WellnessPlanViewModelTests: XCTestCase {
    private var mockAPI: MockClaudeAPIService!

    override func setUp() {
        super.setUp()
        mockAPI = MockClaudeAPIService()
    }

    // MARK: - Init State

    func testInit_defaultState() {
        let vm = WellnessPlanViewModel(apiService: mockAPI)
        XCTAssertNil(vm.wellnessPlan)
        XCTAssertFalse(vm.isGenerating)
        XCTAssertNil(vm.generationError)
        XCTAssertFalse(vm.isSaving)
        XCTAssertEqual(vm.verifiedCount, 0)
        XCTAssertEqual(vm.flaggedCount, 0)
        XCTAssertEqual(vm.totalExerciseCount, 0)
    }

    // MARK: - buildWellnessPlanUserMessage

    func testBuildMessage_includesAge() {
        let vm = WellnessPlanViewModel(apiService: mockAPI)
        let result = TestFixtures.makeWellnessAnalysisResult(
            profile: TestFixtures.makeProfile(age: 45)
        )
        let message = vm.buildWellnessPlanUserMessage(from: result)
        XCTAssertTrue(message.contains("45"), "Message should include patient age")
    }

    func testBuildMessage_includesSurgicalHistory() {
        let vm = WellnessPlanViewModel(apiService: mockAPI)
        let profile = TestFixtures.makeProfile(
            surgeries: [TestFixtures.makeSurgery(name: "ACL Reconstruction", year: 2023)]
        )
        let result = TestFixtures.makeWellnessAnalysisResult(profile: profile)
        let message = vm.buildWellnessPlanUserMessage(from: result)
        XCTAssertTrue(message.contains("ACL Reconstruction"), "Message should include surgical history")
        XCTAssertTrue(message.contains("2023"))
    }

    func testBuildMessage_includesRecommendations() {
        let vm = WellnessPlanViewModel(apiService: mockAPI)
        let rec = TestFixtures.makeWellnessRecommendation(title: "Core Strengthening Plan")
        let result = TestFixtures.makeWellnessAnalysisResult(recommendations: [rec])
        let message = vm.buildWellnessPlanUserMessage(from: result)
        XCTAssertTrue(message.contains("Core Strengthening Plan"), "Message should include recommendation titles")
    }

    func testBuildMessage_includesPreferences() {
        let vm = WellnessPlanViewModel(apiService: mockAPI)
        let result = TestFixtures.makeWellnessAnalysisResult()
        let message = vm.buildWellnessPlanUserMessage(from: result)
        XCTAssertTrue(message.contains("USER PREFERENCES"), "Message should include preferences section")
        XCTAssertTrue(message.contains("Equipment"), "Message should include equipment preference")
        XCTAssertTrue(message.contains("Session Length"), "Message should include session length")
    }

    func testBuildMessage_includesCurrentInjuries_excludesPast() {
        let vm = WellnessPlanViewModel(apiService: mockAPI)
        let profile = TestFixtures.makeProfile(
            injuries: [
                UserProfile.Injury(bodyArea: "Right Knee", description: "ACL sprain", isCurrent: true, year: 2024, recoveryStatus: "Recovering"),
                UserProfile.Injury(bodyArea: "Left Ankle", description: "Old sprain", isCurrent: false, year: 2018, recoveryStatus: nil)
            ]
        )
        let result = TestFixtures.makeWellnessAnalysisResult(profile: profile)
        let message = vm.buildWellnessPlanUserMessage(from: result)
        XCTAssertTrue(message.contains("ACL sprain"), "Should include current injury")
        XCTAssertFalse(message.contains("Old sprain"), "Should not include past injury")
    }

    // MARK: - WS8-01: Offline uses the local fallback plan

    /// Unlike the other WS8-01 offline guards, this VM has a genuine
    /// network-free fallback plan — offline must route straight to it
    /// instead of surfacing an error and losing a feature that already
    /// worked offline.
    func testGenerateWellnessPlan_offline_appliesFallbackPlanWithoutAPICall() async {
        _ = NetworkMonitor.shared
        await Task.yield()
        NetworkMonitor.shared.isConnected = false
        defer { NetworkMonitor.shared.isConnected = true }

        let vm = WellnessPlanViewModel(apiService: mockAPI)
        let result = TestFixtures.makeWellnessAnalysisResult()

        vm.generateWellnessPlan(from: result)

        // The offline fallback now runs validation off the main actor
        // (WS11-01's Task.detached), so it's no longer synchronous — poll
        // briefly for it to land.
        for _ in 0..<50 where vm.wellnessPlan == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertNil(vm.generationError)
        XCTAssertFalse(vm.isGenerating)
        XCTAssertNotNil(vm.wellnessPlan, "Offline should still produce the local fallback plan")
        XCTAssertGreaterThan(vm.wellnessPlan?.exercises.count ?? 0, 0)
        XCTAssertEqual(mockAPI.sendMessageCallCount, 0, "Offline must never attempt the API call")
    }
}
