import Foundation
import FirebaseAuth

// MARK: - Error Types

enum ClaudeAPIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(Int, String)
    case decodingError(Error)
    case noContent
    case rateLimited
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL configuration."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription). Please check your internet connection."
        case .invalidResponse(let statusCode, let details):
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
}

// MARK: - Claude API Service

class ClaudeAPIService: ClaudeAPIServiceProtocol {
    static let shared = ClaudeAPIService()

    private init() {}

    /// Send a message to the Claude API via the Firebase proxy and return the text response.
    /// The system prompt, model, and max_tokens are controlled server-side for security.
    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String {
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

        // Make the API call
        await MainActor.run {
            SessionLogger.shared.logAPI(.apiCallStarted, endpoint: "claudeProxy",
                                         metadata: ["requestType": requestType.rawValue])
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            await MainActor.run {
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                                             metadata: ["requestType": requestType.rawValue,
                                                         "error": error.localizedDescription])
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
            await MainActor.run {
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                                             metadata: ["requestType": requestType.rawValue,
                                                         "statusCode": "401", "error": "authRequired"])
            }
            throw ClaudeAPIError.authenticationRequired
        case 429:
            await MainActor.run {
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                                             metadata: ["requestType": requestType.rawValue,
                                                         "statusCode": "429", "error": "rateLimited"])
            }
            throw ClaudeAPIError.rateLimited
        default:
            let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
            AppLogger.api.error("Claude Proxy Error (\(httpResponse.statusCode)): \(errorBody)")
            await MainActor.run {
                SessionLogger.shared.logAPI(.apiCallFailed, endpoint: "claudeProxy",
                                             metadata: ["requestType": requestType.rawValue,
                                                         "statusCode": "\(httpResponse.statusCode)"])
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

        await MainActor.run {
            SessionLogger.shared.logAPI(.apiCallSucceeded, endpoint: "claudeProxy",
                                         metadata: ["requestType": requestType.rawValue,
                                                     "statusCode": "200",
                                                     "responseLength": "\(text.count)"])
        }

        // Clean up the response — strip markdown code fences if present
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
