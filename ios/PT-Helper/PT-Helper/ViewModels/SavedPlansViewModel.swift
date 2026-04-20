import SwiftUI

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class SavedPlansViewModel: ObservableObject {
    /// Cap on plans fetched by the real-time listener. Prevents unbounded reads
    /// (and unbounded snapshot payloads on every write) if a user accumulates
    /// many plans. Newest-first ordering means older plans fall off the window
    /// once the cap is hit; add pagination here if users ever actually hit it.
    private static let rehabPlansFetchLimit = 50

    @Published var rehabPlans: [RehabPlan] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String?

    private let db = Firestore.firestore()
    /// `nonisolated(unsafe)` so deinit (which is nonisolated) can remove the listener.
    nonisolated(unsafe) private var listenerRegistration: ListenerRegistration?

    init() {
        if TestDataSeeder.isUITesting && TestDataSeeder.shouldSeedMockData {
            self.rehabPlans = TestDataSeeder.makeMockPlans()
            self.isLoading = false
        } else {
            startListening()
        }
    }

    deinit {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    /// One-time migration: move any docs from the legacy `wellnessPlans` collection
    /// into `rehabPlans` so they appear in the My Plan tab.
    private func migrateWellnessPlansIfNeeded(uid: String) {
        let key = "wellnessPlansMigrated_\(uid)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        Task {
            do {
                let snapshot = try await db.collection("users").document(uid)
                    .collection("wellnessPlans").getDocuments()

                guard !snapshot.documents.isEmpty else {
                    UserDefaults.standard.set(true, forKey: key)
                    return
                }

                AppLogger.data.info("Migrating \(snapshot.documents.count) wellness plan(s) to rehabPlans")

                for doc in snapshot.documents {
                    let data = doc.data()
                    try await db.collection("users").document(uid)
                        .collection("rehabPlans").document(doc.documentID)
                        .setData(data)
                    try await doc.reference.delete()
                }

                UserDefaults.standard.set(true, forKey: key)
                SessionLogger.shared.log(.firestoreWrite, category: .data,
                                          message: "Migrated \(snapshot.documents.count) wellness plan(s) to rehabPlans")
            } catch {
                AppLogger.data.error("Wellness plan migration failed: \(error.localizedDescription)")
                SessionLogger.shared.logError(error, context: "WellnessPlanMigration")
            }
        }
    }

    /// Start real-time Firestore listener for rehab plans.
    /// Idempotent — if a listener is already active, this is a no-op.
    func startListening() {
        guard listenerRegistration == nil else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        migrateWellnessPlansIfNeeded(uid: uid)

        listenerRegistration = db.collection("users").document(uid).collection("rehabPlans")
            .order(by: "createdDate", descending: true)
            .limit(to: Self.rehabPlansFetchLimit)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.isLoading = false
                    if let error = error {
                        AppLogger.data.error("Error listening to rehab plans: \(error.localizedDescription)")
                        SessionLogger.shared.logError(error, context: "RehabPlansListener")
                        self.loadError = "Unable to load your rehab plans. Please pull down to retry."
                        return
                    }
                    self.loadError = nil
                    SessionLogger.shared.log(.firestoreRead, category: .data, message: "Rehab plans updated",
                                              metadata: ["count": "\(snapshot?.documents.count ?? 0)"])
                    self.rehabPlans = self.parsePlans(from: snapshot)
                }
            }
    }

    /// Stop the real-time listener (called on deinit).
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }

    /// Restart the listener (useful for pull-to-refresh or auth changes).
    func fetchRehabPlans() {
        stopListening()
        startListening()
    }

    // MARK: - Parsing

    private func parsePlans(from snapshot: QuerySnapshot?) -> [RehabPlan] {
        snapshot?.documents.compactMap { document -> RehabPlan? in
            let data = document.data()
            guard let idString = data["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let planName = data["planName"] as? String else {
                return nil
            }

            let exercises: [RehabExercise] = (data["exercises"] as? [[String: Any]] ?? []).compactMap { e in
                guard let eidStr = e["id"] as? String,
                      let eid = UUID(uuidString: eidStr),
                      let name = e["name"] as? String else { return nil }
                let diffStr = e["difficulty"] as? String ?? "beginner"
                let difficulty: RehabExercise.Difficulty
                switch diffStr {
                case "intermediate": difficulty = .intermediate
                case "advanced": difficulty = .advanced
                default: difficulty = .beginner
                }
                return RehabExercise(
                    id: eid,
                    name: name,
                    targetArea: e["targetArea"] as? String ?? "",
                    description: e["description"] as? String ?? "",
                    sets: e["sets"] as? Int ?? 3,
                    reps: e["reps"] as? String ?? "10",
                    restSeconds: e["restSeconds"] as? Int ?? 30,
                    difficulty: difficulty,
                    demonstrationIcon: e["demonstrationIcon"] as? String ?? "figure.flexibility",
                    tips: e["tips"] as? [String] ?? [],
                    contraindications: e["contraindications"] as? [String] ?? [],
                    startPosition: e["startPosition"] as? String,
                    movement: e["movement"] as? String,
                    endPosition: e["endPosition"] as? String,
                    exerciseCategory: e["exerciseCategory"] as? String,
                    imageFileName: e["imageFileName"] as? String
                )
            }

            // Decode weeklySchedule: supports both dictionary format (new) and nested array format (legacy)
            let weeklySchedule: [[String]]
            if let scheduleDict = data["weeklySchedule"] as? [String: [String]] {
                // New format: dictionary keyed by day index
                var schedule: [[String]] = Array(repeating: [], count: 7)
                for (key, exercises) in scheduleDict {
                    if let dayIndex = Int(key), dayIndex >= 0, dayIndex < 7 {
                        schedule[dayIndex] = exercises
                    }
                }
                weeklySchedule = schedule
            } else if let scheduleArray = data["weeklySchedule"] as? [[String]] {
                // Legacy format: nested array
                weeklySchedule = scheduleArray
            } else {
                weeklySchedule = []
            }

            return RehabPlan(
                id: id,
                planName: planName,
                conditions: data["conditions"] as? [String] ?? [],
                exercises: exercises,
                weeklySchedule: weeklySchedule,
                totalWeeks: data["totalWeeks"] as? Int ?? 4,
                createdDate: (data["createdDate"] as? Timestamp)?.dateValue() ?? Date(),
                notes: data["notes"] as? String,
                startDate: (data["startDate"] as? Timestamp)?.dateValue(),
                lastModifiedDate: (data["lastModifiedDate"] as? Timestamp)?.dateValue()
            )
        } ?? []
    }

    /// Update an existing plan in Firestore (for edits, startDate changes, etc.)
    func updatePlan(_ plan: RehabPlan) {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Update locally first
        if let index = rehabPlans.firstIndex(where: { $0.id == plan.id }) {
            rehabPlans[index] = plan
        }

        // Serialize exercises
        let exercisesData: [[String: Any]] = plan.exercises.map { e in
            var dict: [String: Any] = [
                "id": e.id.uuidString,
                "name": e.name,
                "targetArea": e.targetArea,
                "description": e.description,
                "sets": e.sets,
                "reps": e.reps,
                "restSeconds": e.restSeconds,
                "difficulty": e.difficulty.rawValue,
                "demonstrationIcon": e.demonstrationIcon,
                "tips": e.tips,
                "contraindications": e.contraindications
            ]
            if let sp = e.startPosition { dict["startPosition"] = sp }
            if let mv = e.movement { dict["movement"] = mv }
            if let ep = e.endPosition { dict["endPosition"] = ep }
            if let ec = e.exerciseCategory { dict["exerciseCategory"] = ec }
            if let img = e.imageFileName { dict["imageFileName"] = img }
            return dict
        }

        // Serialize weeklySchedule as dictionary format
        var scheduleDict: [String: [String]] = [:]
        for (index, day) in plan.weeklySchedule.enumerated() {
            if !day.isEmpty {
                scheduleDict["\(index)"] = day
            }
        }

        var planData: [String: Any] = [
            "id": plan.id.uuidString,
            "planName": plan.planName,
            "conditions": plan.conditions,
            "exercises": exercisesData,
            "weeklySchedule": scheduleDict,
            "totalWeeks": plan.totalWeeks,
            "createdDate": Timestamp(date: plan.createdDate)
        ]
        if let notes = plan.notes { planData["notes"] = notes }
        if let startDate = plan.startDate { planData["startDate"] = Timestamp(date: startDate) }
        if let lastMod = plan.lastModifiedDate { planData["lastModifiedDate"] = Timestamp(date: lastMod) }

        db.collection("users").document(uid).collection("rehabPlans")
            .document(plan.id.uuidString)
            .setData(planData) { error in
                if let error = error {
                    AppLogger.data.error("Error updating plan: \(error.localizedDescription)")
                }
            }
    }

    func deletePlan(_ plan: RehabPlan) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let planId = plan.id.uuidString

        SessionLogger.shared.log(.firestoreDelete, category: .data, message: "Rehab plan deleted",
                                  metadata: ["planId": planId])

        // Remove locally first for instant UI feedback
        rehabPlans.removeAll { $0.id == plan.id }

        // Remove from Firestore
        db.collection("users").document(uid).collection("rehabPlans")
            .document(planId)
            .delete { [weak self] error in
                if let error = error {
                    AppLogger.data.error("Error deleting plan: \(error.localizedDescription)")
                    // Re-fetch to restore consistent state
                    self?.fetchRehabPlans()
                }
            }
    }
}
