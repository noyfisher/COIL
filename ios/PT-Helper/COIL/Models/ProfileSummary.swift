import Foundation

/// What the Profile masthead shows. Built once per render by `ProfileSummaryBuilder`
/// from the profile, the saved plans, the streak and the session count; the card
/// itself does no data access.
struct ProfileSummary: Equatable {

    struct ActivePlan: Equatable {
        var name: String
        /// "Week 2 of 6" / "Not started" / "Completed"
        var statusText: String
        /// True only for `.active` plans — drives the "Active" badge.
        var isActive: Bool
    }

    struct PlanWeek: Equatable {
        var current: Int
        var total: Int
    }

    struct Stats: Equatable {
        var streak: Int
        /// nil unless the chosen plan is `.active`.
        var planWeek: PlanWeek?
        var sessions: Int
    }

    /// "First Last" trimmed; "Your profile" when the profile is nil or the name is blank.
    var displayName: String
    /// First letters of first + last; first two letters of a single name; "?" when blank.
    var initials: String
    /// "34 · Moderately Active" — age omitted below 1, activity omitted when empty, nil when both are.
    var detailLine: String?
    /// Current injuries as "Body area · description (≤ 24 chars, ellipsised)", then medical
    /// conditions; de-duplicated case-insensitively; at most four.
    var conditionChips: [String]
    var activePlan: ActivePlan?
    var stats: Stats
}

enum ProfileSummaryBuilder {

    static let placeholderName = "Your profile"
    static let maxChips = 4
    static let chipDescriptionLimit = 24

    static func build(profile: UserProfile?, plans: [RehabPlan],
                      streak: StreakData, sessionCount: Int) -> ProfileSummary {
        let plan = HomeProgramLogic.preferredPlan(from: plans)
        let activePlan = plan.map { chosen in
            ProfileSummary.ActivePlan(name: chosen.planName,
                                      statusText: statusText(for: chosen),
                                      isActive: isActive(chosen))
        }
        let planWeek: ProfileSummary.PlanWeek? = plan.flatMap { chosen in
            if case .active(let week) = chosen.status {
                return ProfileSummary.PlanWeek(current: week, total: chosen.totalWeeks)
            }
            return nil
        }
        return ProfileSummary(
            displayName: displayName(for: profile),
            initials: initials(for: profile),
            detailLine: detailLine(for: profile),
            conditionChips: conditionChips(for: profile),
            activePlan: activePlan,
            stats: ProfileSummary.Stats(streak: streak.currentStreak,
                                        planWeek: planWeek,
                                        sessions: sessionCount)
        )
    }

    // MARK: - Pieces (internal so tests can target one rule at a time if needed)

    static func displayName(for profile: UserProfile?) -> String {
        guard let profile else { return placeholderName }
        let full = [profile.firstName, profile.lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? placeholderName : full
    }

    static func initials(for profile: UserProfile?) -> String {
        guard let profile else { return "?" }
        let first = profile.firstName.trimmingCharacters(in: .whitespaces)
        let last = profile.lastName.trimmingCharacters(in: .whitespaces)
        switch (first.isEmpty, last.isEmpty) {
        case (false, false): return (String(first.prefix(1)) + String(last.prefix(1))).uppercased()
        case (false, true):  return String(first.prefix(2)).uppercased()
        case (true, false):  return String(last.prefix(2)).uppercased()
        case (true, true):   return "?"
        }
    }

    static func detailLine(for profile: UserProfile?) -> String? {
        guard let profile else { return nil }
        var parts: [String] = []
        if profile.age >= 1 { parts.append("\(profile.age)") }
        let activity = profile.activityLevel.trimmingCharacters(in: .whitespaces)
        if !activity.isEmpty { parts.append(activity) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func conditionChips(for profile: UserProfile?) -> [String] {
        guard let profile else { return [] }
        var chips: [String] = []
        for injury in profile.injuries where injury.isCurrent {
            let area = injury.bodyArea.trimmingCharacters(in: .whitespaces)
            let description = clipped(injury.description.trimmingCharacters(in: .whitespaces))
            let chip = [area, description].filter { !$0.isEmpty }.joined(separator: " · ")
            if !chip.isEmpty { chips.append(chip) }
        }
        chips.append(contentsOf: profile.medicalConditions
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        var seen = Set<String>()
        let unique = chips.filter { seen.insert($0.lowercased()).inserted }
        return Array(unique.prefix(maxChips))
    }

    /// Keeps a chip's description within `chipDescriptionLimit` characters, ending it
    /// with an ellipsis rather than a mid-word cut when it had to be shortened.
    static func clipped(_ text: String) -> String {
        guard text.count > chipDescriptionLimit else { return text }
        return String(text.prefix(chipDescriptionLimit - 1)) + "…"
    }

    static func statusText(for plan: RehabPlan) -> String {
        switch plan.status {
        case .notStarted:        return "Not started"
        case .completed:         return "Completed"
        case .active(let week):  return "Week \(week) of \(plan.totalWeeks)"
        }
    }

    private static func isActive(_ plan: RehabPlan) -> Bool {
        if case .active = plan.status { return true }
        return false
    }
}
