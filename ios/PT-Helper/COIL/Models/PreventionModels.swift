import Foundation

// MARK: - Date Keying

/// Shared calendar-day key ("yyyy-MM-dd") for all Prevention persistence —
/// mirrors the ad-hoc format `PreventativeTasksView` already uses for its
/// legacy checklist, centralized here so every Prevention type/service agrees.
enum PreventionDateKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        return f
    }()

    static func key(for date: Date = Date()) -> String { formatter.string(from: date) }
}

// MARK: - Prevention Focus

/// The user's primary injury-prevention goal, captured in prevention setup.
enum PreventionFocus: String, Codable, CaseIterable, Identifiable {
    case deskComfort = "desk_comfort"
    case workoutResilience = "workout_resilience"
    case mobility = "mobility"
    case balance = "balance"
    case returnToActivity = "return_to_activity"
    case healthyAging = "healthy_aging"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deskComfort: return "Desk Comfort"
        case .workoutResilience: return "Workout Resilience"
        case .mobility: return "Mobility"
        case .balance: return "Balance & Fall Prevention"
        case .returnToActivity: return "Return to Activity"
        case .healthyAging: return "Healthy Aging"
        }
    }

    var subtitle: String {
        switch self {
        case .deskComfort: return "Undo sitting stiffness in your neck, back and hips"
        case .workoutResilience: return "Warm up and stay durable for training"
        case .mobility: return "Keep your joints moving freely"
        case .balance: return "Steadier footing, fewer stumbles"
        case .returnToActivity: return "Ease back in after time off"
        case .healthyAging: return "Stay strong, mobile and independent"
        }
    }

    var icon: String {
        switch self {
        case .deskComfort: return "chair.fill"
        case .workoutResilience: return "figure.run"
        case .mobility: return "figure.flexibility"
        case .balance: return "figure.stand"
        case .returnToActivity: return "arrow.triangle.turn.up.right.circle.fill"
        case .healthyAging: return "leaf.fill"
        }
    }
}

// MARK: - Daily Context

/// What "today" looks like. Shared by the prevention profile's "typical
/// context" and the daily check-in's "what does today look like" question —
/// the product spec lists the same four options for both.
enum DailyContext: String, Codable, CaseIterable, Identifiable {
    case deskHeavy = "desk_heavy"
    case activeDay = "active_day"
    case recoveryDay = "recovery_day"
    case commute = "commute"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deskHeavy: return "Desk-heavy day"
        case .activeDay: return "Workout / active day"
        case .recoveryDay: return "Recovery day"
        case .commute: return "Long drive / commute"
        }
    }

    var icon: String {
        switch self {
        case .deskHeavy: return "desktopcomputer"
        case .activeDay: return "figure.strengthtraining.traditional"
        case .recoveryDay: return "bed.double.fill"
        case .commute: return "car.fill"
        }
    }
}

// MARK: - Prevention Category (weekly-progress buckets)

/// Coarse category used to roll up weekly progress. Distinct from
/// `RehabExercise.exerciseCategory` (fine-grained catalog category like
/// "strength"/"stretch") — this is the 4-bucket grouping the product spec
/// asks the progress UI to show.
enum PreventionCategory: String, Codable, CaseIterable, Identifiable {
    case mobilityControl = "mobility_control"
    case strengthCapacity = "strength_capacity"
    case balance = "balance"
    case recoveryHabits = "recovery_habits"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mobilityControl: return "Mobility & Control"
        case .strengthCapacity: return "Strength & Capacity"
        case .balance: return "Balance"
        case .recoveryHabits: return "Recovery Habits"
        }
    }

    var icon: String {
        switch self {
        case .mobilityControl: return "figure.flexibility"
        case .strengthCapacity: return "figure.strengthtraining.traditional"
        case .balance: return "figure.stand"
        case .recoveryHabits: return "wind"
        }
    }
}

// MARK: - Routine Length

enum PreventionRoutineLength: Int, Codable, CaseIterable, Identifiable {
    case short = 3
    case medium = 6
    case long = 10

