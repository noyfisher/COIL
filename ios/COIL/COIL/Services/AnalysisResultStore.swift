import Foundation

/// Persists the last AnalysisResult so the dashboard can display it across sessions.
///
/// The result contains PHI (condition differentials, confidences, pain assessments,
/// and a full UserProfile snapshot), so it is stored as a file with
/// `.completeFileProtection` — encrypted at rest while the device is locked and
/// excluded from unencrypted backups — rather than in UserDefaults. A one-time
/// migration moves any value left in the legacy UserDefaults key.
@MainActor
class AnalysisResultStore: ObservableObject {
    static let shared = AnalysisResultStore()

    @Published var lastResult: AnalysisResult?

    /// Legacy UserDefaults key (pre-file-protection). Read once for migration, then removed.
    private let legacyKey = "dashboardLastAnalysisResult"

    private var fileURL: URL {
        let dir = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("dashboardLastAnalysisResult.json")
    }

    init() {
        load()
    }

    func save(_ result: AnalysisResult) {
        lastResult = result
        guard let data = try? JSONEncoder().encode(result) else { return }
        var url = fileURL
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    func load() {
        // Migrate once from the legacy UserDefaults blob, if present.
        if let legacy = UserDefaults.standard.data(forKey: legacyKey) {
            try? legacy.write(to: fileURL, options: [.atomic, .completeFileProtection])
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
        guard let data = try? Data(contentsOf: fileURL),
              let result = try? JSONDecoder().decode(AnalysisResult.self, from: data) else {
            return
        }
        lastResult = result
    }

    func clear() {
        lastResult = nil
        try? FileManager.default.removeItem(at: fileURL)
        UserDefaults.standard.removeObject(forKey: legacyKey) // clear any legacy remnant
    }
}
