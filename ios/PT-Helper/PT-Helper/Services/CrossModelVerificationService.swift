import Foundation
import FirebaseAuth
import os

// MARK: - Cross-Model Verification Result

struct CrossModelResult {
    let exerciseName: String
    let conditionName: String
    let isSafe: Bool
    let confidence: Double
    let reasoning: String
    let concerns: [String]
}

/// The final verification status for an exercise after all verification tiers have been attempted.
enum ExerciseVerificationStatus: Equatable {
    case verified                                    // Knowledge graph confirms safe
    case contraindicated(reason: String)             // Knowledge graph confirms unsafe
    case crossModelVerified                          // GPT-4o-mini confirms safe
    case crossModelFlagged(concerns: [String])       // GPT-4o-mini has concerns
    case crossModelFailed                            // Cross-model check failed (network, etc.)
    case checking                                    // Cross-model check in progress

    static func == (lhs: ExerciseVerificationStatus, rhs: ExerciseVerificationStatus) -> Bool {
        switch (lhs, rhs) {
        case (.verified, .verified): return true
        case (.contraindicated(let a), .contraindicated(let b)): return a == b
        case (.crossModelVerified, .crossModelVerified): return true
        case (.crossModelFlagged(let a), .crossModelFlagged(let b)): return a == b
        case (.crossModelFailed, .crossModelFailed): return true
        case (.checking, .checking): return true
        default: return false
        }
    }
}

// MARK: - Cross-Model Verification Service

class CrossModelVerificationService {
    static let shared = CrossModelVerificationService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper", category: "crossModel")
    private let crossVerifyURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/crossVerify"

    private init() {}

    /// Maximum exercises per request (server enforces max 20).
    private let maxBatchSize = 20

    /// Verify unverified exercises against a second AI model (GPT-4o-mini).
    /// Automatically batches into chunks of 20 if needed.
    func verify(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult] {
        guard !exercises.isEmpty else { return [] }

        logger.info("Cross-model verification requested for \(exercises.count) exercise(s)")

        // Split into batches of maxBatchSize to stay within server limit
        var allResults: [CrossModelResult] = []
        let batches = stride(from: 0, to: exercises.count, by: maxBatchSize).map {
            Array(exercises[$0..<min($0 + maxBatchSize, exercises.count)])
        }

        logger.info("Splitting into \(batches.count) batch(es)")
        for (index, batch) in batches.enumerated() {
            logger.debug("Sending batch \(index + 1)/\(batches.count) with \(batch.count) exercise(s)")
            let batchResults = try await sendBatch(exercises: batch, patientContext: patientContext)
            allResults.append(contentsOf: batchResults)
        }

        logger.info("Cross-model verification complete: \(allResults.filter { $0.isSafe }.count) safe, \(allResults.filter { !$0.isSafe }.count) flagged")
        return allResults
    }

    /// Send a single batch (max 20) to the crossVerify endpoint.
    private func sendBatch(
        exercises: [(name: String, condition: String)],
        patientContext: String
    ) async throws -> [CrossModelResult] {
        guard let url = URL(string: crossVerifyURL) else {
            logger.error("Invalid crossVerify URL")
            throw CrossModelError.invalidURL
        }

        // Get Firebase Auth token
        guard let currentUser = Auth.auth().currentUser else {
            throw CrossModelError.authenticationRequired
        }

        let idToken: String
        do {
            idToken = try await currentUser.getIDToken()
        } catch {
            throw CrossModelError.authenticationRequired
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let exercisesPayload = exercises.map { exercise in
            ["name": exercise.name, "condition": exercise.condition]
        }

        let body: [String: Any] = [
            "exercises": exercisesPayload,
            "patientContext": patientContext
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Make request
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("Cross-model network error: \(error.localizedDescription)")
            throw CrossModelError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CrossModelError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Cross-model error (\(httpResponse.statusCode)): \(errorBody)")
            throw CrossModelError.serverError(httpResponse.statusCode)
        }

        // Parse response
        return try parseCrossModelResponse(data, exercises: exercises)
    }

    // MARK: - Response Parsing

    private func parseCrossModelResponse(_ data: Data, exercises: [(name: String, condition: String)]) throws -> [CrossModelResult] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CrossModelError.decodingError
        }

        // Handle single exercise response
        if let safe = json["safe"] as? Bool {
            guard let firstExercise = exercises.first else { throw CrossModelError.decodingError }
            return [CrossModelResult(
                exerciseName: firstExercise.name,
                conditionName: firstExercise.condition,
                isSafe: safe,
                confidence: json["confidence"] as? Double ?? 0.5,
                reasoning: json["reasoning"] as? String ?? "",
                concerns: json["concerns"] as? [String] ?? []
            )]
        }

        // Handle batched response
        guard let results = json["results"] as? [[String: Any]] else {
            throw CrossModelError.decodingError
        }

        return zip(results, exercises).map { (result, exercise) in
            CrossModelResult(
                exerciseName: exercise.name,
                conditionName: exercise.condition,
                isSafe: result["safe"] as? Bool ?? false,
                confidence: result["confidence"] as? Double ?? 0.5,
                reasoning: result["reasoning"] as? String ?? "",
                concerns: result["concerns"] as? [String] ?? []
            )
        }
    }
}

// MARK: - Cross-Model Errors

enum CrossModelError: LocalizedError {
    case invalidURL
    case authenticationRequired
    case networkError(Error)
    case invalidResponse
    case serverError(Int)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid verification service URL."
        case .authenticationRequired: return "Authentication required for verification."
        case .networkError(let error): return "Network error during verification: \(error.localizedDescription)"
        case .invalidResponse: return "Invalid response from verification service."
        case .serverError(let code): return "Verification service error (status \(code))."
        case .decodingError: return "Failed to parse verification response."
        }
    }
}
