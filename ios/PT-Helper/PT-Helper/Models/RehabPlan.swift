import Foundation

struct RehabPlan: Codable, Identifiable {

    enum PlanType: String, Codable {
        case rehab
        case wellness
        case movementSnack
    }

    let id: UUID
    var planName: String
    let conditions: [String]
    var exercises: [RehabExercise]
    var weeklySchedule: [[String]]
    let totalWeeks: Int
    var createdDate: Date
    let notes: String?
    /// When the user started following this plan (nil = not started yet)
    var startDate: Date?
    /// Timestamp of last user edit (nil = never edited)
    var lastModifiedDate: Date?
    /// Whether this is a rehab or wellness plan (defaults to .rehab for backward compatibility)
    var planType: PlanType = .rehab
    /// Wellness goal categories that generated this plan (nil for rehab plans)
    var sourceGoalCategories: [String]?

    /// Current week number (1-based) based on startDate, or nil if not started
    var currentWeek: Int? {
        guard let start = startDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return min(max(days / 7 + 1, 1), totalWeeks)
    }
}

struct RehabExercise: Codable, Identifiable {
    let id: UUID
    var name: String
    var targetArea: String
    var description: String
    var sets: Int
    var reps: String
    var restSeconds: Int
    var difficulty: Difficulty
    let demonstrationIcon: String
    let tips: [String]
    let contraindications: [String]

    // Structured visual instruction fields (optional for backward compatibility)
    let startPosition: String?
    let movement: String?
    let endPosition: String?
    let exerciseCategory: String?

    // AI-generated exercise image filename (optional, nil = SF Symbol fallback)
    let imageFileName: String?

    enum Difficulty: String, Codable, CaseIterable {
        case beginner, intermediate, advanced
    }

    init(id: UUID, name: String, targetArea: String, description: String, sets: Int, reps: String, restSeconds: Int, difficulty: Difficulty, demonstrationIcon: String, tips: [String], contraindications: [String], startPosition: String? = nil, movement: String? = nil, endPosition: String? = nil, exerciseCategory: String? = nil, imageFileName: String? = nil) {
        self.id = id
        self.name = name
        self.targetArea = targetArea
        self.description = description
        self.sets = sets
        self.reps = reps
        self.restSeconds = restSeconds
        self.difficulty = difficulty
        self.demonstrationIcon = demonstrationIcon
        self.tips = tips
        self.contraindications = contraindications
        self.startPosition = startPosition
        self.movement = movement
        self.endPosition = endPosition
        self.exerciseCategory = exerciseCategory
        self.imageFileName = imageFileName
    }
}
