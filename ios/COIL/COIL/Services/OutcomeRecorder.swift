import Foundation
import FirebaseAuth
import FirebaseFirestore
import os

// MARK: - Tier 3 PR D: Outcome Recorder

/// Persists outcome ratings (was the AI analysis useful?) to two layers:
///   1. UserDefaults — local cache. Cheap "have I rated this analysis already?"
///      check that doesn't require a Firestore round-trip on every plan view.
///   2. Firestore at `users/{uid}/analysisOutcomes/{analysisId}` — the durable
///      source of truth. Used by Tier 3B confidence recalibration once the
///      sample volume is meaningful (~500 outcomes).
///
/// Both writes are fire-and-forget at the call site so a Firestore outage
/// doesn't block the UI. Local cache write is synchronous.
@MainActor
final class OutcomeRecorder {
    static let shared = OutcomeRecorder()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper",
        category: "outcomes"
    )

    /// UserDefaults key holding the JSON-encoded set of analysis IDs that
    /// have already been rated. Set keeps lookup O(1) for the "already
    /// rated?" check.
    private static let ratedIDsKey = "ratedAnalysisIDs"

    private init() {}

    // MARK: - Record

    /// Persist a rating. Local set is updated immediately; Firestore write
    /// runs in a detached Task and is auth-safe (no-op if user is not
    /// authenticated). The session log records every call so the event is
    /// captured even if Firestore is offline.
    func record(
        _ feedback: OutcomeFeedback,
        for analysisId: UUID,
        planId: UUID? = nil,
        planAgeDays: Int? = nil
    ) {
        let record = AnalysisOutcomeRecord(
            analysisId: analysisId,
            feedback: feedback,
            recordedAt: Date(),
            planId: planId,
            planAgeDays: planAgeDays
        )

        // 1. Local cache update — synchronous so subsequent `hasRated()` calls
        //    return true immediately.
        markRated(analysisId: analysisId)

        // 2. Session log breadcrumb (non-blocking).
        SessionLogger.shared.logOutcome(
            analysisId: analysisId,
            feedback: feedback,
            planAgeDays: planAgeDays
        )

        // 3. Firestore write — capture the acting user's UID NOW (not later, at
        //    execution time) so an account switch between this action and the
        //    detached write can't misattribute the outcome to the next account (P2-04).
        let uid = Auth.auth().currentUser?.uid
        Task.detached { [logger] in
            await Self.persistRemote(record: record, uid: uid, logger: logger)
        }
    }

    /// Did this analysis already get rated? Reads the local cache.
    func hasRated(analysisId: UUID) -> Bool {
        loadRatedIDs().contains(analysisId)
    }

    // MARK: - Eligibility

    /// Should we surface the outcome prompt for this plan?
    /// Returns true when:
    /// - the plan has a `startDate`
    /// - the user has been on the plan for at least `minimumPlanAgeDays`
    ///   (default 7)
    /// - the underlying analysis hasn't been rated yet
    nonisolated static let minimumPlanAgeDays = 7

    func shouldShowPrompt(
        planStartDate: Date?,
        analysisId: UUID,
        now: Date = Date(),
        minimumDays: Int = OutcomeRecorder.minimumPlanAgeDays
    ) -> Bool {
        guard let startDate = planStartDate else { return false }
        if hasRated(analysisId: analysisId) { return false }
        let elapsedSeconds = now.timeIntervalSince(startDate)
        let elapsedDays = Int(elapsedSeconds / 86_400)
        return elapsedDays >= minimumDays
    }

    /// Days since a plan started (rounded down). Returns nil when start
    /// date is missing or in the future. Used as the `planAgeDays` field
    /// when recording.
    static func planAgeDays(planStartDate: Date?, now: Date = Date()) -> Int? {
        guard let startDate = planStartDate else { return nil }
        let elapsed = now.timeIntervalSince(startDate)
        guard elapsed >= 0 else { return nil }
        return Int(elapsed / 86_400)
    }

    // MARK: - Local cache

    private func loadRatedIDs() -> Set<UUID> {
        guard let data = UserDefaults.standard.data(forKey: Self.ratedIDsKey),
              let strings = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    private func markRated(analysisId: UUID) {
        var set = loadRatedIDs()
        set.insert(analysisId)
        let strings = set.map(\.uuidString).sorted()
        guard let data = try? JSONEncoder().encode(strings) else { return }
        UserDefaults.standard.set(data, forKey: Self.ratedIDsKey)
    }

    /// Test/debug helper.
    func clearLocalCache() {
        UserDefaults.standard.removeObject(forKey: Self.ratedIDsKey)
    }

    // MARK: - Firestore

    private static func persistRemote(record: AnalysisOutcomeRecord, uid: String?, logger: Logger) async {
        guard let uid else {
            logger.debug("Skipping outcome persistence: no authenticated user")
            return
        }
        do {
            try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("analysisOutcomes").document(record.analysisId.uuidString)
                .setData([
                    "feedback": record.feedback.rawValue,
                    "recordedAt": Timestamp(date: record.recordedAt),
                    "planId": record.planId?.uuidString as Any,
                    "planAgeDays": record.planAgeDays as Any,
                ])
            logger.info("Persisted outcome rating \(record.feedback.rawValue) for analysis \(record.analysisId.uuidString)")
        } catch {
            logger.error("Failed to persist outcome to Firestore: \(error.localizedDescription)")
        }
    }
}

// MARK: - SessionLogger extension

extension SessionLogger {
    /// Log a user outcome rating as a session event. Captured locally for
    /// debug + included in session-log uploads. Separate from the Firestore
    /// persistence (which is the source of truth for recalibration).
    func logOutcome(
        analysisId: UUID,
        feedback: OutcomeFeedback,
        planAgeDays: Int?
    ) {
        var meta: [String: String] = [
            "analysisId": analysisId.uuidString,
            "feedback": feedback.rawValue,
        ]
        if let age = planAgeDays {
            meta["planAgeDays"] = "\(age)"
        }
        log(
            .formSubmitted,
            category: .userAction,
            message: "Outcome rated: \(feedback.rawValue)",
            metadata: meta
        )
    }
}
