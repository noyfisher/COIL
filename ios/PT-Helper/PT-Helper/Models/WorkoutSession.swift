import Foundation

struct WorkoutSession: Identifiable, Codable {
    var id: UUID
    var date: Date
    var duration: TimeInterval
    var painLevel: Double
    var isCompleted: Bool
    var exercisesPerformed: [String]
    var notes: String?

    /// Backward-compatible initializer for existing Firestore data
    init(id: UUID, date: Date, duration: TimeInterval, painLevel: Double, isCompleted: Bool, exercisesPerformed: [String] = [], notes: String? = nil) {
        self.id = id
        self.date = date
        self.duration = duration
        self.painLevel = painLevel
        self.isCompleted = isCompleted
        self.exercisesPerformed = exercisesPerformed
        self.notes = notes
    }
}
