import Foundation

private let savedBodyRiskResultKey = "SavedBodyRiskResult"

@MainActor
final class BodyRiskViewModel: ObservableObject {

    // MARK: - Form State

    @Published var primaryActivity: PrimaryActivity = .deskWork
    @Published var hoursSeated: Double = 8
    @Published var sportOrHobby: String = ""

    // MARK: - Analysis State

    @Published var isAnalyzing = false
    @Published var result: BodyRiskResult?
    @Published var error: String?

    // MARK: - Init

    init() {
        loadPersistedResult()
    }

    // MARK: - Analysis

    func analyze(profile: UserProfile, apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) async {
        isAnalyzing = true
        error = nil

        let assessment = BodyRiskAssessment(
            primaryActivity: primaryActivity,
            hoursSeatedPerDay: hoursSeated,
            dominantSportOrHobby: sportOrHobby.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : sportOrHobby.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            let validated = try await BodyRiskAnalyzer.analyze(
                assessment: assessment,
                profile: profile,
                apiService: apiService
            )
            result = validated.result
            persistResult(validated.result)
            SessionLogger.shared.log(.stateUpdated, category: .api,
                                      message: "Body risk assessment completed",
                                      metadata: ["regionCount": "\(validated.result.riskRegions.count)"])
        } catch {
            self.error = error.localizedDescription
            SessionLogger.shared.log(.errorOccurred, category: .error,
                                      message: "Body risk assessment failed",
                                      metadata: ["error": error.localizedDescription])
        }

        isAnalyzing = false
    }

    func reset() {
        result = nil
        error = nil
        primaryActivity = .deskWork
        hoursSeated = 8
        sportOrHobby = ""
        UserDefaults.standard.removeObject(forKey: savedBodyRiskResultKey)
    }

    // MARK: - Persistence

    private func persistResult(_ result: BodyRiskResult) {
        guard let data = try? JSONEncoder().encode(result) else { return }
        UserDefaults.standard.set(data, forKey: savedBodyRiskResultKey)
    }

    private func loadPersistedResult() {
        guard let data = UserDefaults.standard.data(forKey: savedBodyRiskResultKey),
              let saved = try? JSONDecoder().decode(BodyRiskResult.self, from: data) else { return }
        result = saved
    }
}
