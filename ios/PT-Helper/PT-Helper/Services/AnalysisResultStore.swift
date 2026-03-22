import Foundation

/// Persists the last AnalysisResult so the dashboard can display it across sessions.
@MainActor
class AnalysisResultStore: ObservableObject {
    static let shared = AnalysisResultStore()

    @Published var lastResult: AnalysisResult?

    private let key = "dashboardLastAnalysisResult"

    init() {
        load()
    }

    func save(_ result: AnalysisResult) {
        lastResult = result
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            return
        }
        lastResult = result
    }

    func clear() {
        lastResult = nil
        UserDefaults.standard.removeObject(forKey: key)
    }
}
