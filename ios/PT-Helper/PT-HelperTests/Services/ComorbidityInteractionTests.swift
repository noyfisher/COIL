import XCTest
@testable import PT_Helper

/// Tier 3 PR A — tests for the comorbidity interaction map.
///
/// Covers two layers:
///   1. `OrderedPair` Hashable behavior (a,b) collides with (b,a).
///   2. `ComorbidityInteractionMap.canonicalize(_:)` — maps free-text user
///      condition strings (30 synthetic shapes) to canonical IDs.
///   3. `ExerciseContraindicationChecker.comorbidityWarnings(...)` — emits
///      `.serious` warnings for known interaction pairs, dedupes per
///      exercise, and stays silent on benign single-condition cases.
final class ComorbidityInteractionTests: XCTestCase {

    // MARK: - OrderedPair

    func test_orderedPair_symmetric() {
        let p1 = OrderedPair("alpha", "beta")
        let p2 = OrderedPair("beta", "alpha")
        XCTAssertEqual(p1, p2)
        XCTAssertEqual(p1.hashValue, p2.hashValue)
    }

    func test_orderedPair_normalizesToSortedOrder() {
        let p = OrderedPair("zeta", "alpha")
        XCTAssertEqual(p.a, "alpha")
        XCTAssertEqual(p.b, "zeta")
    }

    func test_orderedPair_differentValuesNotEqual() {
        XCTAssertNotEqual(
            OrderedPair("a", "b"),
            OrderedPair("a", "c")
        )
    }

    // MARK: - canonicalize() — exact alias matches

    func test_canonicalize_exactAlias_osteoporosis() {
        XCTAssertEqual(ComorbidityInteractionMap.canonicalize("osteoporosis"), "osteoporosis")
    }

    func test_canonicalize_exactAlias_pvd() {
        XCTAssertEqual(ComorbidityInteractionMap.canonicalize("pvd"), "peripheral_vascular_disease")
    }

    func test_canonicalize_caseInsensitive() {
        XCTAssertEqual(ComorbidityInteractionMap.canonicalize("OSTEOPOROSIS"), "osteoporosis")
        XCTAssertEqual(ComorbidityInteractionMap.canonicalize("PVD"), "peripheral_vascular_disease")
        XCTAssertEqual(ComorbidityInteractionMap.canonicalize("Diabetes"), "diabetes")
    }

    func test_canonicalize_trimsWhitespace() {
        XCTAssertEqual(ComorbidityInteractionMap.canonicalize("  osteoporosis  "), "osteoporosis")
    }

    func test_canonicalize_collapsesInternalWhitespace() {
        XCTAssertEqual(
            ComorbidityInteractionMap.canonicalize("balance   issues"),
            "balance_disorder"
        )
    }

    // MARK: - canonicalize() — substring matching

    func test_canonicalize_substring_userElaboration() {
        // User describes condition with extra context — substring containment
        // still resolves the canonical.
        XCTAssertEqual(
            ComorbidityInteractionMap.canonicalize("type 2 diabetes mellitus"),
            "diabetes"
        )
    }

    func test_canonicalize_substring_drugClass() {
        XCTAssertEqual(
            ComorbidityInteractionMap.canonicalize("warfarin 5mg daily"),
            "blood_thinner"
        )
    }

    // MARK: - canonicalize() — alternate phrasings

    func test_canonicalize_alternatePhrasings() {
        let cases: [(String, String)] = [
            ("low bone density", "osteoporosis"),
            ("history of falls", "balance_disorder"),
            ("vertigo", "balance_disorder"),
            ("history of MI", "cardiac_history"),
            ("hx of MI", "cardiac_history"),
            ("CABG 2019", "cardiac_history"),
            ("high blood pressure", "uncontrolled_htn"),
            ("prednisone 10mg", "corticosteroid_use"),
            ("recent surgery", "post_surgical"),
            ("post-op shoulder", "post_surgical"),
            ("peripheral neuropathy", "peripheral_neuropathy"),
            ("rheumatoid arthritis", "rheumatoid_arthritis"),
            ("RA flare", "rheumatoid_arthritis"),
            ("lupus", "autoimmune_inflammatory"),
            ("PAD", "peripheral_vascular_disease"),
            ("claudication", "peripheral_vascular_disease"),
            ("eliquis", "blood_thinner"),
            ("xarelto 20mg", "blood_thinner"),
            ("vestibular dysfunction", "balance_disorder"),
            ("balance disorder", "balance_disorder"),
            ("acute injury", "recent_injury"),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(
                ComorbidityInteractionMap.canonicalize(input),
                expected,
                "canonicalize(\"\(input)\") expected \"\(expected)\""
            )
        }
    }

