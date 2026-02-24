import Foundation

struct RehabPlan: Codable, Identifiable {
    let id: UUID
    let planName: String
    let conditions: [String]
    let exercises: [RehabExercise]
    let weeklySchedule: [[String]]
    let totalWeeks: Int
    let createdDate: Date
    let notes: String?
}

struct RehabExercise: Codable, Identifiable {
    let id: UUID
    let name: String
    let targetArea: String
    let description: String
    let sets: Int
    let reps: String
    let restSeconds: Int
    let difficulty: Difficulty
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