    var id: Int { rawValue }
    var displayName: String { "\(rawValue) min" }

    /// Number of essential exercises/actions for this length (spec: 2-4 items).
    var exerciseCount: Int {
        switch self {
        case .short: return 2
        case .medium: return 3
        case .long: return 4
        }
    }
}

// MARK: - Prevention Profile

/// Lightweight, local, optional setup. No server dependency — persisted via
/// `PreventionService` as a single JSON blob in UserDefaults.
struct PreventionProfile: Codable {
    var focus: PreventionFocus
    var typicalContext: DailyContext
    var equipment: RehabPlanPreferences.Equipment
    var preferredLength: PreventionRoutineLength
    /// Optional preferred reminder time. Stored only for this MVP — not wired
    /// into `NotificationService` (see plan decisions); a natural follow-up.
    var reminderHour: Int?
    var reminderMinute: Int?
    /// False until the user completes (or explicitly skips) setup; drives the
    /// unobtrusive "Personalize" entry point vs. treating defaults as chosen.
    var hasCompletedSetup: Bool
    var lastUpdated: Date

    static let defaultProfile = PreventionProfile(
        focus: .mobility,
        typicalContext: .deskHeavy,
        equipment: .none,
        preferredLength: .medium,
        reminderHour: nil,
        reminderMinute: nil,
        hasCompletedSetup: false,
        lastUpdated: Date()
    )
}

// MARK: - Daily Check-In

/// The compact, ≤3-interaction check-in shown before today's routine.
/// Persisted per calendar day.
struct DailyPreventionCheckIn: Codable, Identifiable {
    var id: String { dateKey }
    let dateKey: String
    var context: DailyContext
    var hasNewOrWorseningSymptoms: Bool
    var length: PreventionRoutineLength
    var completedAt: Date

    init(dateKey: String = PreventionDateKey.key(), context: DailyContext,
         hasNewOrWorseningSymptoms: Bool, length: PreventionRoutineLength,
         completedAt: Date = Date()) {
        self.dateKey = dateKey
        self.context = context
        self.hasNewOrWorseningSymptoms = hasNewOrWorseningSymptoms
        self.length = length
        self.completedAt = completedAt
    }
}

// MARK: - Prevention Exercise

/// Wraps a `RehabExercise` so existing display machinery (`ExerciseImageView`,
/// `ExerciseImageService`'s fuzzy image resolver) works unmodified, plus the
/// bits specific to the prevention loop.
struct PreventionExercise: Codable, Identifiable {
    let id: UUID
    var exercise: RehabExercise
    var category: PreventionCategory
    var isMicroAction: Bool
    /// For time-based holds/breathing (seconds). Nil = show `exercise.reps` as-is.
    var durationSeconds: Int?
    /// Stable catalog identity (independent of `id`, which is re-minted per
    /// selection) — used for rotation/history and duplicate detection.
    var catalogKey: String

    init(id: UUID = UUID(), exercise: RehabExercise, category: PreventionCategory,
         isMicroAction: Bool = false, durationSeconds: Int? = nil, catalogKey: String) {
        self.id = id
        self.exercise = exercise
        self.category = category
        self.isMicroAction = isMicroAction
        self.durationSeconds = durationSeconds
        self.catalogKey = catalogKey
    }

    /// A fresh copy with a new `id`, used when the same catalog template is
    /// placed into a new routine (identity should be per-appearance, not shared).
    func instantiated() -> PreventionExercise {
        PreventionExercise(exercise: exercise, category: category,
                            isMicroAction: isMicroAction, durationSeconds: durationSeconds,
                            catalogKey: catalogKey)
    }
}

// MARK: - Daily Routine

struct DailyPreventionRoutine: Codable, Identifiable {
    let id: UUID
    let dateKey: String
    var focus: PreventionFocus
    var context: DailyContext
    var length: PreventionRoutineLength
    var categoryEmphasis: PreventionCategory
    var essentialExercises: [PreventionExercise]
    var microAction: PreventionExercise?
    var rationale: String
    var generatedDate: Date
    /// True when today's set was regressed due to recent "too much"/"concerning" feedback.
    var wasRegressed: Bool
    /// True when today's set was advanced due to repeated "easier" feedback.
    var wasAdvanced: Bool

