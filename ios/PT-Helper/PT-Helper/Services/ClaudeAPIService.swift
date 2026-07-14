import Foundation
import FirebaseAuth
import UIKit

// MARK: - Error Types

enum ClaudeAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(Int, String)
    case decodingError(Error)
    case noContent
    case rateLimited
    case authenticationRequired

    /// Tier 1: true when the server rejected Claude's output via Zod response-schema
    /// validation (see functions/src/response-schemas.ts). ViewModels should render a
    /// specific "response was malformed — try again" state rather than the default
    /// cryptic error string.
    var isResponseInvalid: Bool {
        if case let .invalidResponse(statusCode, details) = self {
            return statusCode == 502 && details.contains("ai_response_invalid")
        }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL configuration."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription). Please check your internet connection."
        case .invalidResponse(let statusCode, let details):
            // Tier 1: ai_response_invalid gets a user-friendly message first.
            if statusCode == 502 && details.contains("ai_response_invalid") {
                return "The AI response was malformed. Please try again."
            }
            // Parse Anthropic-style error: { "error": { "message": "..." } }
            if let data = details.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorInfo = json["error"] as? [String: Any],
               let message = errorInfo["message"] as? String {
                return "API error (\(statusCode)): \(message)"
            }
            // Parse proxy-style error: { "error": "..." }
            if let data = details.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["error"] as? String {
                return "API error (\(statusCode)): \(message)"
            }
            return "Server returned an error (status \(statusCode)). Please try again."
        case .decodingError:
            return "Failed to process the AI response. Please try again."
        case .noContent:
            return "The AI returned an empty response. Please try again."
        case .rateLimited:
            return "The service is busy. Please wait a moment and try again."
        case .authenticationRequired:
            return "Please sign in to use this feature."
        }
    }
}

// MARK: - API Request/Response Models

/// Request type determines which server-side system prompt and model config to use
enum AIRequestType: String, Encodable {
    case analysis
    case analysis_verify
    case rehab_plan
    case exercise_substitute
    case recovery_insights
    case form_analysis
    case wellness_analysis
    case wellness_verify
    case wellness_plan
}

struct ClaudeProxyRequest: Encodable {
    let requestType: AIRequestType
    let messages: [ClaudeMessage]
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]
    let stop_reason: String?

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

// MARK: - Protocol for Dependency Injection

protocol ClaudeAPIServiceProtocol {
    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String
    func requestAgentInsights() async throws -> String
    func requestAgentFormAnalysis(exerciseName: String, userMessage: String) async throws -> String
}

// MARK: - Claude API Service

class ClaudeAPIService: ClaudeAPIServiceProtocol {
    static let shared = ClaudeAPIService()

    /// Build the telemetry metadata dict logged with each API call event so we can
    /// diagnose cellular vs. wifi latency. Pure for testability — caller passes
    /// in the interface type rather than reading NetworkMonitor here.
    static func makeTelemetryMetadata(
        requestType: String,
        interfaceType: String,
        requestBytes: Int,
        responseBytes: Int? = nil,
        elapsedMs: Int? = nil,
        extras: [String: String] = [:]
    ) -> [String: String] {
        var dict: [String: String] = [
            "requestType": requestType,
            "interfaceType": interfaceType,
            "requestBytes": "\(requestBytes)",
        ]
        if let responseBytes { dict["responseBytes"] = "\(responseBytes)" }
        if let elapsedMs { dict["elapsedMs"] = "\(elapsedMs)" }
        for (k, v) in extras { dict[k] = v }
        return dict
    }

    private init() {}

    // MARK: - Background Task Support

