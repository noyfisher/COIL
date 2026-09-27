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
    @Published var loadingMessage: String = "Analyzing your recovery data…"
    @Published var error: String?
    /// In-memory only — resets on app restart. Prevents repeated API calls within a session.
    @Published var lastGeneratedDate: Date?

    /// Rotating loading messages for the agent's multi-step analysis.
    private static let loadingMessages = [
        "Analyzing your recovery data…",
        "Detecting pain trends across sessions…",
        "Evaluating your adherence patterns…",
        "Cross-referencing with your rehab plan…",
        "Personalizing recommendations…",
        "Preparing your recovery digest…",
    ]
    private var loadingMessageTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Minimum sessions needed in the lookback window to generate insights.
    static let minimumSessionCount = 3
    /// How far back to look for sessions (in days).
    static let lookbackDays = 14
    /// Minimum time between regenerations (in seconds) — 1 hour.
    static let cacheValidityInterval: TimeInterval = 3600

    // MARK: - Dependencies

    let apiService: ClaudeAPIServiceProtocol

    init(apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.resolved) {
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

        // Fail fast when offline instead of making the user watch a doomed
        // spinner before a generic network error (WS8-01, extends audit #58).
        guard NetworkMonitor.shared.isConnected else {
            error = "You're offline. Connect to the internet to load your recovery insights, then try again."
            isLoading = false
            return
        }

        isLoading = true
        loadingMessage = Self.loadingMessages[0]
        error = nil
        startLoadingMessages()

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Requested recovery insights",
                                  metadata: ["sessionCount": "\(recent.count)"])

        // Try agent-powered insights first (server fetches data, multi-step analysis)
        // Fall back to single-call path on any error
        do {
            let response = try await apiService.requestAgentInsights()
            let parsed = try parseInsight(from: response)
            // Tier 1: client-side schema sanity check even though the server schema-validates.
            // If the payload is malformed (unknown enum, out-of-range scores, empty arrays),
            // fall through to the single-call fallback path rather than rendering a broken card.
            if let reason = Self.validationError(for: parsed) {
                SessionLogger.shared.log(.errorOccurred, category: .error,
                                          message: "Agent insights rejected by client validator",
                                          metadata: ["reason": reason, "source": "agent"])
                throw ClaudeAPIError.decodingError(
                    NSError(domain: "RecoveryInsightsViewModel", code: -10,
                            userInfo: [NSLocalizedDescriptionKey: reason]))
            }
            self.insight = parsed
            self.lastGeneratedDate = Date()
            self.isLoading = false
            self.stopLoadingMessages()

            AnalyticsService.shared.log(.recoveryInsightsViewed)
            SessionLogger.shared.log(.loadingFinished, category: .stateChange,
                                      message: "Recovery insights generated (agent)",
                                      metadata: [
                                          "headline": parsed.headline,
                                          "painTrend": parsed.painAnalysis.trendDirection,
                                          "adherenceScore": "\(parsed.adherenceAnalysis.score)",
                                          "source": "agent"
                                      ])
            return
        } catch {
            SessionLogger.shared.log(.errorOccurred, category: .error,
                                      message: "Agent insights failed, falling back",
                                      metadata: ["error": error.localizedDescription])
        }

        // Fallback: single-call recovery insights via claudeProxy
        do {
            let message = buildUserMessage(sessions: recent, plans: plans, profile: profile)
            let response = try await apiService.sendMessage(
                requestType: .recovery_insights,
                userMessage: message
            )
            let parsed = try parseInsight(from: response)
            // Tier 1: same client-side validator as the agent path. A malformed fallback
            // surfaces a user-friendly error state instead of a broken card.
            if let reason = Self.validationError(for: parsed) {
                SessionLogger.shared.log(.errorOccurred, category: .error,
                                          message: "Recovery insights rejected by client validator",
                                          metadata: ["reason": reason, "source": "fallback"])
                self.error = "Recovery insights unavailable. Please try again later."
                self.isLoading = false
                self.stopLoadingMessages()
                return
            }
            self.insight = parsed
            self.lastGeneratedDate = Date()
            self.isLoading = false
            self.stopLoadingMessages()

            AnalyticsService.shared.log(.recoveryInsightsViewed)
            SessionLogger.shared.log(.loadingFinished, category: .stateChange,
                                      message: "Recovery insights generated (fallback)",
                                      metadata: [
                                          "headline": parsed.headline,
                                          "painTrend": parsed.painAnalysis.trendDirection,
                                          "adherenceScore": "\(parsed.adherenceAnalysis.score)",
                                          "source": "fallback"
                                      ])
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
            self.stopLoadingMessages()

            // Tier 1: ai_response_invalid breadcrumb (server Zod rejection on the
            // fallback single-call path — the agent path is validated by managed-agent.ts).
            if let apiError = error as? ClaudeAPIError, apiError.isResponseInvalid {
                SessionLogger.shared.log(.errorOccurred, category: .api,
                    message: "Recovery insights rejected by server schema (ai_response_invalid)",
                    metadata: ["error_kind": "ai_response_invalid"])
            }
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

    // MARK: - Tier 1 client-side validation

    /// Swift mirror of `functions/src/managed-agent.ts:validateInsightResult`. Defends
    /// against a buggy / modified server that returns a payload matching our Codable
    /// shape but with out-of-range numbers, unknown enum values, or empty arrays.
    ///
    /// Returns nil on success; on failure returns a short reason string suitable for
    /// logging (not user-facing).
    static func validationError(for insight: RecoveryInsight) -> String? {
        let validTrends: Set<String> = ["improving", "stable", "worsening"]
        if insight.headline.isEmpty { return "empty headline" }
        if insight.summary.isEmpty { return "empty summary" }
        if !validTrends.contains(insight.painAnalysis.trendDirection) {
            return "invalid trendDirection: \(insight.painAnalysis.trendDirection)"
        }
        if insight.painAnalysis.averagePain < 0 || insight.painAnalysis.averagePain > 10 {
            return "averagePain out of range: \(insight.painAnalysis.averagePain)"
        }
        if insight.adherenceAnalysis.score < 0 || insight.adherenceAnalysis.score > 100 {
            return "adherence score out of range: \(insight.adherenceAnalysis.score)"
        }
        if insight.keyWins.isEmpty { return "empty keyWins" }
        if insight.focusAreas.isEmpty { return "empty focusAreas" }
        if insight.recommendations.isEmpty { return "empty recommendations" }
        return nil
    }

    // MARK: - Response Parsing

    func parseInsight(from text: String) throws -> RecoveryInsight {
        // Tier 3 PR C: shadow-mode strict parsing (see ShadowModeJSONParser).
        let aiResponse = try ShadowModeJSONParser.parse(
            text,
            as: AIRecoveryInsightResponse.self,
            requestType: "recovery_insights"
        )

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

    // MARK: - Loading Messages

    private func startLoadingMessages() {
        loadingMessageTask?.cancel()
        loadingMessageTask = Task {
            for index in 1..<Self.loadingMessages.count {
                try? await Task.sleep(nanoseconds: 8_000_000_000) // 8 seconds per message
                guard !Task.isCancelled else { return }
                self.loadingMessage = Self.loadingMessages[index]
            }
        }
    }

    private func stopLoadingMessages() {
        loadingMessageTask?.cancel()
        loadingMessageTask = nil
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
}
