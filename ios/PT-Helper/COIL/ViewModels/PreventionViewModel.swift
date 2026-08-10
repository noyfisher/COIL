import Foundation

/// Thin `@MainActor` wrapper around `PreventionService` for `TodaysPreventionView`.
/// Owns the check-in → safety-hold → routine state machine so the view layer
/// never has to re-derive "does today need a check-in, or is it a safety hold?"
@MainActor
final class PreventionViewModel: ObservableObject {

    enum Stage {
        case needsCheckIn
        case safetyHold(DailyPreventionCheckIn)
        case routine(DailyPreventionRoutine)
    }

    @Published private(set) var stage: Stage = .needsCheckIn
    @Published var showCheckInSheet = false
    @Published var showProfileSetup = false
    @Published var showWeeklyReview = false
    @Published var pendingFeedbackFor: PreventionCompletion?

    private let service: PreventionService

    // `PreventionService.shared` is @MainActor-isolated, and Swift 6 mode
    // doesn't let a default-argument expression inherit actor isolation from
    // the initializer — so the `.shared` lookup happens in the (MainActor) body instead.
    init(service: PreventionService? = nil) {
        self.service = service ?? .shared
    }

    var profile: PreventionProfile { service.profile }
    var todayCheckIn: DailyPreventionCheckIn? { service.checkIn() }

    /// Same data as `weeklyReview()`, for the inline Home progress widget —
    /// deliberately does NOT log `.preventionWeeklyReviewViewed` (that's
    /// reserved for actually opening the full weekly review sheet).
    func currentWeekProgress() -> PreventionWeeklyReview {
        service.weeklyReview()
    }

    // MARK: - Refresh

    /// Re-derives `stage` from persisted state. Call on appear and after any
    /// check-in / profile change.
    func refresh(activePlan: RehabPlan?, healthProfile: UserProfile?) {
        guard let checkIn = service.checkIn() else {
            stage = .needsCheckIn
            return
        }
        if checkIn.hasNewOrWorseningSymptoms {
            stage = .safetyHold(checkIn)
            return
        }
        if let routine = service.routine(activePlan: activePlan, healthProfile: healthProfile) {
            stage = .routine(routine)
        } else {
            // Defensive — shouldn't happen once a non-symptom check-in exists.
            stage = .needsCheckIn
        }
    }

    // MARK: - Check-In

    func submitCheckIn(context: DailyContext, hasSymptoms: Bool, length: PreventionRoutineLength,
                        activePlan: RehabPlan?, healthProfile: UserProfile?) {
        let checkIn = DailyPreventionCheckIn(context: context, hasNewOrWorseningSymptoms: hasSymptoms, length: length)
        service.submitCheckIn(checkIn)
        showCheckInSheet = false
        refresh(activePlan: activePlan, healthProfile: healthProfile)
    }

    // MARK: - Profile

    func saveProfile(_ profile: PreventionProfile) {
        service.saveProfile(profile)
        showProfileSetup = false
    }

    // MARK: - Routine Actions

    /// Records the routine as completed and queues the post-completion feedback prompt.
    func completeRoutine(_ routine: DailyPreventionRoutine) {
        let completion = PreventionCompletion(
            dateKey: routine.dateKey,
            routineId: routine.id,
            categories: routine.allCategories,
            focus: routine.focus,
            context: routine.context,
            minutes: routine.length.rawValue,
            includedMicroAction: routine.microAction != nil
        )
        service.recordCompletion(completion)
        pendingFeedbackFor = completion
    }

    /// "Too much today" — bails out before finishing. Records feedback (no
    /// completion) so the routine engine regresses tomorrow onward, and shows
    /// the same safety-minded feedback framing without pretending it was completed.
    func tooMuchToday(_ routine: DailyPreventionRoutine) {
        let fb = PreventionFeedback(
            routineId: routine.id, dateKey: routine.dateKey, categories: routine.allCategories,
            difficulty: .tooMuch, pain: nil
        )
        service.recordFeedback(fb)
    }

    func submitFeedback(difficulty: PreventionDifficultyRating, pain: PreventionPainLevel?) {
        guard let completion = pendingFeedbackFor else { return }
        let fb = PreventionFeedback(
            routineId: completion.routineId, dateKey: completion.dateKey, categories: completion.categories,
            difficulty: difficulty, pain: pain
        )
        service.recordFeedback(fb)
        pendingFeedbackFor = nil
    }

    func dismissFeedback() {
        pendingFeedbackFor = nil
    }

    // MARK: - Weekly Review

    func weeklyReview() -> PreventionWeeklyReview {
        AnalyticsService.shared.log(.preventionWeeklyReviewViewed)
        return service.weeklyReview()
    }
}
