import Foundation

/// Deterministic selection of the day's prevention routine. Stateless enum,
/// pure static functions — mirrors `AdaptiveProgressionAnalyzer`'s pattern.
/// No AI call: MVP is fully local so it works offline and instantly.
enum PreventionRoutineEngine {

    // MARK: - Public API

    /// Builds today's routine, or `nil` when the check-in flags new/worsening
    /// symptoms — callers MUST treat `nil` as "do not prescribe or progress a
    /// routine" and show safety guidance instead (this is a defensive second
    /// guard; the view layer should also never call this when symptoms are flagged).
    static func selectRoutine(
        profile: PreventionProfile,
        checkIn: DailyPreventionCheckIn,
        healthProfile: UserProfile?,
        activePlan: RehabPlan?,
        recentFeedback: [PreventionFeedback],
        referenceDate: Date = Date()
    ) -> DailyPreventionRoutine? {
        guard !checkIn.hasNewOrWorseningSymptoms else { return nil }

        let focus = profile.focus
        let context = checkIn.context
        let length = checkIn.length

        let emphasis = categoryEmphasis(focus: focus, context: context, referenceDate: referenceDate)
        let progression = decideProgression(recentFeedback: recentFeedback, emphasis: emphasis)

        var pool = safetyFilteredPool(healthProfile: healthProfile, activePlan: activePlan)
        if context == .commute {
            pool = pool.filter { !$0.requiresSpace }
        }
        if context == .recoveryDay || progression == .regress {
            pool = pool.filter { $0.isGentle }
        }

        let picked = pickExercises(
            from: pool, focus: focus, context: context, emphasis: emphasis,
            count: length.exerciseCount, referenceDate: referenceDate
        )
        let adjusted = applyProgression(progression, to: picked)

        let micro = pickMicroAction(context: context, healthProfile: healthProfile)

        return DailyPreventionRoutine(
            dateKey: checkIn.dateKey,
            focus: focus,
            context: context,
            length: length,
            categoryEmphasis: emphasis,
            essentialExercises: adjusted,
            microAction: micro,
            rationale: rationale(focus: focus, context: context, activePlan: activePlan, progression: progression),
            generatedDate: referenceDate,
            wasRegressed: progression == .regress,
            wasAdvanced: progression == .advance
        )
    }

    // MARK: - Category Emphasis

    /// Deterministic per-day emphasis. Stable for a given (focus, context, week) —
    /// `healthyAging` alternates balance/strength by ISO week so a whole week
    /// reads as coherent while different weeks vary (spec: "coherent weekly emphasis").
    static func categoryEmphasis(focus: PreventionFocus, context: DailyContext, referenceDate: Date) -> PreventionCategory {
        if context == .recoveryDay { return .recoveryHabits }
        switch focus {
        case .deskComfort: return .mobilityControl
        case .workoutResilience: return .strengthCapacity
        case .mobility: return .mobilityControl
        case .balance: return .balance
        case .returnToActivity: return .mobilityControl
        case .healthyAging:
            let week = Calendar.current.component(.weekOfYear, from: referenceDate)
            return week.isMultiple(of: 2) ? .balance : .strengthCapacity
        }
    }

    // MARK: - Safety Filtering

    /// Excludes: exercises targeting a currently-injured body area or a
    /// "still recovering" / "has restrictions" surgery site; exact-name
    /// duplicates of the active plan's exercises; impact/jump-named items
    /// when osteoporosis is a listed medical condition (keyword conventions
    /// reused verbatim from `ResponseValidationPipeline`).
    static func safetyFilteredPool(
        healthProfile: UserProfile?, activePlan: RehabPlan?,
        pool: [PreventionCatalogEntry] = PreventionExerciseCatalog.allEntries
    ) -> [PreventionCatalogEntry] {
        let restrictedAreas = restrictedBodyAreas(healthProfile)
        let planNames = Set((activePlan?.exercises ?? []).map { $0.name.lowercased() })
        let hasOsteoporosis = (healthProfile?.medicalConditions ?? [])
            .contains { $0.lowercased().contains("osteoporosis") }
        let impactKeywords = ["jump", "plyometric", "impact"]

        return pool.filter { entry in
            let name = entry.template.exercise.name.lowercased()
            let area = entry.template.exercise.targetArea.lowercased()

            if planNames.contains(name) { return false }
            if restrictedAreas.contains(where: { area.contains($0) || $0.contains(area) }) { return false }
            if hasOsteoporosis && impactKeywords.contains(where: { name.contains($0) }) { return false }
            return true
        }
    }

