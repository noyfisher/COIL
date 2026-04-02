import Foundation

struct WorkoutSession: Identifiable, Codable {
    var id: UUID
    var date: Date
    var duration: TimeInterval
    var painLevel: Double
    var isCompleted: Bool
    var exercisesPerformed: [String]
    /// Exercises explicitly skipped during this session. Nil for legacy sessions.
    var skippedExercises: [String]?
    var notes: String?
    /// Per-region pain levels (e.g. ["left_knee": 3, "right_shoulder": 5]). Nil for legacy sessions.
    var regionPainLevels: [String: Double]?
    /// Links this session to the rehab plan it was performed under.
    var planId: UUID?

    /// Backward-compatible initializer for existing Firestore data
    init(id: UUID, date: Date, duration: TimeInterval, painLevel: Double, isCompleted: Bool,
         exercisesPerformed: [String] = [], skippedExercises: [String]? = nil,
         notes: String? = nil, regionPainLevels: [String: Double]? = nil, planId: UUID? = nil) {
        self.id = id
        self.date = date
        self.duration = duration
        self.painLevel = painLevel
        self.isCompleted = isCompleted
        self.exercisesPerformed = exercisesPerformed
        self.skippedExercises = skippedExercises
        self.notes = notes
        self.regionPainLevels = regionPainLevels
        self.planId = planId
    }
}
