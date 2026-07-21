import Foundation

/// Persistent store for per-plan acknowledgement of `.serious` validation warnings.
///
/// When a rehab / wellness plan contains a `.serious` finding (contraindication,
/// osteoporosis + impact, blood-thinners + balance, etc.) the user sees a
/// `SeriousWarningModal` blocking the plan. Once they tap "I've read this &
/// accept", we persist the planId here so the modal doesn't re-fire on every
/// subsequent plan open.
///
/// Note: `@AppStorage` does not accept dynamic string-interpolated keys, so we
/// store a single JSON-encoded `[String]` under a fixed key and check
/// membership imperatively.
enum SeriousWarningAcknowledgements {
    private static let key = "acknowledgedSeriousWarnings"

    static func isAcknowledged(planId: String) -> Bool {
        loadSet().contains(planId)
    }

    static func acknowledge(planId: String) {
        var set = loadSet()
        set.insert(planId)
        save(set)
    }

    /// Test/debug helper — clears all acknowledgements.
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func loadSet() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private static func save(_ set: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(set).sorted()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
