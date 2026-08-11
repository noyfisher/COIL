#if DEBUG
import Foundation

// MARK: - Why this exists
//
// UI tests run the app as a separate process, so the `MockClaudeAPIService` that unit
// tests inject is unreachable from XCUITest. `ClaudeAPIService` and
// `CrossModelVerificationService` had no `--uitesting` branch, which meant any UI test
// walking into an assessment, a plan generation, or a wellness flow would hit the real
// Cloud Function and the real Claude API over the network. The E2E suite avoided those
// journeys entirely rather than test them flakily — leaving the app's primary value
// path at 0% end-to-end coverage.
//
// This file is the in-process fake that closes that gap. It is wrapped in `#if DEBUG`
// in its entirety, so none of it — not the type, not the canned JSON — exists in a
// release binary. Activation additionally requires `--uitesting --stub-ai`, matching the
// gating `TestDataSeeder` already applies to every other test affordance.

// MARK: - Scenario steps

/// One queued outcome for a single AI call: either a response body or a thrown error.
enum ScenarioStep {
    case json(String)
    case error(Error)
}

// MARK: - Canned response bodies

/// JSON bodies shaped like real Claude responses, matching the Zod schemas in
/// `functions/src/response-schemas.ts`. Deliberately hand-written rather than generated,
/// so a server-side schema change shows up as a test failure instead of being silently
/// mirrored.
enum AIScenarioFixtures {

    static func analysis(
        conditionName: String = "Patellofemoral Pain Syndrome",
        commonName: String = "Runner's Knee",
        confidence: Double = 75,
        isRedFlag: Bool = false,
        redFlagMessage: String? = nil
    ) -> String {
        let redFlagValue = redFlagMessage.map { "\"\($0)\"" } ?? "null"
        return """
        {
            "conditions": [{
                "conditionName": "\(conditionName)",
                "commonName": "\(commonName)",
                "confidence": \(confidence),
                "explanation": "Pain pattern consistent with \(commonName).",
                "whatItMeans": "The kneecap is not tracking cleanly through its groove.",
                "howToManage": "Strengthen the quadriceps and glutes; avoid deep flexion under load.",
                "isRedFlag": \(isRedFlag),
                "redFlagMessage": \(redFlagValue),
                "nextSteps": ["See a physical therapist if symptoms persist beyond two weeks"]
            }],
            "overallSummary": "Findings are consistent with \(commonName).",
            "disclaimerText": "This is educational information, not medical advice."
        }
        """
    }

    static func rehabPlan(planName: String = "Knee Rehab Plan", exerciseCount: Int = 2) -> String {
        let exercises = (0..<exerciseCount).map { index in
            """
            {
                "name": "\(index == 0 ? "Quad Sets" : "Wall Sits")",
                "targetArea": "Knee",
                "description": "Controlled knee-strengthening movement.",
                "sets": 3,
                "reps": "10-12",
                "restSeconds": 30,
                "difficulty": "beginner",
                "demonstrationIcon": "figure.cooldown",
                "tips": ["Move slowly"],
                "contraindications": ["Stop if sharp pain"],
                "startPosition": "Seated with the leg extended",
                "movement": "Tighten the thigh and hold",
                "endPosition": "Relax back to the start",
                "exerciseCategory": "strength",
                "imageFileName": "\(index == 0 ? "quad-sets" : "wall-sits")"
            }
            """
        }.joined(separator: ",\n")

        return """
        {
            "planName": "\(planName)",
            "exercises": [\(exercises)],
            "totalWeeks": 4,
            "notes": "Progress gradually."
        }
        """
    }

    static func wellnessAnalysis(title: String = "Posture Improvement Plan") -> String {
        """
        {
            "recommendations": [{
                "goalCategory": "improve_posture",
                "title": "\(title)",
                "currentStateAssessment": "Mild postural fatigue from prolonged desk work.",
                "rootCauses": ["Prolonged sitting", "Weak deep core"],
                "expectedTimeline": "4-6 weeks",
                "keyInsight": "Frequent movement breaks help more than any single stretch.",
                "priorityLevel": "high",
                "relatedGoals": []
            }],
            "overallSummary": "Small daily habits will steadily improve your posture.",
            "disclaimerText": "This is educational wellness guidance, not medical advice."
        }
        """
    }

    static func exerciseSubstitute(count: Int = 2) -> String {
        let subs = (0..<count).map { index in
            """
            {
                "name": "Substitute Exercise \(index + 1)",
                "targetArea": "Knee",
                "description": "Alternative knee-rehab movement \(index + 1).",
                "sets": 3,
                "reps": "10-12",
                "restSeconds": 30,
                "difficulty": "beginner",
                "demonstrationIcon": "figure.cooldown",
                "tips": ["Keep good form"],
                "contraindications": ["Stop if pain increases"]
            }
            """
        }.joined(separator: ",\n")
        return """
        { "substitutes": [\(subs)] }
        """
    }

    static func formAnalysis(overallScore: Double = 82) -> String {
        """
        {
            "overallScore": \(overallScore),
            "verdict": "good",
            "corrections": [],
            "positivePoints": ["Consistent depth"],
            "safetyNotes": []
        }
        """
    }

    static func recoveryInsights() -> String {
        """
        {
            "painTrend": "improving",
            "adherenceScore": 82,
            "keyWins": ["Completed four sessions this week"],
            "focusAreas": ["Consistency on rest days"],
            "recommendations": ["Keep sessions to 20 minutes on busy days"]
        }
        """
    }