    init(id: UUID = UUID(), dateKey: String, focus: PreventionFocus, context: DailyContext,
         length: PreventionRoutineLength, categoryEmphasis: PreventionCategory,
         essentialExercises: [PreventionExercise], microAction: PreventionExercise?,
         rationale: String, generatedDate: Date = Date(),
         wasRegressed: Bool = false, wasAdvanced: Bool = false) {
        self.id = id
        self.dateKey = dateKey
        self.focus = focus
        self.context = context
        self.length = length
        self.categoryEmphasis = categoryEmphasis
        self.essentialExercises = essentialExercises
        self.microAction = microAction
        self.rationale = rationale
        self.generatedDate = generatedDate
        self.wasRegressed = wasRegressed
        self.wasAdvanced = wasAdvanced
    }

    /// All categories represented (essential + micro-action), de-duplicated —
    /// used to log a completion against the weekly-progress buckets.
    var allCategories: [PreventionCategory] {
        var cats = essentialExercises.map(\.category)
        if let micro = microAction { cats.append(micro.category) }
        var seen = Set<PreventionCategory>()
        return cats.filter { seen.insert($0).inserted }
    }
}

// MARK: - Completion

struct PreventionCompletion: Codable, Identifiable {
    let id: UUID
    let dateKey: String
    let routineId: UUID
    let categories: [PreventionCategory]
    let focus: PreventionFocus
    let context: DailyContext
    let minutes: Int
    let completedDate: Date
    let includedMicroAction: Bool

    init(id: UUID = UUID(), dateKey: String, routineId: UUID, categories: [PreventionCategory],
         focus: PreventionFocus, context: DailyContext, minutes: Int,
         completedDate: Date = Date(), includedMicroAction: Bool) {
        self.id = id
        self.dateKey = dateKey
        self.routineId = routineId
        self.categories = categories
        self.focus = focus
        self.context = context
        self.minutes = minutes
        self.completedDate = completedDate
        self.includedMicroAction = includedMicroAction
    }
}

// MARK: - Feedback

enum PreventionDifficultyRating: String, Codable, CaseIterable, Identifiable {
    case easier
    case aboutRight = "about_right"
    case tooMuch = "too_much"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easier: return "Easier than expected"
        case .aboutRight: return "About right"
        case .tooMuch: return "Too much"
        }
    }
}

enum PreventionPainLevel: String, Codable, CaseIterable, Identifiable {
    case none
    case mild
    case concerning

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .mild: return "Mild"
        case .concerning: return "Concerning"
        }
    }
}

struct PreventionFeedback: Codable, Identifiable {
    let id: UUID
    /// The routine this feedback is about. Linked to `DailyPreventionRoutine.id`
    /// rather than a completion, so "Too much today" (bailing out before
    /// finishing) can submit feedback without a `PreventionCompletion` existing.
    let routineId: UUID
    let dateKey: String
    let categories: [PreventionCategory]
    let difficulty: PreventionDifficultyRating
    let pain: PreventionPainLevel?
    let submittedDate: Date

    init(id: UUID = UUID(), routineId: UUID, dateKey: String, categories: [PreventionCategory],
         difficulty: PreventionDifficultyRating, pain: PreventionPainLevel? = nil,
         submittedDate: Date = Date()) {
        self.id = id
        self.routineId = routineId
        self.dateKey = dateKey
        self.categories = categories
        self.difficulty = difficulty
        self.pain = pain
        self.submittedDate = submittedDate
    }
}

// MARK: - Weekly Review

/// Deterministic, transparent, local-data-only summary — no risk scores or
/// predictive/diagnostic language.
struct PreventionWeeklyReview: Codable {
    let weekStart: Date
    let weekEnd: Date
    let sessionCount: Int
    let completionsByCategory: [PreventionCategory: Int]
    let mostCommonContext: DailyContext?
    let positiveInsight: String
    let nextWeekAdjustment: String
}