    // MARK: - canonicalize() — misses

    func test_canonicalize_unknownCondition_returnsNil() {
        XCTAssertNil(ComorbidityInteractionMap.canonicalize("zebrafish syndrome"))
    }

    func test_canonicalize_emptyString_returnsNil() {
        XCTAssertNil(ComorbidityInteractionMap.canonicalize(""))
    }

    func test_canonicalize_whitespaceOnly_returnsNil() {
        XCTAssertNil(ComorbidityInteractionMap.canonicalize("   \n\t  "))
    }

    // MARK: - canonicalize() — coverage threshold

    /// DoD: a 30-string synthetic set should map ≥ 27 to canonical IDs
    /// (≥ 90% recall on plausible user input).
    func test_canonicalize_30StringTestSet_meetsCoverageThreshold() {
        let testSet = [
            // Direct alias hits
            "osteoporosis", "low bone density", "osteopenia",
            // Balance variants
            "balance disorder", "balance issues", "fall risk", "vertigo",
            // Diabetes
            "diabetes", "type 2 diabetes", "diabetic", "T2DM with neuropathy",
            // PVD
            "PVD", "peripheral artery disease", "claudication",
            // Cardiac
            "heart disease", "history of MI", "CABG", "stent placed 2018",
            // HTN
            "uncontrolled hypertension", "high blood pressure",
            // Steroids
            "prednisone", "corticosteroid use",
            // Anticoagulants
            "blood thinner", "warfarin", "eliquis",
            // Post-surgical
            "post-op", "recent surgery",
            // Autoimmune
            "rheumatoid arthritis", "lupus",
            // Neuropathy
            "peripheral neuropathy",
        ]
        XCTAssertEqual(testSet.count, 30, "test set must be exactly 30 to match DoD spec")

        let mapped = testSet.compactMap { ComorbidityInteractionMap.canonicalize($0) }
        XCTAssertGreaterThanOrEqual(
            mapped.count, 27,
            "Expected at least 27/30 to canonicalize; got \(mapped.count). Missing: \(testSet.filter { ComorbidityInteractionMap.canonicalize($0) == nil })"
        )
    }

    // MARK: - interactionExercises lookup

    func test_interactionExercises_knownPair_returnsBlocked() {
        let pair = OrderedPair("osteoporosis", "balance_disorder")
        let blocked = ComorbidityInteractionMap.interactionExercises(for: pair)
        XCTAssertFalse(blocked.isEmpty)
        XCTAssertTrue(blocked.contains("single-leg") || blocked.contains("bosu"))
    }

    func test_interactionExercises_pairOrderIrrelevant() {
        let blockedAB = ComorbidityInteractionMap.interactionExercises(
            for: OrderedPair("osteoporosis", "balance_disorder")
        )
        let blockedBA = ComorbidityInteractionMap.interactionExercises(
            for: OrderedPair("balance_disorder", "osteoporosis")
        )
        XCTAssertEqual(blockedAB, blockedBA)
    }

    func test_interactionExercises_unknownPair_returnsEmpty() {
        XCTAssertTrue(
            ComorbidityInteractionMap.interactionExercises(
                for: OrderedPair("alpha", "omega")
            ).isEmpty
        )
    }

    // MARK: - comorbidityWarnings end-to-end

    private func makeExercise(name: String) -> RehabExercise {
        RehabExercise(
            id: UUID(),
            name: name,
            targetArea: "Test",
            description: "Test exercise.",
            sets: 3,
            reps: "10",
            restSeconds: 30,
            difficulty: .beginner,
            demonstrationIcon: "figure.walk",
            tips: [],
            contraindications: []
        )
    }