    /// Fallback for any request type a scenario does not explicitly define, so an
    /// unrelated call never derails a test that isn't about it.
    static func generic(for requestType: AIRequestType) -> String {
        switch requestType {
        case .analysis, .analysis_verify:            return analysis()
        case .rehab_plan, .wellness_plan:            return rehabPlan()
        case .wellness_analysis, .wellness_verify:   return wellnessAnalysis()
        case .exercise_substitute:                   return exerciseSubstitute()
        case .form_analysis:                         return formAnalysis()
        case .recovery_insights:                     return recoveryInsights()
        }
    }
}

// MARK: - Scenario table

/// Maps a scenario name to a per-request-type FIFO queue.
///
/// The queue is keyed by `AIRequestType` rather than being one global list because a
/// single test can trigger `analysis` → `analysis_verify` → `rehab_plan` →
/// `exercise_substitute` in sequence, and the two-call pipelines need *different* bodies
/// for call 1 and call 2 of the same flow.
enum AIScenarioLoader {

    private static let scenarios: [String: [AIRequestType: [ScenarioStep]]] = [
        // Straight-through success: analysis, its verification, and a generated plan.
        "default": [
            .analysis: [.json(AIScenarioFixtures.analysis())],
            .analysis_verify: [.json(AIScenarioFixtures.analysis(confidence: 82))],
            .rehab_plan: [.json(AIScenarioFixtures.rehabPlan())],
        ],

        // Server-flagged emergency: the condition carries isRedFlag, which
        // ResponseValidationPipeline promotes to an .emergency warning and AnalyzingView
        // routes to EmergencyRedirectView.
        "emergency_red_flag": [
            .analysis: [.json(AIScenarioFixtures.analysis(
                conditionName: "Acute Coronary Syndrome",
                commonName: "Cardiac Event",
                confidence: 70,
                isRedFlag: true,
                redFlagMessage: "These symptoms may indicate a cardiac emergency. Call 911 immediately."
            ))],
        ],

        // Verification call fails: InjuryAnalyzer must degrade to the primary result
        // rather than surfacing an error.
        // `commonName` is what the results screen renders, so it carries the marker that
        // tells the test which of the two calls produced the displayed result.
        "verify_failure": [
            .analysis: [.json(AIScenarioFixtures.analysis(
                conditionName: "Primary Only Condition",
                commonName: "Primary Call Result"
            ))],
            .analysis_verify: [.error(ClaudeAPIError.networkError(URLError(.timedOut)))],
        ],

        // The server returns 200 with a body the client cannot decode.
        "malformed_analysis": [
            .analysis: [.json("{ this is not valid json")],
        ],

        // The primary call itself fails — there is nothing to fall back to.
        "analysis_network_error": [
            .analysis: [.error(ClaudeAPIError.networkError(URLError(.notConnectedToInternet)))],
        ],

        "wellness_happy_path": [
            .wellness_analysis: [.json(AIScenarioFixtures.wellnessAnalysis())],
            .wellness_verify: [.json(AIScenarioFixtures.wellnessAnalysis(title: "Verified Posture Plan"))],
            .wellness_plan: [.json(AIScenarioFixtures.rehabPlan(planName: "Posture Wellness Plan"))],
        ],
    ]

    /// FIFO cursor per request type. Guarded because AI calls are made from concurrent
    /// async contexts, and this is process-global mutable state.
    private static let lock = NSLock()
    private static var consumed: [AIRequestType: Int] = [:]

    static func next(for requestType: AIRequestType) throws -> String {
        let queue = scenarios[TestDataSeeder.aiScenario]?[requestType] ?? []

        lock.lock()
        let index = consumed[requestType, default: 0]
        consumed[requestType] = index + 1
        lock.unlock()

        guard !queue.isEmpty else {
            return AIScenarioFixtures.generic(for: requestType)
        }

        // Past the end of the queue, repeat the final step rather than failing — a flow
        // that retries a call shouldn't fall off a cliff.
        switch queue[min(index, queue.count - 1)] {
        case .json(let body):
            return body
        case .error(let error):
            throw error
        }
    }

    /// Resets the cursors. Exposed for completeness; each UI test launches a fresh
    /// process, so in practice state never carries between tests.
    static func reset() {
        lock.lock()
        consumed = [:]
        lock.unlock()
    }
}

// MARK: - Stub services

/// In-process stand-in for `ClaudeAPIService`, selected by `ClaudeAPIService.resolved`
/// when `--uitesting --stub-ai` is present.
final class StubClaudeAPIService: ClaudeAPIServiceProtocol {
    static let shared = StubClaudeAPIService()
    private init() {}

    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String {
        try AIScenarioLoader.next(for: requestType)
    }

    func requestAgentInsights() async throws -> String {
        try AIScenarioLoader.next(for: .recovery_insights)
    }

    func requestAgentFormAnalysis(exerciseName: String, userMessage: String) async throws -> String {
        try AIScenarioLoader.next(for: .form_analysis)
    }
}

/// In-process stand-in for `CrossModelVerificationService`. Reports everything safe by
/// default; the `crossmodel_failure` scenario makes it throw so the
/// `SeriousWarningModal` path is reachable end to end.
final class StubCrossModelVerificationService: CrossModelVerifying {
    static let shared = StubCrossModelVerificationService()
    private init() {}

    func verify(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult] {
        if TestDataSeeder.aiScenario == "crossmodel_failure" {
            throw CrossModelError.serverError(503)
        }
        return exercises.map { pair in
            CrossModelResult(
                exerciseName: pair.name,
                conditionName: pair.condition,
                isSafe: true,
                confidence: 0.9,
                reasoning: "Stubbed verification.",
                concerns: []
            )
        }
    }
}
#endif
