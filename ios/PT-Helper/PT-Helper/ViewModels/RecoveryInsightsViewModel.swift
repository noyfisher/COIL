import Foundation

// MARK: - Private AI Response Types

/// Matches the JSON structure returned by the `recovery_insights` system prompt.
/// `id` and `generatedDate` are set client-side after parsing.
private struct AIRecoveryInsightResponse: Decodable {
    let headline: String
    let summary: String
    let painAnalysis: RecoveryInsight.PainAnalysis
    let adherenceAnalysis: RecoveryInsight.AdherenceAnalysis
    let keyWins: [String]
    let focusAreas: [String]
    let recommendations: [AIRecommendation]
}

private struct AIRecommendation: Decodable {
    let icon: String
    let title: String
    let description: String
}

// MARK: - ViewModel

@MainActor
class RecoveryInsightsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var insight: RecoveryInsight?
    @Published var isLoading: Bool = false
    @Published var error: String?
    /// In-memory only — resets on app restart. Prevents repeated API calls within a session.
    @Published var lastGeneratedDate: Date?

    // MARK: - Configuration

    /// Minimum sessions needed in the lookback window to generate insights.
    static let minimumSessionCount = 3
    /// How far back to look for sessions (in days).
    static let lookbackDays = 14
    /// Minimum time between regenerations (in seconds) — 1 hour.
    static let cacheValidityInterval: TimeInterval = 3600

    // MARK: - Dependencies

    let apiService: ClaudeAPIServiceProtocol

    init(apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) {
        self.apiService = apiService
    }

    // MARK: - Computed Properties

    /// Whether the cached insight is still valid (less than 1 hour old).
    var isCacheValid: Bool {
        guard let lastGenerated = lastGeneratedDate else { return false }
        return Date().timeIntervalSince(lastGenerated) < Self.cacheValidityInterval
    }

    // MARK: - Data Eligibility

    /// Check if there are enough sessions in the lookback window.
    func hasEnoughData(sessions: [WorkoutSession]) -> Bool {
        return recentSessions(from: sessions).count >= Self.minimumSessionCount
    }

    /// Filter sessions to the lookback window and sort chronologically.
    func recentSessions(from sessions: [WorkoutSession]) -> [WorkoutSession] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.lookbackDays, to: Date()) ?? Date()
        return sessions.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    // MARK: - Generate Insights

    /// Generate AI recovery insights from recent session data.
    /// Skips the API call if a cached result is still valid.
    /// Pass `forceRegenerate: true` to bypass the cache.
    func generateInsights(
        sessions: [WorkoutSession],
        plans: [RehabPlan],
        profile: UserProfile?,
        forceRegenerate: Bool = false
    ) async {
        // Return cached result if still valid
        guard forceRegenerate || !isCacheValid else { return }

        let recent = recentSessions(from: sessions)
        guard recent.count >= Self.minimumSessionCount else {
            self.error = "Complete at least \(Self.minimumSessionCount) workouts in the past 2 weeks to generate insights."
            return
        }

        isLoading = true
        error = nil

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Requested recovery insights",
                                  metadata: ["sessionCount": "\(recent.count)"])

        do {
            let message = buildUserMessage(sessions: recent, plans: plans, profile: profile)
            let response = try await apiService.sendMessage(
                requestType: .recovery_insights,
                userMessage: message
            )
            let parsed = try parseInsight(from: response)
            self.insight = parsed
            self.lastGeneratedDate = Date()
            self.isLoading = false

            SessionLogger.shared.log(.loadingFinished, category: .stateChange,
                                      message: "Recovery insights generated",
                                      metadata: [
                                          "headline": parsed.headline,
                                          "painTrend": parsed.painAnalysis.trendDirection,
                                          "adherenceScore": "\(parsed.adherenceAnalysis.score)"
                                      ])
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false

            SessionLogger.shared.log(.errorOccurred, category: .error,
                                      message: "Recovery insights generation failed",
                                      metadata: ["error": error.localizedDescription])
        }
    }

    // MARK: - Message Construction (internal for testing)

    func buildUserMessage(
        sessions: [WorkoutSession],
        plans: [RehabPlan],
        profile: UserProfile?
    ) -> String {
        // Session summaries
        let sessionLines = sessions.map { session -> String in
            let dateStr = Self.dateFormatter.string(from: session.date)
            let exerciseCount = session.exercisesPerformed.count
            let duration = Int(session.duration / 60)
            var line = "- \(dateStr): pain \(String(format: "%.1f", session.painLevel))/10, \(exerciseCount) exercises, \(duration) min"
            if let regionPain = session.regionPainLevels, !regionPain.isEmpty {
                let regionStr = regionPain.map { "\($0.key): \(String(format: "%.1f", $0.value))" }.joined(separator: ", ")
                line += " [regions: \(regionStr)]"
            }
            if let planId = session.planId,
               let plan = plans.first(where: { $0.id == planId }) {
                line += " (plan: \(plan.planName))"
            }
            return line
        }.joined(separator: "\n")

        // Plan context
        let planContext = plans.map { plan -> String in
            let exerciseNames = plan.exercises.map(\.name).joined(separator: ", ")
            let scheduled = plan.weeklySchedule.filter { !$0.isEmpty }.count
            return "- \(plan.planName): \(plan.exercises.count) exercises (\(exerciseNames)), \(scheduled) days/week scheduled, conditions: \(plan.conditions.joined(separator: ", "))"
        }.joined(separator: "\n")

        // Expected sessions per week (from weekly schedules)
        let expectedPerWeek = plans.reduce(0) { sum, plan in
            sum + plan.weeklySchedule.filter { !$0.isEmpty }.count
        }

        // Profile context
        var profileContext = "Not available"
        if let p = profile {
            var parts = ["\(p.age) year old \(p.sex)", "activity level: \(p.activityLevel)"]
            if !p.medicalConditions.isEmpty {
                parts.append("conditions: \(p.medicalConditions.joined(separator: ", "))")
            }
            if let meds = p.medications, !meds.isEmpty {
                parts.append("medications: \(meds.joined(separator: ", "))")
            }
            profileContext = parts.joined(separator: ", ")
        }

        return """
        RECOVERY DATA (past \(Self.lookbackDays) days):

        WORKOUT SESSIONS (\(sessions.count) total):
        \(sessionLines)

        ACTIVE REHAB PLANS:
        \(planContext.isEmpty ? "None" : planContext)

        EXPECTED SESSIONS PER WEEK: \(expectedPerWeek > 0 ? "\(expectedPerWeek)" : "Not scheduled")

        USER PROFILE: \(profileContext)

        Please analyze this data and provide a weekly recovery digest.
        """
    }

    // MARK: - Response Parsing

    func parseInsight(from text: String) throws -> RecoveryInsight {
        guard let jsonData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(
                NSError(domain: "RecoveryInsightsViewModel", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response text encoding"]))
        }

        let aiResponse: AIRecoveryInsightResponse
        do {
            aiResponse = try JSONDecoder().decode(AIRecoveryInsightResponse.self, from: jsonData)
        } catch let directError {
            // Fallback: extract JSON between first { and last }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex {
                let jsonSubstring = String(text[startIndex...endIndex])
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    aiResponse = try JSONDecoder().decode(AIRecoveryInsightResponse.self, from: fallbackData)
                } else {
                    throw ClaudeAPIError.decodingError(directError)
                }
            } else {
                throw ClaudeAPIError.decodingError(directError)
            }
        }

        return RecoveryInsight(
            id: UUID(),
            headline: aiResponse.headline,
            summary: aiResponse.summary,
            painAnalysis: aiResponse.painAnalysis,
            adherenceAnalysis: aiResponse.adherenceAnalysis,
            keyWins: aiResponse.keyWins,
            focusAreas: aiResponse.focusAreas,
            recommendations: aiResponse.recommendations.map {
                RecoveryInsight.Recommendation(icon: $0.icon, title: $0.title, description: $0.description)
            },
            generatedDate: Date()
        )
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
