import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PT-Helper", category: "DailySnackScheduler")

// MARK: - Intermediate Decodable Types

private struct AISnackResponse: Decodable {
    let planName: String
    let exercises: [AISnackExercise]
    let totalWeeks: Int?
    let notes: String?
}

private struct AISnackExercise: Decodable {
    let name: String
    let targetArea: String
    let description: String
    let sets: Int
    let reps: String
    let restSeconds: Int
    let difficulty: String
    let demonstrationIcon: String
    let tips: [String]
    let contraindications: [String]
    let startPosition: String?
    let movement: String?
    let endPosition: String?
    let exerciseCategory: String?
    let imageFileName: String?
}

// MARK: - Daily Snack Scheduler

/// Singleton that manages today's movement snack — generating, caching, and serving
/// a pre-generated micro-routine based on the user's active wellness goals.
@MainActor
class DailySnackScheduler: ObservableObject {
    static let shared = DailySnackScheduler()

    @Published var currentSnack: RehabPlan?
    @Published var isGenerating: Bool = false

    private let cacheKeyPrefix = "DailyMovementSnack_"

    private var todayCacheKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return cacheKeyPrefix + formatter.string(from: Date())
    }

    private init() {
        loadFromCache()
    }

    // MARK: - Public API

    /// Load today's snack from cache, or generate a new one if needed.
    func loadOrGenerate(
        profile: UserProfile,
        wellnessGoals: [String],
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared
    ) async {
        // Already have today's snack
        if currentSnack != nil { return }

        // Check cache
        if let cached = loadFromCache() {
            currentSnack = cached
            return
        }

        // Generate new snack
        isGenerating = true
        do {
            let snack = try await generateSnack(profile: profile, wellnessGoals: wellnessGoals, apiService: apiService)
            currentSnack = snack
            saveToCache(snack)
            logger.info("Generated movement snack: \(snack.planName)")
        } catch {
            logger.warning("Snack generation failed: \(error.localizedDescription). Using static fallback.")
            let fallback = makeStaticSnack(timeOfDay: currentTimeOfDay(), goals: wellnessGoals)
            currentSnack = fallback
            saveToCache(fallback)
        }
        isGenerating = false
    }

    /// Force-regenerate tomorrow's snack (called after completing today's).
    func invalidateCache() {
        UserDefaults.standard.removeObject(forKey: todayCacheKey)
        currentSnack = nil
    }

    // MARK: - Generation

    private func generateSnack(
        profile: UserProfile,
        wellnessGoals: [String],
        apiService: ClaudeAPIServiceProtocol
    ) async throws -> RehabPlan {
        let timeOfDay = currentTimeOfDay()
        let goalsText = wellnessGoals.isEmpty ? "general mobility and wellness" : wellnessGoals.joined(separator: ", ")

        let message = """
        Generate a \(timeOfDay) movement snack for this person:
        - Activity Level: \(profile.activityLevel)
        - Wellness Goals: \(goalsText)
        - Time of Day: \(timeOfDay)
        - Equipment: none (bodyweight only)

        Keep it 3–5 exercises, time-based holds only (30–60 seconds each), 1 set each. Make it feel restorative and achievable, not like a workout.
        """

        let responseText = try await apiService.sendMessage(
            requestType: .generate_movement_snack,
            userMessage: message
        )

        return try parseSnackResponse(responseText)
    }

    // MARK: - Parsing

    private func parseSnackResponse(_ text: String) throws -> RehabPlan {
        guard let jsonData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(NSError(domain: "DailySnackScheduler", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"]))
        }

        let aiResponse: AISnackResponse
        do {
            aiResponse = try JSONDecoder().decode(AISnackResponse.self, from: jsonData)
        } catch let directError {
            // Fallback: extract JSON between first { and last }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex,
               let fallbackData = String(text[startIndex...endIndex]).data(using: .utf8) {
                aiResponse = try JSONDecoder().decode(AISnackResponse.self, from: fallbackData)
            } else {
                throw ClaudeAPIError.decodingError(directError)
            }
        }

        let exercises = aiResponse.exercises.prefix(5).map { ex in
            RehabExercise(
                id: UUID(),
                name: ex.name,
                targetArea: ex.targetArea,
                description: ex.description,
                sets: max(1, ex.sets),
                reps: ex.reps,
                restSeconds: min(ex.restSeconds, 10),
                difficulty: RehabExercise.Difficulty(rawValue: ex.difficulty) ?? .beginner,
                demonstrationIcon: ex.demonstrationIcon,
                tips: ex.tips,
                contraindications: ex.contraindications,
                startPosition: ex.startPosition,
                movement: ex.movement,
                endPosition: ex.endPosition,
                exerciseCategory: ex.exerciseCategory,
                imageFileName: ex.imageFileName
            )
        }

        return RehabPlan(
            id: UUID(),
            planName: aiResponse.planName,
            conditions: [],
            exercises: Array(exercises),
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 1,
            createdDate: Date(),
            notes: aiResponse.notes,
            planType: .movementSnack
        )
    }

    // MARK: - Cache

    @discardableResult
    private func loadFromCache() -> RehabPlan? {
        guard let data = UserDefaults.standard.data(forKey: todayCacheKey),
              let snack = try? JSONDecoder().decode(RehabPlan.self, from: data) else {
            return nil
        }
        if currentSnack == nil { currentSnack = snack }
        return snack
    }

    private func saveToCache(_ snack: RehabPlan) {
        if let data = try? JSONEncoder().encode(snack) {
            UserDefaults.standard.set(data, forKey: todayCacheKey)
        }
    }

    // MARK: - Time of Day

    func currentTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "morning"
        case 11..<14: return "midday"
        case 17..<21: return "evening"
        default: return "anytime"
        }
    }

    var timeOfDayLabel: String {
        switch currentTimeOfDay() {
        case "morning": return "Morning"
        case "midday": return "Midday"
        case "evening": return "Evening"
        default: return "Today's"
        }
    }

    var timeOfDayIcon: String {
        switch currentTimeOfDay() {
        case "morning": return "sun.horizon.fill"
        case "midday": return "sun.max.fill"
        case "evening": return "moon.stars.fill"
        default: return "figure.flexibility"
        }
    }

    // MARK: - Static Fallback

    private func makeStaticSnack(timeOfDay: String, goals: [String]) -> RehabPlan {
        let exercises: [RehabExercise]
        switch timeOfDay {
        case "morning":
            exercises = [
                RehabExercise(id: UUID(), name: "Cat-Cow Stretch", targetArea: "Spine",
                    description: "Gentle spinal flexion and extension.", sets: 1, reps: "45 seconds",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.yoga",
                    tips: ["Breathe slowly", "Move gently"], contraindications: [],
                    startPosition: "On hands and knees, wrists under shoulders.",
                    movement: "Inhale to arch (cow), exhale to round (cat).",
                    endPosition: "Return to neutral and repeat.", exerciseCategory: "mobility", imageFileName: nil),
                RehabExercise(id: UUID(), name: "Seated Neck Rolls", targetArea: "Neck",
                    description: "Release neck tension with slow circular movements.", sets: 1, reps: "30 seconds",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.seated.side",
                    tips: ["Keep shoulders relaxed"], contraindications: [],
                    startPosition: "Sit tall, shoulders relaxed.",
                    movement: "Slowly roll head in a half-circle from shoulder to shoulder.",
                    endPosition: "Return to center.", exerciseCategory: "stretch", imageFileName: nil),
                RehabExercise(id: UUID(), name: "Hip Flexor Hold", targetArea: "Hip",
                    description: "Open the hip flexors to counter overnight compression.", sets: 1, reps: "30 seconds each side",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.flexibility",
                    tips: ["Keep your back tall"], contraindications: [],
                    startPosition: "Kneel on one knee, other foot forward.",
                    movement: "Gently push hips forward until you feel a stretch in the front of the back hip.",
                    endPosition: "Hold and breathe deeply. Switch sides.", exerciseCategory: "stretch", imageFileName: nil)
            ]
        case "midday":
            exercises = [
                RehabExercise(id: UUID(), name: "Chest Opener", targetArea: "Chest/Shoulders",
                    description: "Reverse the effects of forward-hunched sitting.", sets: 1, reps: "30 seconds",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.cooldown",
                    tips: ["Don't hold your breath"], contraindications: [],
                    startPosition: "Stand tall, clasp hands behind your back.",
                    movement: "Gently squeeze shoulder blades together and lift chest toward the ceiling.",
                    endPosition: "Hold and breathe. Release slowly.", exerciseCategory: "stretch", imageFileName: nil),
                RehabExercise(id: UUID(), name: "Standing Hip Circles", targetArea: "Hip",
                    description: "Lubricate the hip joints and reset posture.", sets: 1, reps: "30 seconds",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.stand",
                    tips: ["Keep circles slow and controlled"], contraindications: [],
                    startPosition: "Stand with feet hip-width apart, hands on hips.",
                    movement: "Rotate hips in large, slow circles.",
                    endPosition: "Switch direction halfway through.", exerciseCategory: "mobility", imageFileName: nil),
                RehabExercise(id: UUID(), name: "Thoracic Rotation", targetArea: "Upper Back",
                    description: "Restore rotational mobility lost from sitting.", sets: 1, reps: "30 seconds each side",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.yoga",
                    tips: ["Rotate from your mid-back, not neck"], contraindications: [],
                    startPosition: "Sit tall at edge of chair, feet flat.",
                    movement: "Place hand behind head and rotate upper body, keeping hips still.",
                    endPosition: "Hold at end range. Return and switch.", exerciseCategory: "mobility", imageFileName: nil)
            ]
        default: // evening or anytime
            exercises = [
                RehabExercise(id: UUID(), name: "Supine Twist", targetArea: "Lower Back",
                    description: "Release spinal tension built up during the day.", sets: 1, reps: "45 seconds each side",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.roll",
                    tips: ["Let gravity do the work"], contraindications: [],
                    startPosition: "Lie on your back, knees bent.",
                    movement: "Let both knees fall to one side, arms out wide.",
                    endPosition: "Breathe and hold. Switch sides.", exerciseCategory: "stretch", imageFileName: nil),
                RehabExercise(id: UUID(), name: "Legs Up the Wall", targetArea: "Hamstrings/Circulation",
                    description: "Restore circulation and calm the nervous system.", sets: 1, reps: "60 seconds",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.roll",
                    tips: ["Close your eyes and breathe deeply"], contraindications: [],
                    startPosition: "Lie next to a wall, scoot hips close.",
                    movement: "Rest legs straight up the wall. Relax completely.",
                    endPosition: "Breathe slowly for the full duration.", exerciseCategory: "stretch", imageFileName: nil),
                RehabExercise(id: UUID(), name: "Child's Pose", targetArea: "Back/Hips",
                    description: "Full body release to end the day.", sets: 1, reps: "45 seconds",
                    restSeconds: 5, difficulty: .beginner, demonstrationIcon: "figure.yoga",
                    tips: ["Breathe into your lower back"], contraindications: [],
                    startPosition: "Kneel, then sit back toward your heels.",
                    movement: "Walk hands forward and rest forehead on the floor.",
                    endPosition: "Hold and breathe deeply.", exerciseCategory: "yoga", imageFileName: nil)
            ]
        }

        let names = ["Morning Spine Reset", "Midday Desk Rescue", "Evening Wind-Down", "Quick Reset"]
        let planName: String
        switch timeOfDay {
        case "morning": planName = names[0]
        case "midday": planName = names[1]
        case "evening": planName = names[2]
        default: planName = names[3]
        }

        return RehabPlan(
            id: UUID(),
            planName: planName,
            conditions: [],
            exercises: exercises,
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: 1,
            createdDate: Date(),
            notes: "A 3-minute movement break to keep your body feeling good.",
            planType: .movementSnack
        )
    }
}