    /// Request background execution time so API calls survive app backgrounding.
    /// Returns the task ID to end when the call completes.
    private func beginBackgroundTask(named name: String) async -> UIBackgroundTaskIdentifier {
        await MainActor.run {
            var taskID: UIBackgroundTaskIdentifier = .invalid
            taskID = UIApplication.shared.beginBackgroundTask(withName: name) {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
            return taskID
        }
    }

    private func endBackgroundTask(_ taskID: UIBackgroundTaskIdentifier) {
        guard taskID != .invalid else { return }
        Task { @MainActor in
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    // MARK: - Public API

    /// Send a message to the Claude API via the Firebase proxy and return the text response.
    /// The system prompt, model, and max_tokens are controlled server-side for security.
    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String {
        // Body carries only requestType + user message (prompt is server-side).
        let body = try JSONEncoder().encode(ClaudeProxyRequest(
            requestType: requestType,
            messages: [ClaudeMessage(role: "user", content: userMessage)]
        ))
        return try await performProxyRequest(
            endpoint: ProxyEndpoint(
                urlString: APIConfig.claudeProxyURL,
                logName: "claudeProxy",
                requestTypeLabel: requestType.rawValue,
                backgroundTaskName: "claudeProxy-\(requestType.rawValue)",
                timeout: 90
            ),
            body: body
        )
    }

    /// Request recovery insights from the managed agent endpoint.
    /// The server fetches user data from Firestore and runs a multi-step agent analysis.
    /// No request body needed — the server identifies the user via the auth token.
    func requestAgentInsights() async throws -> String {
        try await performProxyRequest(
            endpoint: ProxyEndpoint(
                urlString: APIConfig.agentInsightsURL,
                logName: "agentInsights",
                requestTypeLabel: "recovery_insights_agent",
                backgroundTaskName: "agentInsights",
                timeout: 180 // Agent may take longer than regular calls
            ),
            body: Data("{}".utf8)
        )
    }

    /// Request cross-session form analysis from the managed agent endpoint.
    /// Unlike `requestAgentInsights()`, the request body carries the CURRENT session's
    /// metrics message — the just-recorded session is not in Firestore yet (iOS persists
    /// after feedback). The server fetches prior sessions of the same exercise.
    func requestAgentFormAnalysis(exerciseName: String, userMessage: String) async throws -> String {
        struct AgentFormAnalysisRequest: Encodable {
            let exerciseName: String
            let userMessage: String
        }
        let body = try JSONEncoder().encode(
            AgentFormAnalysisRequest(exerciseName: exerciseName, userMessage: userMessage)
        )
        return try await performProxyRequest(
            endpoint: ProxyEndpoint(
                urlString: APIConfig.agentFormAnalysisURL,
                logName: "agentFormAnalysis",
                requestTypeLabel: "form_analysis_agent",
                backgroundTaskName: "agentFormAnalysis",
                timeout: 180 // Agent may take longer than regular calls
            ),
            body: body
        )
    }

    // MARK: - Shared Request Pipeline

    /// Describes one Cloud Function endpoint for the shared request pipeline.
    private struct ProxyEndpoint {
        let urlString: String
        /// Endpoint label for SessionLogger events and error logs.
        let logName: String
        /// Value of the "requestType" key in telemetry metadata.
        let requestTypeLabel: String
        let backgroundTaskName: String
        let timeout: TimeInterval
    }

    /// The full request lifecycle shared by every Cloud Function call:
    /// auth token → POST → telemetry → HTTP status handling → decode →
    /// text extraction → code-fence cleanup.
    private func performProxyRequest(endpoint: ProxyEndpoint, body: Data) async throws -> String {
        let bgTaskID = await beginBackgroundTask(named: endpoint.backgroundTaskName)
        defer { endBackgroundTask(bgTaskID) }

        guard let url = URL(string: endpoint.urlString) else {
            throw ClaudeAPIError.invalidURL
        }

        let idToken = try await firebaseIDToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = endpoint.timeout
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let telemetry = APICallTelemetry(endpoint: endpoint, requestBytes: body.count)
        await telemetry.log(.apiCallStarted)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            await telemetry.log(.apiCallFailed, extras: ["error": error.localizedDescription])
            throw ClaudeAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse(0, "Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            break // Success
        case 401:
            await telemetry.log(.apiCallFailed, responseBytes: data.count,
                                extras: ["statusCode": "401", "error": "authRequired"])
            throw ClaudeAPIError.authenticationRequired
        case 429:
            await telemetry.log(.apiCallFailed, responseBytes: data.count,
                                extras: ["statusCode": "429", "error": "rateLimited"])
            throw ClaudeAPIError.rateLimited
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
            AppLogger.api.error("\(endpoint.logName) error (\(httpResponse.statusCode)): \(errorBody)")
            await telemetry.log(.apiCallFailed, responseBytes: data.count,
                                extras: ["statusCode": "\(httpResponse.statusCode)"])
            throw ClaudeAPIError.invalidResponse(httpResponse.statusCode, errorBody)
        }

        // Decode the response (proxy passes through Anthropic's response format)
        let claudeResponse: ClaudeResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            AppLogger.api.error("\(endpoint.logName) decode failed. Raw body (\(data.count) bytes): \(rawBody.prefix(500))")
            throw ClaudeAPIError.decodingError(error)
        }

        // Extract text from the first content block
        guard let textBlock = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textBlock.text, !text.isEmpty else {
            throw ClaudeAPIError.noContent
        }

        await telemetry.log(.apiCallSucceeded, responseBytes: data.count,
                            extras: ["statusCode": "200", "responseLength": "\(text.count)"])

        // Clean up the response — strip markdown code fences if present
        return ClaudeAPIService.cleanJSONResponse(text)
    }

    /// Fetch the Firebase Auth ID token, mapping every failure to `.authenticationRequired`.
    private func firebaseIDToken() async throws -> String {
        guard let currentUser = Auth.auth().currentUser else {
            throw ClaudeAPIError.authenticationRequired
        }
        do {
            return try await currentUser.getIDToken()
        } catch {
            throw ClaudeAPIError.authenticationRequired
        }
    }

    /// Captures the request start time and emits SessionLogger API events with
    /// consistent telemetry metadata. Reads NetworkMonitor on the main actor.
    private struct APICallTelemetry {
        let endpoint: ProxyEndpoint
        let requestBytes: Int
        private let started = Date()

        /// Log one API lifecycle event. Elapsed time is attached to every event
        /// after `.apiCallStarted`; response size only when a response arrived.
        func log(_ event: SessionEvent.EventType,
                 responseBytes: Int? = nil,
                 extras: [String: String] = [:]) async {
            let elapsedMs = event == .apiCallStarted
                ? nil
                : Int(Date().timeIntervalSince(started) * 1000)
            await MainActor.run {
                let interfaceType = NetworkMonitor.shared.connectionType.description
                SessionLogger.shared.logAPI(event, endpoint: endpoint.logName,
                    metadata: ClaudeAPIService.makeTelemetryMetadata(
                        requestType: endpoint.requestTypeLabel,
                        interfaceType: interfaceType,
                        requestBytes: requestBytes,
                        responseBytes: responseBytes,
                        elapsedMs: elapsedMs,
                        extras: extras))
            }
        }
    }

    /// Strip markdown code fences from the response
    static func cleanJSONResponse(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` wrapping
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }

        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