    private static func restrictedBodyAreas(_ profile: UserProfile?) -> Set<String> {
        guard let profile else { return [] }
        var areas: Set<String> = []
        for injury in profile.injuries where injury.isCurrent {
            areas.insert(injury.bodyArea.lowercased())
        }
        for surgery in profile.surgeries {
            guard let status = surgery.recoveryStatus,
                  status == "Still recovering" || status == "Have restrictions" else { continue }
            if let area = surgery.bodyArea { areas.insert(area.lowercased()) }
        }
        return areas
    }

    // MARK: - Selection + Rotation

    /// Picks `count` exercises, preferring the emphasized category, then
    /// filling from the rest of the (already safety-filtered) pool. Rotates
    /// deterministically by day-of-year so the exact set varies daily while
    /// the category emphasis stays stable for the week.
    static func pickExercises(
        from pool: [PreventionCatalogEntry], focus: PreventionFocus, context: DailyContext,
        emphasis: PreventionCategory, count: Int, referenceDate: Date
    ) -> [PreventionExercise] {
        func suitable(_ entry: PreventionCatalogEntry, requireContext: Bool, requireFocus: Bool) -> Bool {
            let focusOK = !requireFocus || entry.suitableFocuses.isEmpty || entry.suitableFocuses.contains(focus)
            let contextOK = !requireContext || entry.suitableContexts.isEmpty || entry.suitableContexts.contains(context)
            return focusOK && contextOK
        }

        // Progressively relax focus/context requirements if the strict pool is too small,
        // so a heavily-restricted profile still gets a full routine rather than an empty one.
        var candidates = pool.filter { suitable($0, requireContext: true, requireFocus: true) }
        if candidates.count < count {
            candidates = pool.filter { suitable($0, requireContext: false, requireFocus: true) }
        }
        if candidates.count < count {
            candidates = pool.filter { suitable($0, requireContext: false, requireFocus: false) }
        }
        guard !candidates.isEmpty else { return [] }

        let sorted = candidates.sorted { $0.template.catalogKey < $1.template.catalogKey }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: referenceDate) ?? 1
        let offset = dayOfYear % sorted.count
        let rotated = Array(sorted[offset...] + sorted[..<offset])

        // Stable-partition: emphasis-category items first, so the routine
        // leans into today's focus even after rotation.
        let emphasized = rotated.filter { $0.template.category == emphasis }
        let rest = rotated.filter { $0.template.category != emphasis }
        let ordered = emphasized + rest

        var picked: [PreventionExercise] = []
        var seenKeys: Set<String> = []
        for entry in ordered {
            guard picked.count < count else { break }
            guard seenKeys.insert(entry.template.catalogKey).inserted else { continue }
            picked.append(entry.template.instantiated())
        }
        return picked
    }

    private static func pickMicroAction(context: DailyContext, healthProfile: UserProfile?) -> PreventionExercise? {
        let restrictedAreas = restrictedBodyAreas(healthProfile)
        let matches = PreventionExerciseCatalog.microActions.filter { entry in
            entry.suitableContexts.contains(context)
                && !restrictedAreas.contains(where: { entry.template.exercise.targetArea.lowercased().contains($0) })
        }
        return (matches.first ?? PreventionExerciseCatalog.microActions.first)?.template.instantiated()
    }

    // MARK: - Progression / Regression

    enum ProgressionDecision: Equatable { case advance, maintain, regress }

    /// Looks at the most recent feedback whose categories include today's
    /// emphasis. A single "too much" or any concerning-pain report regresses
    /// immediately (safety-biased); two most-recent-in-a-row "easier" reports advance.
    static func decideProgression(recentFeedback: [PreventionFeedback], emphasis: PreventionCategory) -> ProgressionDecision {
        let relevant = recentFeedback
            .filter { $0.categories.contains(emphasis) }
            .sorted { $0.submittedDate > $1.submittedDate }

        guard let latest = relevant.first else { return .maintain }

        // Note: `.none` on `PreventionPainLevel` collides with `Optional.none`,
        // so the "has reported pain" case is written with an explicit type name
        // to avoid silently comparing against `nil` instead.
        if latest.difficulty == .tooMuch || (latest.pain != nil && latest.pain != PreventionPainLevel.none) {
            return .regress
        }

        let recentTwo = relevant.prefix(2)
        if recentTwo.count == 2 && recentTwo.allSatisfy({ $0.difficulty == .easier }) {
            return .advance
        }

        return .maintain
    }

    private static func applyProgression(_ decision: ProgressionDecision, to exercises: [PreventionExercise]) -> [PreventionExercise] {
        guard decision != .maintain else { return exercises }
        return exercises.map { item in
            var updated = item
            switch decision {
            case .advance:
                updated.exercise.reps = AdaptiveProgressionAnalyzer.adjustReps(item.exercise.reps, increment: 2)
                updated.exercise.difficulty = AdaptiveProgressionAnalyzer.nextDifficulty(item.exercise.difficulty)
            case .regress:
                updated.exercise.reps = AdaptiveProgressionAnalyzer.adjustReps(item.exercise.reps, increment: -2)
                updated.exercise.difficulty = previousDifficulty(item.exercise.difficulty)
            case .maintain:
                break
            }
            return updated
        }
    }

    /// Inverse of `AdaptiveProgressionAnalyzer.nextDifficulty` — that analyzer
    /// only advances, so the (small) regression direction lives here.
    private static func previousDifficulty(_ current: RehabExercise.Difficulty) -> RehabExercise.Difficulty {
        switch current {
        case .advanced: return .intermediate
        case .intermediate: return .beginner
        case .beginner: return .beginner
        }
    }

    // MARK: - Rationale

    private static func rationale(focus: PreventionFocus, context: DailyContext, activePlan: RehabPlan?, progression: ProgressionDecision) -> String {
        var base: String
        switch context {
        case .deskHeavy: base = "Built for your desk-heavy day."
        case .activeDay: base = "A short warm-up to prep for training."
        case .recoveryDay: base = "Recovery day — gentle movement, no pushing today."
        case .commute: base = "A quick reset for your drive or commute."
        }
        if progression == .regress {
            base += " Eased off based on your last feedback."
        } else if let plan = activePlan {
            base += " Complements your \(plan.planName)."
        }
        return base
    }
}

