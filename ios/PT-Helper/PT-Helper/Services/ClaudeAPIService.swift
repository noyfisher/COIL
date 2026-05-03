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

    /// Send a message to the Claude API via the Firebase proxy and return the text response.
    /// The system prompt, model, and max_tokens are controlled server-side for security.
    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String {
        let bgTaskID = await beginBackgroundTask(named: "claudeProxy-\(requestType.rawValue)")
        defer { endBackgroundTask(bgTaskID) }

        guard let url = URL(string: APIConfig.claudeProxyURL) else {
            throw ClaudeAPIError.invalidURL
        }

        // Get Firebase Auth ID token for authentication
        guard let currentUser = Auth.auth().currentUser else {
            throw ClaudeAPIError.authenticationRequired
        }

        let idToken: String
        do {
            idToken = try await currentUser.getIDToken()
        } catch {
            throw ClaudeAPIError.authenticationRequired
        }

        // Build the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90

        // Set headers — Bearer token for auth
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the request body — only requestType + user message (prompt is server-side)
        let requestBody = ClaudeProxyRequest(
            requestType: requestType,
            messages: [
                ClaudeMessage(role: "user", content: userMessage)
            ]
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(requestBody)

        let requestBytes = request.httpBody?.count ?? 0
        let started = Date()
        func elapsedMsInt() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

        // Make the API call
        await MainActor.run {
            let interfaceType = NetworkMonitor.shared.connectionType.description
            SessionLogger.shared.logAPI(.apiCallStarted, endpoint: "claudeProxy",
                metadata: Self.makeTelemetryMetadata(
                    requestType: requestType.rawValue,
                    interfaceType: interfaceType,
                    requestBytes: requestBytes))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = elapsedMsInt()
            await MainActor.run {
                let interfaceType = NetworkMonitor.shared.connectionType.description
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                    metadata: Self.makeTelemetryMetadata(
                        requestType: requestType.rawValue,
                        interfaceType: interfaceType,
                        requestBytes: requestBytes,
                        elapsedMs: elapsed,
                        extras: ["error": error.localizedDescription]))
            }
            throw ClaudeAPIError.networkError(error)
        }

        // Check HTTP status
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse(0, "Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            break // Success
        case 401:
            let elapsed = elapsedMsInt()
            let responseBytes = data.count
            await MainActor.run {
                let interfaceType = NetworkMonitor.shared.connectionType.description
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                    metadata: Self.makeTelemetryMetadata(
                        requestType: requestType.rawValue,
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
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                    metadata: Self.makeTelemetryMetadata(
                        requestType: requestType.rawValue,
                        interfaceType: interfaceType,
                        requestBytes: requestBytes,
                        responseBytes: responseBytes,
                        elapsedMs: elapsed,
                        extras: ["statusCode": "429", "error": "rateLimited"]))
            }
            throw ClaudeAPIError.rateLimited
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
            AppLogger.api.error("Claude Proxy Error (\(httpResponse.statusCode)): \(errorBody)")
            let elapsed = elapsedMsInt()
            let responseBytes = data.count
            await MainActor.run {
                let interfaceType = NetworkMonitor.shared.connectionType.description
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                    metadata: Self.makeTelemetryMetadata(
                        requestType: requestType.rawValue,
                        interfaceType: interfaceType,
                        requestBytes: requestBytes,
                        responseBytes: responseBytes,
                        elapsedMs: elapsed,
                        extras: ["statusCode": "\(httpResponse.statusCode)"]))
            }
            throw ClaudeAPIError.invalidResponse(httpResponse.statusCode, errorBody)
        }

        // Decode the response (proxy passes through Anthropic's response format)
        let claudeResponse: ClaudeResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            AppLogger.api.error("ClaudeResponse decode failed. Raw body (\(data.count) bytes): \(rawBody.prefix(500))")
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
            SessionLogger.shared.logAPI(.apiCallSucceeded, endpoint: "claudeProxy",
                metadata: Self.makeTelemetryMetadata(
                    requestType: requestType.rawValue,
                    interfaceType: interfaceType,
                    requestBytes: requestBytes,
                    responseBytes: responseBytes,
                    elapsedMs: elapsed,
                    extras: ["statusCode": "200", "responseLength": "\(textCount)"]))
        }

        // Clean up the response — strip markdown code fences if present
        return ClaudeAPIService.cleanJSONResponse(text)
    }

    /// Request recovery insights from the managed agent endpoint.
    /// The server fetches user data from Firestore and runs a multi-step agent analysis.
    /// No request body needed — the server identifies the user via the auth token.
    func requestAgentInsights() async throws -> String {
        let bgTaskID = await beginBackgroundTask(named: "agentInsights")
        defer { endBackgroundTask(bgTaskID) }

        guard let url = URL(string: APIConfig.agentInsightsURL) else {
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
        request.timeoutInterval = 180 // Agent may take longer than regular calls
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8)

        let requestBytes = request.httpBody?.count ?? 0
        let started = Date()
        func elapsedMsInt() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

        await MainActor.run {
            let interfaceType = NetworkMonitor.shared.connectionType.description
            SessionLogger.shared.logAPI(.apiCallStarted, endpoint: "agentInsights",
                metadata: Self.makeTelemetryMetadata(
                    requestType: "recovery_insights_agent",
                    interfaceType: interfaceType,
                    requestBytes: requestBytes))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            let elapsed = elapsedMsInt()
            await MainActor.run {
                let interfaceType = NetworkMonitor.shared.connectionType.description
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "agentInsights",
                    metadata: Self.makeTelemetryMetadata(
                        requestType: "recovery_insights_agent",
                        interfaceType: interfaceType,
                        requestBytes: requestBytes,
                        elapsedMs: elapsed,
                        extras: ["error": error.localizedDescription]))
            }
            throw ClaudeAPIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse(0, "Invalid HTTP response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw ClaudeAPIError.authenticationRequired
        case 429:
            throw ClaudeAPIError.rateLimited
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
            throw ClaudeAPIError.invalidResponse(httpResponse.statusCode, errorBody)
        }

        let claudeResponse: ClaudeResponse
        do {
            claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        } catch {
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            AppLogger.api.error("AgentInsights decode failed. Raw body (\(data.count) bytes): \(rawBody.prefix(500))")
            throw ClaudeAPIError.decodingError(error)
        }

        guard let textBlock = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textBlock.text, !text.isEmpty else {
            throw ClaudeAPIError.noContent
        }

        let elapsed = elapsedMsInt()
        let responseBytes = data.count
        let textCount = text.count
        await MainActor.run {
            let interfaceType = NetworkMonitor.shared.connectionType.description
            SessionLogger.shared.logAPI(.apiCallSucceeded, endpoint: "agentInsights",
                metadata: Self.makeTelemetryMetadata(
                    requestType: "recovery_insights_agent",
                    interfaceType: interfaceType,
                    requestBytes: requestBytes,
                    responseBytes: responseBytes,
                    elapsedMs: elapsed,
                    extras: ["responseLength": "\(textCount)"]))
        }

        return ClaudeAPIService.cleanJSONResponse(text)
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
