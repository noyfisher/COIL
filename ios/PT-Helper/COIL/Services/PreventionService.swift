import Foundation

/// Owns all local persistence for the "Today's Prevention" feature — profile,
/// daily check-ins, completions, feedback — behind 4 well-defined UserDefaults
/// keys so views never touch UserDefaults directly (`RehabPlanViewModel`'s
/// singleton/init style, `NotificationService`'s persistence style).
///
/// Fully local/deterministic for this MVP: no Firestore, no AI call. Routine
/// generation itself is delegated to `PreventionRoutineEngine`.
@MainActor
final class PreventionService: ObservableObject {
    static let shared = PreventionService()

    static let profileKey = "prevention.profile.v1"
    static let checkInsKey = "prevention.checkIns.v1"
    static let completionsKey = "prevention.completions.v1"
    static let feedbackKey = "prevention.feedback.v1"

    /// Bounds UserDefaults growth for long-term users.
    static let historyRetentionDays = 90

    private let defaults: UserDefaults

    @Published private(set) var profile: PreventionProfile
    @Published private(set) var checkIns: [String: DailyPreventionCheckIn]
    @Published private(set) var completions: [PreventionCompletion]
    @Published private(set) var feedback: [PreventionFeedback]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.profile = Self.decode(PreventionProfile.self, from: defaults, key: Self.profileKey) ?? .defaultProfile
        self.checkIns = Self.decode([String: DailyPreventionCheckIn].self, from: defaults, key: Self.checkInsKey) ?? [:]
        self.completions = Self.decode([PreventionCompletion].self, from: defaults, key: Self.completionsKey) ?? []
        self.feedback = Self.decode([PreventionFeedback].self, from: defaults, key: Self.feedbackKey) ?? []
    }

    // MARK: - Profile

    func saveProfile(_ newProfile: PreventionProfile) {
        var updated = newProfile
        updated.hasCompletedSetup = true
        updated.lastUpdated = Date()
        profile = updated
        encode(updated, key: Self.profileKey)
        AnalyticsService.shared.log(.preventionProfileSaved, parameters: [
            "focus": updated.focus.rawValue,
            "length_minutes": updated.preferredLength.rawValue
        ])
    }

    // MARK: - Check-In

    func checkIn(for dateKey: String = PreventionDateKey.key()) -> DailyPreventionCheckIn? {
        checkIns[dateKey]
    }

    func submitCheckIn(_ checkIn: DailyPreventionCheckIn) {
        checkIns[checkIn.dateKey] = checkIn
        encode(checkIns, key: Self.checkInsKey)
        AnalyticsService.shared.log(.preventionCheckInCompleted, parameters: [
            "context": checkIn.context.rawValue,
            "length_minutes": checkIn.length.rawValue
        ])
        if checkIn.hasNewOrWorseningSymptoms {
            AnalyticsService.shared.log(.preventionSymptomsFlagged)
        }
    }

    // MARK: - Routine

    /// Builds (does not persist) today's routine via the deterministic engine.
    /// Returns `nil` both when there's no check-in yet AND when the check-in
    /// flags symptoms — callers must inspect `checkIn(for:)` separately to
    /// distinguish "needs check-in" from "safety hold" before rendering.
    func routine(activePlan: RehabPlan?, healthProfile: UserProfile?, referenceDate: Date = Date()) -> DailyPreventionRoutine? {
        guard let today = checkIn(for: PreventionDateKey.key(for: referenceDate)) else { return nil }
        return PreventionRoutineEngine.selectRoutine(
            profile: profile,
            checkIn: today,
            healthProfile: healthProfile,
            activePlan: activePlan,
            recentFeedback: recentFeedback(days: 14, before: referenceDate),
            referenceDate: referenceDate
        )
    }

    // MARK: - Completion + Feedback

    func recordCompletion(_ completion: PreventionCompletion) {
        completions.append(completion)
        prune()
        encode(completions, key: Self.completionsKey)
        AnalyticsService.shared.log(.preventionRoutineCompleted, parameters: [
            "minutes": completion.minutes,
            "category_count": completion.categories.count,
            "included_micro_action": completion.includedMicroAction
        ])
    }

    func recordFeedback(_ newFeedback: PreventionFeedback) {
        feedback.append(newFeedback)
        prune()
        encode(feedback, key: Self.feedbackKey)
    }

    func recentFeedback(days: Int, before referenceDate: Date = Date()) -> [PreventionFeedback] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) else { return feedback }
        return feedback.filter { $0.submittedDate >= cutoff }
    }

    // MARK: - Weekly Review

    func weeklyReview(referenceDate: Date = Date()) -> PreventionWeeklyReview {
        PreventionWeeklyReviewEngine.buildReview(completions: completions, feedback: feedback, referenceDate: referenceDate)
    }

    // MARK: - History Pruning

    private func prune() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -Self.historyRetentionDays, to: Date()) else { return }
        completions.removeAll { $0.completedDate < cutoff }
        feedback.removeAll { $0.submittedDate < cutoff }
        checkIns = checkIns.filter { _, value in value.completedAt >= cutoff }
    }

    // MARK: - Test/Debug

    /// Clears all prevention data. Mirrors `SeriousWarningAcknowledgements.clearAll()`.
    func clearAll() {
        profile = .defaultProfile
        checkIns = [:]
        completions = []
        feedback = []
        defaults.removeObject(forKey: Self.profileKey)
        defaults.removeObject(forKey: Self.checkInsKey)
        defaults.removeObject(forKey: Self.completionsKey)
        defaults.removeObject(forKey: Self.feedbackKey)
    }

    // MARK: - Codable Helpers

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
