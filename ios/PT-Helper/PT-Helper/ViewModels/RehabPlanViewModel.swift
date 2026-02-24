import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

// MARK: - Intermediate Decodable Types for AI Rehab Response

private struct AIRehabResponse: Decodable {
    let planName: String
    let exercises: [AIRehabExercise]
    let totalWeeks: Int
    let notes: String?
}

private struct AIRehabExercise: Decodable {
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

@MainActor
class RehabPlanViewModel: ObservableObject {
    @Published var rehabPlan: RehabPlan?
    @Published var isSaving = false
    @Published var showSaveSuccess = false
    @Published var saveError: String? = nil
    @Published var isGenerating: Bool = false
    @Published var generationError: String? = nil

    private let db = Firestore.firestore()

    // Fallback exercise database organized by condition name
    private let exerciseDatabase: [String: [RehabExercise]] = [
        "Patellofemoral Pain Syndrome": [
            RehabExercise(id: UUID(), name: "Quad Sets", targetArea: "Knee", description: "Sit with your leg straight. Tighten the muscle on top of your thigh by pressing the back of your knee into the floor. Hold for 5 seconds, then relax.", sets: 3, reps: "10-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Keep your leg straight.", "Press knee firmly into the floor.", "You should see your kneecap move upward."], contraindications: ["Avoid if acute knee swelling is present."], startPosition: "Sit on the floor or bed with your affected leg straight out in front of you", movement: "Tighten the muscle on top of your thigh by pressing the back of your knee firmly into the floor. Hold for 5 seconds", endPosition: "Release the tension and let your leg rest flat. Repeat.", exerciseCategory: "strength", imageFileName: "quad-sets"),
            RehabExercise(id: UUID(), name: "Straight Leg Raises", targetArea: "Knee", description: "Lie on your back with one knee bent. Keeping the other leg straight, tighten the quad and lift the leg to 45 degrees. Hold 2 seconds, lower slowly.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your core engaged.", "Lift slowly and with control.", "Don't arch your back."], contraindications: ["Avoid if hip pain worsens."], startPosition: "Lie on your back with one knee bent and foot flat on the floor. Keep the other leg straight", movement: "Tighten your quad, then slowly lift the straight leg to about 45 degrees. Hold for 2 seconds", endPosition: "Lower the leg slowly back to the floor with control", exerciseCategory: "strength", imageFileName: "straight-leg-raises"),
            RehabExercise(id: UUID(), name: "Wall Sits", targetArea: "Knee", description: "Stand with your back against a wall. Slide down until your knees are bent to about 45 degrees. Hold the position.", sets: 3, reps: "30 seconds", restSeconds: 45, difficulty: .intermediate, demonstrationIcon: "figure.cooldown", tips: ["Keep knees behind toes.", "Press your back flat against the wall.", "Start with a shallow bend and go deeper as you get stronger."], contraindications: ["Avoid deep bending if knee pain increases."], startPosition: "Stand with your back flat against a wall, feet shoulder-width apart and about 2 feet from the wall", movement: "Slowly slide your back down the wall until your knees are bent to about 45 degrees. Hold this position", endPosition: "Slide back up the wall to standing", exerciseCategory: "strength", imageFileName: "wall-sits"),
            RehabExercise(id: UUID(), name: "Clamshells", targetArea: "Hip/Knee", description: "Lie on your side with knees bent to 45 degrees. Keeping your feet together, raise your top knee as high as you can without rotating your pelvis. Lower slowly.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Keep your feet together throughout.", "Don't roll your hips backward.", "Focus on squeezing the glute."], contraindications: ["Avoid if hip pain is present."], startPosition: "Lie on your side with knees bent to 45 degrees, feet together, head resting on your arm", movement: "Keeping your feet together, raise your top knee as high as you can without rotating your pelvis", endPosition: "Lower your knee slowly back to the starting position", exerciseCategory: "strength", imageFileName: "clamshells")
        ],
        "Meniscus Tear": [
            RehabExercise(id: UUID(), name: "Heel Slides", targetArea: "Knee", description: "Lie on your back. Slowly slide your heel toward your buttock, bending your knee. Slide back to the starting position.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Move slowly and smoothly.", "Only go as far as comfortable.", "Use a towel under your heel to reduce friction."], contraindications: ["Stop if you feel locking or catching."], startPosition: "Lie on your back with both legs straight on the floor", movement: "Slowly slide your heel along the floor toward your buttock, bending your knee as far as comfortable", endPosition: "Slide your heel back to the straight position", exerciseCategory: "mobility", imageFileName: "heel-slides"),
            RehabExercise(id: UUID(), name: "Step-Ups", targetArea: "Knee", description: "Step up onto a low step with your affected leg. Straighten your knee fully, then step back down slowly.", sets: 3, reps: "10", restSeconds: 45, difficulty: .intermediate, demonstrationIcon: "figure.stairs", tips: ["Use a handrail for balance.", "Keep your knee aligned over your toes.", "Control the descent."], contraindications: ["Avoid if knee gives way or locks."], startPosition: "Stand in front of a low step (6-8 inches) with feet hip-width apart", movement: "Step up with your affected leg, pressing through your heel to straighten your knee fully on top", endPosition: "Step back down slowly with control, leading with the unaffected leg", exerciseCategory: "stair", imageFileName: "step-ups")
        ],
        "Rotator Cuff Strain": [
            RehabExercise(id: UUID(), name: "Pendulum Swings", targetArea: "Shoulder", description: "Lean forward with your unaffected hand on a table. Let your affected arm hang down and swing in small circles, then back and forth.", sets: 2, reps: "30 seconds each direction", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep your arm relaxed.", "Let gravity do the work.", "Gradually increase the circle size."], contraindications: ["Avoid if severe shoulder pain is present."], startPosition: "Lean forward at the waist, supporting yourself with your unaffected hand on a table. Let your affected arm hang straight down", movement: "Gently swing your arm in small circles clockwise, then counterclockwise, then forward and back", endPosition: "Let your arm come to rest hanging straight down", exerciseCategory: "mobility", imageFileName: "pendulum-swings"),
            RehabExercise(id: UUID(), name: "External Rotation", targetArea: "Shoulder", description: "Stand with your elbow bent 90 degrees at your side. Rotate your forearm outward away from your body, keeping elbow tucked.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your elbow at your side.", "Move slowly with control.", "Use a light resistance band if available."], contraindications: ["Stop if sharp pain occurs."], startPosition: "Stand with your elbow bent 90 degrees and tucked against your side, forearm pointing forward", movement: "Rotate your forearm outward away from your body while keeping your elbow firmly against your side", endPosition: "Slowly rotate back to the starting position with your forearm pointing forward", exerciseCategory: "strength", imageFileName: "external-rotation"),
            RehabExercise(id: UUID(), name: "Scapular Squeezes", targetArea: "Upper Back/Shoulder", description: "Sit or stand with arms at your sides. Squeeze your shoulder blades together as if pinching a pencil between them. Hold 5 seconds.", sets: 3, reps: "10-12", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.cooldown", tips: ["Keep shoulders down, away from ears.", "Don't shrug.", "Breathe normally while holding."], contraindications: ["Avoid if thoracic spine pain increases."], startPosition: "Sit or stand upright with arms relaxed at your sides, shoulders down", movement: "Squeeze your shoulder blades together as if pinching a pencil between them. Hold for 5 seconds", endPosition: "Slowly release and let your shoulders return to a relaxed position", exerciseCategory: "strength", imageFileName: "scapular-squeezes"),
            RehabExercise(id: UUID(), name: "Wall Slides", targetArea: "Shoulder", description: "Stand with your back against a wall, arms in a goalpost position. Slowly slide arms up the wall overhead, then back down.", sets: 3, reps: "10", restSeconds: 30, difficulty: .intermediate, demonstrationIcon: "figure.flexibility", tips: ["Keep your back flat against the wall.", "Only go as high as comfortable.", "Focus on smooth movement."], contraindications: ["Avoid if impingement symptoms worsen."], startPosition: "Stand with your back against a wall, arms in a goalpost position (elbows bent 90 degrees at shoulder height)", movement: "Slowly slide your arms up the wall overhead, keeping your back and arms in contact with the wall", endPosition: "Slide arms back down to the goalpost position", exerciseCategory: "mobility", imageFileName: "wall-slides")
        ],
        "Muscle Strain": [
            RehabExercise(id: UUID(), name: "Cat-Cow Stretch", targetArea: "Back", description: "On hands and knees, alternate between arching your back up (cat) and letting it sag down (cow). Move slowly with your breath.", sets: 2, reps: "10", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Inhale on cow, exhale on cat.", "Move through each position slowly.", "Keep your core lightly engaged."], contraindications: ["Avoid if back pain significantly worsens."], startPosition: "Get on your hands and knees with wrists under shoulders and knees under hips", movement: "Exhale and round your back up toward the ceiling (cat). Then inhale and let your belly drop toward the floor, lifting your head (cow)", endPosition: "Return to a flat-back neutral position on hands and knees", exerciseCategory: "stretch", imageFileName: "cat-cow-stretch"),
            RehabExercise(id: UUID(), name: "Glute Bridges", targetArea: "Back/Glutes", description: "Lie on your back with knees bent. Squeeze your glutes and lift your hips toward the ceiling. Hold 2 seconds at the top.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Don't arch your lower back excessively.", "Squeeze glutes at the top.", "Keep your core engaged."], contraindications: ["Avoid if acute back spasm is present."], startPosition: "Lie on your back with knees bent, feet flat on the floor hip-width apart, arms at your sides", movement: "Squeeze your glutes and press through your heels to lift your hips toward the ceiling until your body forms a straight line from shoulders to knees. Hold for 2 seconds", endPosition: "Lower your hips slowly back to the floor", exerciseCategory: "strength", imageFileName: "glute-bridges"),
            RehabExercise(id: UUID(), name: "Bird Dog", targetArea: "Core/Back", description: "On hands and knees, extend one arm forward and the opposite leg backward. Hold for 3 seconds, return, and switch sides.", sets: 3, reps: "8 each side", restSeconds: 30, difficulty: .intermediate, demonstrationIcon: "figure.yoga", tips: ["Keep your back flat like a table.", "Don't rotate your hips.", "Engage your core throughout."], contraindications: ["Modify if shoulder or hip pain occurs."], startPosition: "Get on your hands and knees with a flat back, wrists under shoulders and knees under hips", movement: "Extend your right arm straight forward and your left leg straight back at the same time. Hold for 3 seconds", endPosition: "Return your arm and leg to the floor. Repeat on the opposite side", exerciseCategory: "core", imageFileName: "bird-dog")
        ],
        "Herniated Disc": [
            RehabExercise(id: UUID(), name: "Pelvic Tilts", targetArea: "Lower Back", description: "Lie on your back with knees bent. Flatten your lower back against the floor by tilting your pelvis. Hold 5 seconds.", sets: 3, reps: "10-12", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Think of pulling your belly button to your spine.", "Breathe normally.", "The movement is subtle."], contraindications: ["Stop if radiating leg pain worsens."], startPosition: "Lie on your back with knees bent, feet flat on the floor, arms at your sides", movement: "Gently flatten your lower back against the floor by tilting your pelvis upward. Hold for 5 seconds", endPosition: "Relax and let your back return to its natural position", exerciseCategory: "core", imageFileName: "pelvic-tilts"),
            RehabExercise(id: UUID(), name: "Child's Pose", targetArea: "Lower Back", description: "Kneel on the floor, sit back on your heels, and stretch your arms forward on the floor. Hold the position and breathe deeply.", sets: 2, reps: "30 seconds", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.yoga", tips: ["Relax into the stretch.", "Breathe deeply.", "Widen your knees if needed."], contraindications: ["Avoid if knee pain prevents kneeling."], startPosition: "Kneel on the floor with your knees together or slightly apart", movement: "Sit your hips back onto your heels and stretch your arms forward along the floor. Rest your forehead on the ground", endPosition: "Slowly walk your hands back and sit upright", exerciseCategory: "stretch", imageFileName: "childs-pose")
        ],
        "Impingement Syndrome": [
            RehabExercise(id: UUID(), name: "Doorway Stretch", targetArea: "Chest/Shoulder", description: "Stand in a doorway with arms on the frame at 90 degrees. Step forward to stretch the front of your shoulders and chest.", sets: 3, reps: "30 seconds", restSeconds: 20, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Keep your core tight.", "Don't lean too far forward.", "You should feel the stretch across your chest."], contraindications: ["Avoid if shoulder pops or clicks."], startPosition: "Stand in a doorway with both arms on the door frame, elbows bent at 90 degrees at shoulder height", movement: "Step one foot forward through the doorway until you feel a gentle stretch across your chest and the front of your shoulders. Hold", endPosition: "Step back to the starting position and relax your arms", exerciseCategory: "stretch", imageFileName: "doorway-stretch")
        ],
        "ACL Sprain": [
            RehabExercise(id: UUID(), name: "Hamstring Curls", targetArea: "Knee/Hamstring", description: "Stand holding a chair for balance. Slowly bend your knee to bring your heel toward your buttock. Lower slowly.", sets: 3, reps: "12-15", restSeconds: 30, difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional", tips: ["Keep your thighs parallel.", "Control the movement.", "Use ankle weights for progression."], contraindications: ["Avoid if knee instability is severe."], startPosition: "Stand upright holding the back of a chair for balance, feet hip-width apart", movement: "Slowly bend your affected knee to bring your heel toward your buttock as far as comfortable", endPosition: "Lower your foot slowly back to the floor with control", exerciseCategory: "strength", imageFileName: "hamstring-curls")
        ]
    ]

    /// Generate a rehab plan using AI, with fallback to hardcoded database
    func generateRehabPlan(from analysisResult: AnalysisResult) {
        let conditions = analysisResult.conditions.map { $0.conditionName }

        isGenerating = true
        generationError = nil

        Task {
            do {
                let plan = try await generateAIRehabPlan(from: analysisResult)
                self.rehabPlan = plan
                self.isGenerating = false
                // Preload exercise images in background
                ExerciseImageService.shared.preloadImages(for: plan.exercises)
                // Log exercises that don't have images yet
                logMissingImages(exercises: plan.exercises, source: "ai")
            } catch {
                // Fallback to hardcoded database
                AppLogger.rehab.warning("AI rehab generation failed, using fallback: \(error.localizedDescription)")
                let exercises = conditions.flatMap { exerciseDatabase[$0] ?? [] }
                let finalExercises = exercises.isEmpty ? getGeneralExercises() : exercises

                let weeklySchedule = createWeeklySchedule(
                    for: finalExercises,
                    activityLevel: analysisResult.userProfileSnapshot.activityLevel
                )

                let fallbackPlan = RehabPlan(
                    id: UUID(),
                    planName: "Personalized Rehab Plan",
                    conditions: conditions,
                    exercises: finalExercises,
                    weeklySchedule: weeklySchedule,
                    totalWeeks: 4,
                    createdDate: Date(),
                    notes: nil
                )
                self.rehabPlan = fallbackPlan
                self.isGenerating = false
                // Preload exercise images in background
                ExerciseImageService.shared.preloadImages(for: finalExercises)
                // Log exercises that don't have images yet
                logMissingImages(exercises: finalExercises, source: "fallback")
            }
        }
    }

    // MARK: - AI Rehab Plan Generation

    private func generateAIRehabPlan(from analysisResult: AnalysisResult) async throws -> RehabPlan {
        let systemPrompt = buildRehabSystemPrompt()
        let userMessage = buildRehabUserMessage(from: analysisResult)

        let responseText = try await ClaudeAPIService.shared.sendMessage(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        return try parseRehabPlanResponse(
            responseText,
            conditions: analysisResult.conditions.map { $0.conditionName },
            activityLevel: analysisResult.userProfileSnapshot.activityLevel
        )
    }

    private func buildRehabSystemPrompt() -> String {
        """
        You are a PT rehabilitation specialist. Create personalized exercise plans for musculoskeletal conditions. Educational purposes only.

        RULES:
        - Create 4-8 exercises with clear instructions, sets, reps, rest periods
        - Match difficulty to activity level: sedentary→beginner, moderate→beginner+intermediate, active→intermediate+advanced
        - Use SF Symbol icons: "figure.flexibility", "figure.strengthtraining.traditional", "figure.cooldown", "figure.yoga", "figure.walk", "figure.stairs", "figure.core.training", "figure.run", "figure.stand", "figure.roll", "figure.seated.side", "figure.pool.swim", "figure.outdoor.cycle", "figure.mixed.cardio"
        - Include 2-3 form tips and 1-2 contraindications per exercise
        - For startPosition: describe exactly how to position your body BEFORE the movement (1-2 sentences, simple language a beginner can follow)
        - For movement: describe the motion step by step (1-2 sentences, simple language)
        - For endPosition: describe the end of the movement and how to return (1 sentence)
        - For exerciseCategory: choose ONE of: "stretch", "strength", "balance", "cardio", "mobility", "core", "yoga", "walking", "seated", "lying", "standing", "stair"
        - For imageFileName: create a normalized lowercase kebab-case filename for the exercise (e.g. "quad-sets", "glute-bridges", "cat-cow-stretch"). Use only lowercase letters, numbers, and hyphens.

        Respond ONLY with valid JSON (no markdown):
        {"planName":"string","exercises":[{"name":"string","targetArea":"string","description":"string","sets":number,"reps":"string","restSeconds":number,"difficulty":"beginner|intermediate|advanced","demonstrationIcon":"string","tips":["strings"],"contraindications":["strings"],"startPosition":"string","movement":"string","endPosition":"string","exerciseCategory":"string","imageFileName":"string"}],"totalWeeks":number(4-8),"notes":"string or null"}
        """
    }

    private func buildRehabUserMessage(from analysisResult: AnalysisResult) -> String {
        let profile = analysisResult.userProfileSnapshot

        var message = """
        PATIENT PROFILE:
        - Age: \(profile.age) years old
        - Sex: \(profile.sex)
        - Height: \(profile.heightFeet)'\(profile.heightInches)"
        - Weight: \(Int(profile.weight)) lbs
        - Activity Level: \(profile.activityLevel)
        """

        if let sport = profile.primarySport, !sport.isEmpty {
            message += "\n- Primary Sport/Activity: \(sport)"
        }

        if !profile.medicalConditions.isEmpty {
            message += "\n- Medical Conditions: \(profile.medicalConditions.joined(separator: ", "))"
        }

        if !profile.surgeries.isEmpty {
            let surgeryList = profile.surgeries.map { "\($0.name) (\($0.year))" }.joined(separator: ", ")
            message += "\n- Past Surgeries: \(surgeryList)"
        }

        if !profile.injuries.isEmpty {
            let injuryList = profile.injuries.map { injury in
                let status = injury.isCurrent ? "current" : "past"
                return "\(injury.bodyArea): \(injury.description) (\(status))"
            }.joined(separator: "; ")
            message += "\n- Injuries: \(injuryList)"
        }

        message += "\n\nIDENTIFIED CONDITIONS:\n"

        for condition in analysisResult.conditions {
            message += "- \(condition.conditionName) (Confidence: \(Int(condition.confidence))%)\n"
            message += "  Explanation: \(condition.explanation)\n"
        }

        message += "\nPlease create a personalized rehabilitation exercise plan for this patient."

        return message
    }

    private func parseRehabPlanResponse(_ text: String, conditions: [String], activityLevel: String) throws -> RehabPlan {
        guard let jsonData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(NSError(domain: "RehabPlan", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"]))
        }

        let aiResponse: AIRehabResponse
        do {
            aiResponse = try JSONDecoder().decode(AIRehabResponse.self, from: jsonData)
        } catch {
            // Fallback: extract JSON between { and }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}") {
                let jsonSubstring = String(text[startIndex...endIndex])
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    do {
                        aiResponse = try JSONDecoder().decode(AIRehabResponse.self, from: fallbackData)
                    } catch {
                        throw ClaudeAPIError.decodingError(error)
                    }
                } else {
                    throw ClaudeAPIError.decodingError(error)
                }
            } else {
                throw ClaudeAPIError.decodingError(error)
            }
        }

        // Map AI exercises to our model
        let exercises = aiResponse.exercises.map { aiExercise in
            let difficulty: RehabExercise.Difficulty
            switch aiExercise.difficulty.lowercased() {
            case "intermediate": difficulty = .intermediate
            case "advanced": difficulty = .advanced
            default: difficulty = .beginner
            }

            return RehabExercise(
                id: UUID(),
                name: aiExercise.name,
                targetArea: aiExercise.targetArea,
                description: aiExercise.description,
                sets: aiExercise.sets,
                reps: aiExercise.reps,
                restSeconds: aiExercise.restSeconds,
                difficulty: difficulty,
                demonstrationIcon: aiExercise.demonstrationIcon,
                tips: aiExercise.tips,
                contraindications: aiExercise.contraindications,
                startPosition: aiExercise.startPosition,
                movement: aiExercise.movement,
                endPosition: aiExercise.endPosition,
                exerciseCategory: aiExercise.exerciseCategory,
                imageFileName: aiExercise.imageFileName
            )
        }

        let weeklySchedule = createWeeklySchedule(for: exercises, activityLevel: activityLevel)

        return RehabPlan(
            id: UUID(),
            planName: aiResponse.planName,
            conditions: conditions,
            exercises: exercises,
            weeklySchedule: weeklySchedule,
            totalWeeks: aiResponse.totalWeeks,
            createdDate: Date(),
            notes: aiResponse.notes
        )
    }

    // MARK: - Schedule & Fallback

    private func createWeeklySchedule(for exercises: [RehabExercise], activityLevel: String) -> [[String]] {
        let exerciseDays: Int
        switch activityLevel.lowercased() {
        case "sedentary", "lightly active":
            exerciseDays = 3
        case "moderately active":
            exerciseDays = 4
        case "very active", "athlete":
            exerciseDays = 5
        default:
            exerciseDays = 3
        }

        let exerciseIds = exercises.map { $0.id.uuidString }
        var schedule: [[String]] = Array(repeating: [], count: 7)

        // Distribute exercises across the week with rest days
        let dayIndices: [Int]
        switch exerciseDays {
        case 3: dayIndices = [1, 3, 5] // Mon, Wed, Fri
        case 4: dayIndices = [1, 2, 4, 5] // Mon, Tue, Thu, Fri
        case 5: dayIndices = [1, 2, 3, 4, 5] // Mon-Fri
        default: dayIndices = [1, 3, 5]
        }

        for dayIndex in dayIndices {
            schedule[dayIndex] = exerciseIds
        }

        return schedule
    }

    private func getGeneralExercises() -> [RehabExercise] {
        [
            RehabExercise(id: UUID(), name: "Gentle Stretching", targetArea: "Full Body", description: "Perform gentle full-body stretches, holding each for 15-30 seconds. Focus on areas of tightness.", sets: 1, reps: "5-10 minutes", restSeconds: 0, difficulty: .beginner, demonstrationIcon: "figure.flexibility", tips: ["Never bounce while stretching.", "Breathe deeply.", "Stop if you feel sharp pain."], contraindications: ["Avoid stretching acutely injured areas."], startPosition: "Stand upright with feet shoulder-width apart, arms relaxed at your sides", movement: "Slowly reach overhead, then gently bend to each side. Reach for your toes. Hold each stretch for 15-30 seconds", endPosition: "Return to standing upright and shake out your arms and legs", exerciseCategory: "stretch", imageFileName: "gentle-stretching"),
            RehabExercise(id: UUID(), name: "Walking", targetArea: "General", description: "Walk at a comfortable pace. Start with 10 minutes and gradually increase duration.", sets: 1, reps: "10-20 minutes", restSeconds: 0, difficulty: .beginner, demonstrationIcon: "figure.walk", tips: ["Wear supportive shoes.", "Walk on flat surfaces.", "Maintain good posture."], contraindications: ["Avoid if weight-bearing causes significant pain."], startPosition: "Stand upright with good posture, shoulders back, wearing supportive shoes", movement: "Walk at a comfortable pace on a flat surface. Swing your arms naturally and breathe evenly", endPosition: "Gradually slow your pace and come to a gentle stop", exerciseCategory: "walking", imageFileName: "walking")
        ]
    }

    // MARK: - Missing Image Logging

    /// Logs exercises that don't have images to Firestore so we know which to generate next.
    /// Fire-and-forget — non-blocking, errors are printed to console.
    private func logMissingImages(exercises: [RehabExercise], source: String) {
        let missing = ExerciseImageService.shared.exercisesWithoutImages(in: exercises)
        guard !missing.isEmpty else { return }

        AppLogger.images.info("\(missing.count) exercise(s) missing images: \(missing.map { $0.name }.joined(separator: ", "))")

        Task {
            for exercise in missing {
                let normalizedKey = ExerciseImageService.shared.normalizeName(exercise.name)

                var data: [String: Any] = [
                    "exerciseName": exercise.name,
                    "normalizedKey": normalizedKey,
                    "exerciseCategory": exercise.exerciseCategory ?? "unknown",
                    "targetArea": exercise.targetArea,
                    "source": source,
                    "count": FieldValue.increment(Int64(1)),
                    "lastSeen": FieldValue.serverTimestamp()
                ]

                if let imageFile = exercise.imageFileName {
                    data["imageFileName"] = imageFile
                }

                do {
                    let docRef = db.collection("missingExerciseImages").document(normalizedKey)
                    // Set firstSeen only if document doesn't exist yet
                    let snapshot = try? await docRef.getDocument()
                    if snapshot?.exists != true {
                        data["firstSeen"] = FieldValue.serverTimestamp()
                    }
                    try await docRef.setData(data, merge: true)
                } catch {
                    AppLogger.images.error("Failed to log missing image for \(exercise.name): \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Firestore

    func savePlanToFirestore() {
        guard let userId = Auth.auth().currentUser?.uid else {
            saveError = "Not signed in"
            return
        }
        guard let plan = rehabPlan else {
            saveError = "No plan to save"
            return
        }

        isSaving = true
        saveError = nil

        // Build exercise dictionaries safely
        var exerciseDicts: [[String: Any]] = []
        for exercise in plan.exercises {
            var dict: [String: Any] = [
                "id": exercise.id.uuidString,
                "name": exercise.name,
                "targetArea": exercise.targetArea,
                "description": exercise.description,
                "sets": exercise.sets,
                "reps": exercise.reps,
                "restSeconds": exercise.restSeconds,
                "difficulty": exercise.difficulty.rawValue,
                "demonstrationIcon": exercise.demonstrationIcon,
                "tips": exercise.tips,
                "contraindications": exercise.contraindications
            ]
            if let start = exercise.startPosition { dict["startPosition"] = start }
            if let move = exercise.movement { dict["movement"] = move }
            if let end = exercise.endPosition { dict["endPosition"] = end }
            if let category = exercise.exerciseCategory { dict["exerciseCategory"] = category }
            if let imageFile = exercise.imageFileName { dict["imageFileName"] = imageFile }
            exerciseDicts.append(dict)
        }

        // Flatten weeklySchedule to avoid nested array issues with Firestore
        // Store as a dictionary keyed by day index
        var scheduleDicts: [String: [String]] = [:]
        for (index, dayExercises) in plan.weeklySchedule.enumerated() {
            if !dayExercises.isEmpty {
                scheduleDicts["\(index)"] = dayExercises
            }
        }

        var planData: [String: Any] = [
            "id": plan.id.uuidString,
            "planName": plan.planName,
            "conditions": plan.conditions,
            "exercises": exerciseDicts,
            "weeklySchedule": scheduleDicts,
            "totalWeeks": plan.totalWeeks,
            "createdDate": Timestamp(date: plan.createdDate)
        ]
        if let notes = plan.notes {
            planData["notes"] = notes
        }

        Task {
            do {
                try await db.collection("users").document(userId).collection("rehabPlans")
                    .document(plan.id.uuidString)
                    .setData(planData)
                self.isSaving = false
                self.showSaveSuccess = true
            } catch {
                self.isSaving = false
                self.saveError = error.localizedDescription
            }
        }
    }
}