    func test_comorbidityWarnings_osteoplusBalance_singleLegStand_emitsSerious() {
        let exercises = [makeExercise(name: "Single-Leg Stand")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["Osteoporosis", "balance issues"]
        )
        XCTAssertEqual(warnings.count, 1)
        XCTAssertEqual(warnings.first?.severity, .serious)
        XCTAssertTrue(warnings.first?.message.contains("osteoporosis") ?? false)
        XCTAssertTrue(warnings.first?.message.contains("balance disorder") ?? false)
    }

    func test_comorbidityWarnings_singleConditionOnly_doesNotFire() {
        let exercises = [makeExercise(name: "Single-Leg Stand")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["Osteoporosis"]  // only one condition — interaction can't fire
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    func test_comorbidityWarnings_unknownConditions_doNotFire() {
        let exercises = [makeExercise(name: "Single-Leg Stand")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["something obscure", "another vague label"]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    func test_comorbidityWarnings_safeExercise_noFire() {
        // Quad sets shouldn't be blocked by osteoporosis + balance disorder.
        let exercises = [makeExercise(name: "Quad Sets")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["Osteoporosis", "balance issues"]
        )
        XCTAssertTrue(warnings.isEmpty)
    }

    func test_comorbidityWarnings_dedupesAcrossPairs() {
        // User has 3 conditions all pairwise interacting on the same exercise.
        // Should still get exactly ONE warning per (exercise, pair) — but the
        // SAME exercise across multiple pairs may legitimately get multiple
        // warnings (different pair → different acknowledgement context).
        let exercises = [makeExercise(name: "Single-Leg Stand")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["Osteoporosis", "balance issues", "warfarin"]
        )
        // Pairs that match this exercise:
        //   (osteoporosis, balance_disorder) → matches
        //   (blood_thinner, balance_disorder) → matches
        //   (osteoporosis, blood_thinner) → no entry
        // Expect exactly 2 warnings (one per matching pair).
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(warnings.allSatisfy { $0.severity == .serious })
    }

    func test_comorbidityWarnings_bloodThinnerPlusBalance_fires() {
        let exercises = [makeExercise(name: "BOSU Single-Leg Balance")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["coumadin", "vertigo"]
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings.first?.message.contains("blood thinner") ?? false)
    }

    func test_comorbidityWarnings_diabetesPlusPvd_pressureWork() {
        let exercises = [makeExercise(name: "Barefoot Plantar Pressure Drill")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["type 2 diabetes", "PAD"]
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertEqual(warnings.first?.severity, .serious)
    }

    func test_comorbidityWarnings_cardiacPlusHTN_valsalva() {
        let exercises = [makeExercise(name: "Heavy Deadlift")]
        let warnings = ExerciseContraindicationChecker.comorbidityWarnings(
            exercises: exercises,
            conditions: ["history of MI", "uncontrolled hypertension"]
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertEqual(warnings.first?.severity, .serious)
    }

    // MARK: - validate() integration

    func test_validate_includesComorbidityWarnings() {
        // The full validate() should surface the comorbidity warnings
        // alongside its single-condition output.
        let exercises = [makeExercise(name: "Single-Leg Balance Drill")]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises,
            conditions: ["Osteoporosis", "balance issues"]
        )
        XCTAssertFalse(warnings.isEmpty)
        XCTAssertTrue(warnings.contains(where: { $0.severity == .serious && $0.message.contains("combination of") }))
    }

    func test_validate_singleConditionStillWorks_noRegression() {
        // Tier 1 behavior must still hold — a herniated disc + deadlift in the
        // single-condition map should still emit .serious without needing a
        // comorbidity pair.
        let exercises = [makeExercise(name: "Conventional Deadlift")]
        let warnings = ExerciseContraindicationChecker.validate(
            exercises: exercises,
            conditions: ["Herniated Disc"]
        )
        XCTAssertTrue(warnings.contains(where: { $0.severity == .serious }))
    }
}