// MARK: - Weekly Review

/// Deterministic, transparent weekly summary built only from local
/// completion/feedback data — no risk scores or predictive language.
enum PreventionWeeklyReviewEngine {

    static func buildReview(
        completions: [PreventionCompletion],
        feedback: [PreventionFeedback],
        referenceDate: Date = Date()
    ) -> PreventionWeeklyReview {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .weekOfYear, for: referenceDate)
            ?? DateInterval(start: referenceDate, duration: 7 * 24 * 60 * 60)

        let weekCompletions = completions.filter { interval.contains($0.completedDate) }
        let weekFeedback = feedback.filter { interval.contains($0.submittedDate) }

        var byCategory: [PreventionCategory: Int] = [:]
        for completion in weekCompletions {
            for category in completion.categories {
                byCategory[category, default: 0] += 1
            }
        }

        let contextCounts = Dictionary(grouping: weekCompletions, by: \.context).mapValues(\.count)
        let mostCommonContext = contextCounts.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }?.key

        let positiveInsight = insight(sessionCount: weekCompletions.count, byCategory: byCategory)
        let toughCount = weekFeedback.filter { $0.difficulty == .tooMuch || ($0.pain != nil && $0.pain != PreventionPainLevel.none) }.count
        let adjustment = nextWeekAdjustment(toughCount: toughCount, mostCommonContext: mostCommonContext)

        return PreventionWeeklyReview(
            weekStart: interval.start,
            weekEnd: interval.end,
            sessionCount: weekCompletions.count,
            completionsByCategory: byCategory,
            mostCommonContext: mostCommonContext,
            positiveInsight: positiveInsight,
            nextWeekAdjustment: adjustment
        )
    }

    private static func insight(sessionCount: Int, byCategory: [PreventionCategory: Int]) -> String {
        guard sessionCount > 0 else {
            return "No sessions yet this week — even a 3-minute routine counts."
        }
        if let top = byCategory.max(by: { lhs, rhs in
            lhs.value == rhs.value ? lhs.key.rawValue > rhs.key.rawValue : lhs.value < rhs.value
        }) {
            return "You completed \(top.value) \(top.key.displayName.lowercased()) routine\(top.value == 1 ? "" : "s") this week."
        }
        return "You completed \(sessionCount) prevention session\(sessionCount == 1 ? "" : "s") this week."
    }

    private static func nextWeekAdjustment(toughCount: Int, mostCommonContext: DailyContext?) -> String {
        if toughCount >= 2 {
            return "You marked routines as too much a few times — next week starts with shorter options."
        }
        if let context = mostCommonContext {
            // `DailyContext.displayName` already reads naturally as a day
            // description ("Desk-heavy day", "Long drive / commute") — appending
            // "days" here would double up ("desk-heavy day days").
            return "Your most common context this week was \(context.displayName.lowercased())."
        }
        return "Keep up your current rhythm — consistency matters more than intensity."
    }
}
