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

    // MARK: - Retry Policy (WS8-03)

    static let maxAttempts = 2                       // 1 initial + 1 retry
    static let retryDelaySeconds: TimeInterval = 2   // fixed first backoff step

    /// Idempotent-cost eligibility: exercise_substitute owns its own VM-level
    /// retry/timeout race (ExerciseSwapViewModel.swift) — a service-level sleep
    /// would starve that budget and stack retries. All other proxy request
    /// types are pure generate-and-return with no user-data writes.
    static func isServiceRetryEligible(_ requestType: AIRequestType) -> Bool {
        requestType != .exercise_substitute
    }

    static func isRetryableStatus(_ statusCode: Int) -> Bool {
        (500...599).contains(statusCode)
    }

    /// Waits the fixed retry backoff. Returns false if the task was cancelled
    /// during the wait — callers must not retry in that case.
    private func waitBeforeRetry() async -> Bool {
        try? await Task.sleep(for: .seconds(Self.retryDelaySeconds))
        return !Task.isCancelled
    }

    // MARK: - Shared Proxy Call

    /// Per-endpoint configuration for `performProxyRequest`. Values mirror what
    /// each of the 3 protocol methods used to hardcode inline.
    private struct ProxyCall {
        let urlString: String
        let endpointName: String        // SessionLogger endpoint
        let telemetryRequestType: String
        let timeout: TimeInterval
        let bgTaskName: String
        let retryEligible: Bool
    }

    /// Single choke point for all Claude/agent HTTP traffic: auth, request build,
    /// telemetry, retry, status mapping, decode, and text extraction. Each public
    /// method below is a thin wrapper supplying its own URL/timeout/telemetry identity.
    private func performProxyRequest(_ call: ProxyCall, body: Data) async throws -> String {
        let bgTaskID = await beginBackgroundTask(named: call.bgTaskName)
        defer { endBackgroundTask(bgTaskID) }

        guard let url = URL(string: call.urlString) else {
            throw ClaudeAPIError.invalidURL
        }

        guard let currentUser = Auth.auth().currentUser else {
            throw ClaudeAPIError.authenticationRequired
        }

        let idToken: String
        do {
            idToken = try await currentUser.getIDToken()
        } catch {
            throw ClaudeAPIError.authenticationRequired
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = call.timeout
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let requestBytes = body.count
        let started = Date()
        func elapsedMsInt() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

        await MainActor.run {
            let interfaceType = NetworkMonitor.shared.connectionType.description
            SessionLogger.shared.logAPI(.apiCallStarted, endpoint: call.endpointName,
                metadata: Self.makeTelemetryMetadata(
                    requestType: call.telemetryRequestType,
                    interfaceType: interfaceType,
                    requestBytes: requestBytes))
        }

        var data = Data()
        var statusCode = 0
        var succeededAttempt = 1

        for attempt in 1...Self.maxAttempts {
            succeededAttempt = attempt
            let transportResult: Result<(Data, URLResponse), Error>
            do {
                transportResult = .success(try await URLSession.shared.data(for: request))
            } catch {
                transportResult = .failure(error)
            }

            switch transportResult {
            case .failure(let error):
                let elapsed = elapsedMsInt()
                let retrying = call.retryEligible && attempt < Self.maxAttempts
                await MainActor.run {
                    let interfaceType = NetworkMonitor.shared.connectionType.description
                    var extras = ["error": error.localizedDescription]
                    if retrying { extras["attempt"] = "\(attempt)" }
                    SessionLogger.shared.logAPI(.apiCallFailed, endpoint: call.endpointName,
                        metadata: Self.makeTelemetryMetadata(
                            requestType: call.telemetryRequestType,
                            interfaceType: interfaceType,
                            requestBytes: requestBytes,
                            elapsedMs: elapsed,
                            extras: extras))
                }
                guard retrying, await waitBeforeRetry() else { throw ClaudeAPIError.networkError(error) }
                continue

            case .success(let pair):
                guard let httpResponse = pair.1 as? HTTPURLResponse else {
                    throw ClaudeAPIError.invalidResponse(0, "Invalid HTTP response")
                }
                data = pair.0
                statusCode = httpResponse.statusCode
            }

            if statusCode == 200 {
                break
            }

            switch statusCode {
            case 401:
                let elapsed = elapsedMsInt()
                let responseBytes = data.count
                await MainActor.run {
                    let interfaceType = NetworkMonitor.shared.connectionType.description
                    SessionLogger.shared.logAPI(.apiCallFailed, endpoint: call.endpointName,
                        metadata: Self.makeTelemetryMetadata(
                            requestType: call.telemetryRequestType,
                            interfaceType: interfaceType,
                            requestBytes: requestBytes,
                            responseBytes: responseBytes,
                            elapsedMs: elapsed,
                            extras: ["statusCode": "401", "error": "authRequired"]))
                }
                throw ClaudeAPIError.authenticationRequired
            case 429:
                let elapsed = elapsedMsInt()
                let responseBytes = data.count
                await MainActor.run {
                    let interfaceType = NetworkMonitor.shared.connectionType.description
                    SessionLogger.shared.logAPI(.apiCallFailed, endpoint: call.endpointName,
                        metadata: Self.makeTelemetryMetadata(
                            requestType: call.telemetryRequestType,
                            interfaceType: interfaceType,
                            requestBytes: requestBytes,
                            responseBytes: responseBytes,
                            elapsedMs: elapsed,
                            extras: ["statusCode": "429", "error": "rateLimited"]))
                }
                throw ClaudeAPIError.rateLimited
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
                let retrying = call.retryEligible && Self.isRetryableStatus(statusCode) && attempt < Self.maxAttempts
                if !retrying {
                    AppLogger.api.error("\(call.endpointName) error (\(statusCode)): \(errorBody)")
                }
                let elapsed = elapsedMsInt()
                let responseBytes = data.count
                await MainActor.run {
                    let interfaceType = NetworkMonitor.shared.connectionType.description
                    var extras = ["statusCode": "\(statusCode)"]
                    if retrying { extras["attempt"] = "\(attempt)" }
                    SessionLogger.shared.logAPI(.apiCallFailed, endpoint: call.endpointName,
                        metadata: Self.makeTelemetryMetadata(
                            requestType: call.telemetryRequestType,
                            interfaceType: interfaceType,
                            requestBytes: requestBytes,
                            responseBytes: responseBytes,
                            elapsedMs: elapsed,
                            extras: extras))
                }
                guard retrying, await waitBeforeRetry() else { throw ClaudeAPIError.invalidResponse(statusCode, errorBody) }
                continue
            }
        }

        // Decode the response (proxy/agent endpoints pass through Anthropic's response format)
        let claudeResponse: ClaudeResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            AppLogger.api.error("\(call.endpointName) decode failed. Raw body (\(data.count) bytes): \(rawBody.prefix(500))")
            throw ClaudeAPIError.decodingError(error)
        }

        // Extract text from the first content block
        guard let textBlock = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textBlock.text, !text.isEmpty else {
            throw ClaudeAPIError.noContent
        }

        let elapsed = elapsedMsInt()
        let responseBytes = data.count
        let textCount = text.count
        await MainActor.run {
            let interfaceType = NetworkMonitor.shared.connectionType.description
            SessionLogger.shared.logAPI(.apiCallSucceeded, endpoint: call.endpointName,
                metadata: Self.makeTelemetryMetadata(
                    requestType: call.telemetryRequestType,
                    interfaceType: interfaceType,
                    requestBytes: requestBytes,
                    responseBytes: responseBytes,
                    elapsedMs: elapsed,
                    extras: ["statusCode": "200", "responseLength": "\(textCount)", "attempt": "\(succeededAttempt)"]))
        }

        // Clean up the response — strip markdown code fences if present
        return ClaudeAPIService.cleanJSONResponse(text)
    }

    /// Send a message to the Claude API via the Firebase proxy and return the text response.
    /// The system prompt, model, and max_tokens are controlled server-side for security.
    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String {
        let requestBody = ClaudeProxyRequest(
            requestType: requestType,
            messages: [
                ClaudeMessage(role: "user", content: userMessage)
            ]
        )
        let bodyData = try JSONEncoder().encode(requestBody)
        return try await performProxyRequest(
            ProxyCall(
                urlString: APIConfig.claudeProxyURL,
                endpointName: "claudeProxy",
                telemetryRequestType: requestType.rawValue,
                timeout: 90,
                bgTaskName: "claudeProxy-\(requestType.rawValue)",
                retryEligible: Self.isServiceRetryEligible(requestType)),
            body: bodyData)
    }

    /// Request recovery insights from the managed agent endpoint.
    /// The server fetches user data from Firestore and runs a multi-step agent analysis.
    /// No request body needed — the server identifies the user via the auth token.
    func requestAgentInsights() async throws -> String {
        try await performProxyRequest(
            ProxyCall(
                urlString: APIConfig.agentInsightsURL,
                endpointName: "agentInsights",
                telemetryRequestType: "recovery_insights_agent",
                timeout: 180,
                bgTaskName: "agentInsights",
                retryEligible: false),
            body: "{}".data(using: .utf8)!)
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
        let bodyData = try JSONEncoder().encode(
            AgentFormAnalysisRequest(exerciseName: exerciseName, userMessage: userMessage)
        )
        return try await performProxyRequest(
            ProxyCall(
                urlString: APIConfig.agentFormAnalysisURL,
                endpointName: "agentFormAnalysis",
                telemetryRequestType: "form_analysis_agent",
                timeout: 180,
                bgTaskName: "agentFormAnalysis",
                retryEligible: false),
            body: bodyData)
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
