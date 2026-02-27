import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class WorkoutViewModel: ObservableObject {
    @Published var sessions: [WorkoutSession] = []
    @Published var loadError: String?
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    init() {
        fetchSessions()
    }

    func fetchSessions() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        db.collection("users").document(uid).collection("workoutSessions")
            .order(by: "date", descending: true)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoading = false
                    if let error = error {
                        AppLogger.data.error("Error fetching workout sessions: \(error.localizedDescription)")
                        self.loadError = "Unable to load your workouts. Pull down to retry."
                        return
                    }
                    self.loadError = nil
                    self.sessions = snapshot?.documents.compactMap { document -> WorkoutSession? in
                        let data = document.data()
                        guard let idString = data["id"] as? String,
                              let id = UUID(uuidString: idString) else {
                            return nil
                        }
                        let date = (data["date"] as? Timestamp)?.dateValue() ?? Date()
                        let duration = data["duration"] as? TimeInterval ?? 0
                        let painLevel = data["painLevel"] as? Double ?? 0
                        let isCompleted = data["isCompleted"] as? Bool ?? false
                        let exercisesPerformed = data["exercisesPerformed"] as? [String] ?? []
                        let notes = data["notes"] as? String
                        return WorkoutSession(
                            id: id,
                            date: date,
                            duration: duration,
                            painLevel: painLevel,
                            isCompleted: isCompleted,
                            exercisesPerformed: exercisesPerformed,
                            notes: notes
                        )
                    } ?? []
                }
            }
    }

    func addSession(session: WorkoutSession) {
        sessions.insert(session, at: 0) // Add to top since sorted by newest first

        // Persist to Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        var sessionData: [String: Any] = [
            "id": session.id.uuidString,
            "date": Timestamp(date: session.date),
            "duration": session.duration,
            "painLevel": session.painLevel,
            "isCompleted": session.isCompleted,
            "exercisesPerformed": session.exercisesPerformed
        ]
        if let notes = session.notes {
            sessionData["notes"] = notes
        }
        db.collection("users").document(uid).collection("workoutSessions")
            .document(session.id.uuidString)
            .setData(sessionData) { error in
                if let error = error {
                    AppLogger.data.error("Error saving workout session: \(error.localizedDescription)")
                }
            }
    }
}
