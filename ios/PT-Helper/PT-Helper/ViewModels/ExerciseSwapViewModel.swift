import Foundation

// MARK: - Swap Reason

/// Reason the user wants to swap an exercise.
enum SwapReason: String, CaseIterable, Identifiable {
    case tooPainful = "too_painful"
    case noEquipment = "no_equipment"
    case tooDifficult = "too_difficult"
    case other = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tooPainful: return "Too Painful"
        case .noEquipment: return "No Equipment Available"
        case .tooDifficult: return "Too Difficult"
        case .other: return "Other Reason"
        }
    }

    var icon: String {
        switch self {
        case .tooPainful: return "bolt.heart"
        case .noEquipment: return "dumbbell"
        case .tooDifficult: return "chart.bar.xaxis.ascending"
        case .other: return "ellipsis.circle"
        }
    }
}

// MARK: - AI Response Types

private struct AISubstituteResponse: Decodable {
    let substitutes: [AISubstituteExercise]
}

private struct AISubstituteExercise: Decodable {
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
    let whyItHelps: String?
}

// MARK: - ViewModel

@MainActor
class ExerciseSwapViewModel: ObservableObject {

    // MARK: - Published State

    @Published var selectedReason: SwapReason?
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var substitutes: [RehabExercise] = []
    @Published var substituteReasons: [UUID: String] = [:]  // exercise id → whyItHelps text
    @Published var verificationStatuses: [UUID: ExerciseVerificationStatus] = [:]

    // MARK: - Input

    let exercise: RehabExercise
    let plan: RehabPlan
    let apiService: ClaudeAPIServiceProtocol

    init(exercise: RehabExercise, plan: RehabPlan,
         apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) {
        self.exercise = exercise
        self.plan = plan
        self.apiService = apiService
    }

    // MARK: - Actions

    /// Fetch substitute exercises from the AI.
    func fetchSubstitutes() async {
        guard let reason = selectedReason else { return }
        isLoading = true
        error = nil

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Requested exercise swap",
                                  metadata: ["exercise": exercise.name,
                                              "reason": reason.rawValue])

        do {
            let message = buildUserMessage()
            let response = try await apiService.sendMessage(
                requestType: .exercise_substitute,
                userMessage: message
            )

            let parsed = try parseSubstitutes(from: response)
            self.substitutes = parsed
            verifySubstitutes(parsed)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false

            SessionLogger.shared.log(.errorOccurred, category: .error,
                                      message: "Exercise swap fetch failed",
                                      metadata: ["error": error.localizedDescription])
        }
    }

    /// Replace the original exercise in the plan with the selected substitute.
    func selectSubstitute(_ substitute: RehabExercise,
                          savedPlansVM: SavedPlansViewModel) -> RehabPlan {
        var updatedPlan = plan
        if let index = updatedPlan.exercises.firstIndex(where: { $0.id == exercise.id }) {
            updatedPlan.exercises[index] = substitute
        }
        updatedPlan.lastModifiedDate = Date()
        savedPlansVM.updatePlan(updatedPlan)

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Exercise swapped",
                                  metadata: [
                                      "originalExercise": exercise.name,
                                      "newExercise": substitute.name,
                                      "reason": selectedReason?.rawValue ?? "unknown",
                                      "planId": plan.id.uuidString
                                  ])

        return updatedPlan
    }

    // MARK: - Private — Message Construction

    func buildUserMessage() -> String {
        let existingNames = plan.exercises
            .filter { $0.id != exercise.id }
            .map { $0.name }
            .joined(separator: ", ")

        return """
        EXERCISE TO REPLACE:
        - Name: \(exercise.name)
        - Target Area: \(exercise.targetArea)
        - Category: \(exercise.exerciseCategory ?? "unknown")
        - Difficulty: \(exercise.difficulty.rawValue)
        - Sets: \(exercise.sets), Reps: \(exercise.reps)

        REASON FOR SWAP: \(selectedReason?.displayName ?? "Not specified")

        PLAN CONTEXT:
        - Conditions: \(plan.conditions.joined(separator: ", "))
        - Other exercises in plan: \(existingNames.isEmpty ? "None" : existingNames)
        """
    }

    // MARK: - Private — Response Parsing

    private func parseSubstitutes(from text: String) throws -> [RehabExercise] {
        guard let jsonData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(
                NSError(domain: "ExerciseSwapViewModel", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response text encoding"]))
        }

        let aiResponse: AISubstituteResponse
        do {
            aiResponse = try JSONDecoder().decode(AISubstituteResponse.self, from: jsonData)
        } catch let directError {
            // Fallback: extract JSON between first { and last }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex {
                let jsonSubstring = String(text[startIndex...endIndex])
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    aiResponse = try JSONDecoder().decode(AISubstituteResponse.self, from: fallbackData)
                } else {
                    throw ClaudeAPIError.decodingError(directError)
                }
            } else {
                throw ClaudeAPIError.decodingError(directError)
            }
        }

        return aiResponse.substitutes.map { ai in
            let difficulty: RehabExercise.Difficulty = {
                switch ai.difficulty.lowercased() {
                case "intermediate": return .intermediate
                case "advanced": return .advanced
                default: return .beginner
                }
            }()

            let exercise = RehabExercise(
                id: UUID(),
                name: ai.name,
                targetArea: ai.targetArea,
                description: ai.description,
                sets: ai.sets,
                reps: ai.reps,
                restSeconds: ai.restSeconds,
                difficulty: difficulty,
                demonstrationIcon: ai.demonstrationIcon,
                tips: ai.tips,
                contraindications: ai.contraindications,
                startPosition: ai.startPosition,
                movement: ai.movement,
                endPosition: ai.endPosition,
                exerciseCategory: ai.exerciseCategory,
                imageFileName: ai.imageFileName
            )

            // Store the whyItHelps text separately (not part of RehabExercise model)
            if let reason = ai.whyItHelps, !reason.isEmpty {
                substituteReasons[exercise.id] = reason
            }

            return exercise
        }
    }

    // MARK: - Private — Knowledge Graph Verification

    private func verifySubstitutes(_ exercises: [RehabExercise]) {
        let graph = KnowledgeGraphService.shared

        for sub in exercises {
            var worstTier: ExerciseVerificationStatus = .checking

            for condition in plan.conditions {
                let tier = graph.verify(exercise: sub.name, forCondition: condition)
                switch tier {
                case .contraindicated(let reason):
                    worstTier = .contraindicated(reason: reason)
                case .verified:
                    if case .contraindicated = worstTier { } else {
                        worstTier = .verified
                    }
                case .unverified:
                    break // keep current worstTier (.checking unless overridden)
                }
            }

            verificationStatuses[sub.id] = worstTier
        }
    }
}
