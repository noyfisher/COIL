import Foundation

/// Single source of truth for UserDefaults/@AppStorage keys that are
/// referenced from more than one file ("PR-5" from the SettingsView comment).
/// Values are frozen — changing one orphans users' stored state.
enum AppStorageKeys {
    static let hasSeenMinorSafetyScreen = "hasSeenMinorSafetyScreen"
    static let pendingMinorSafetyScreen = "pendingMinorSafetyScreen"
    static let hasSeenBodyMapCoach = "hasSeenBodyMapCoach"
}
