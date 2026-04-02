import Foundation
import Vision
import UIKit
import FirebaseFirestore
import FirebaseAuth
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PT-Helper", category: "PostureCheckViewModel")

// MARK: - AI Response

private struct AIPostureResponse: Decodable {
    let score: Int
    let observations: [String]
    let correctiveCues: [String]
}

// MARK: - State

enum PostureCheckState {
    case idle
    case analyzing
    case complete(PostureCheckResult)
    case error(String)
}

// MARK: - ViewModel

@MainActor
final class PostureCheckViewModel: ObservableObject {
    static let shared = PostureCheckViewModel()

    @Published var state: PostureCheckState = .idle
    @Published var selectedContext: PostureContext = .atDesk
    @Published var history: [PostureCheckResult] = []

    private let db = Firestore.firestore()
    private let apiService: ClaudeAPIServiceProtocol

    init(apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) {
        self.apiService = apiService
        Task { await loadHistory() }
    }

    // MARK: - Analysis Pipeline

    /// Analyse a still image for posture quality. Runs Vision pose detection, then calls Claude.
    func analyze(image: UIImage) async {
        state = .analyzing

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Posture check started",
                                  metadata: ["context": selectedContext.rawValue])
        do {
            // 1. Run Vision body pose detection
            let poseDescription = try await detectBodyPose(in: image)

            // 2. Build the AI prompt
            let prompt = buildPrompt(poseDescription: poseDescription)

            // 3. Call Claude
            let responseText = try await apiService.sendMessage(
                requestType: .posture_check,
                userMessage: prompt
            )

            // 4. Parse response
            let result = try parseResponse(responseText)

            state = .complete(result)

            // 5. Save to history
            await save(result: result)

            SessionLogger.shared.log(.stateUpdated, category: .stateChange,
                                      message: "Posture check complete",
                                      metadata: ["score": "\(result.score)",
                                                  "context": selectedContext.rawValue])
        } catch {
            let message = (error as? ClaudeAPIError)?.localizedDescription ?? error.localizedDescription
            state = .error(message)
            logger.error("Posture check failed: \(error.localizedDescription)")
        }
    }

    func reset() {
        state = .idle
    }

    // MARK: - Vision Pose Detection

    private func detectBodyPose(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw PostureCheckError.imageConversionFailed
        }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        try handler.perform([request])

        guard let observation = request.results?.first else {
            // No body detected — provide a basic description for Claude to work with
            return "No body pose landmarks detected. Please use the image context to assess posture."
        }

        return formatPoseObservation(observation, imageSize: image.size)
    }

    private func formatPoseObservation(_ observation: VNHumanBodyPoseObservation, imageSize: CGSize) -> String {
        var lines: [String] = [
            "Context: \(selectedContext.promptDescription)",
            "Image dimensions: \(Int(imageSize.width))x\(Int(imageSize.height))",
            "",
            "Detected body landmarks (normalized x,y; 0,0 = bottom-left, 1,1 = top-right):"
        ]

        let keypoints: [(VNHumanBodyPoseObservation.JointName, String)] = [
            (.nose, "Nose"),
            (.leftEar, "Left Ear"),
            (.rightEar, "Right Ear"),
            (.neck, "Neck"),
            (.leftShoulder, "Left Shoulder"),
            (.rightShoulder, "Right Shoulder"),
            (.leftElbow, "Left Elbow"),
            (.rightElbow, "Right Elbow"),
            (.leftWrist, "Left Wrist"),
            (.rightWrist, "Right Wrist"),
            (.leftHip, "Left Hip"),
            (.rightHip, "Right Hip"),
            (.leftKnee, "Left Knee"),
            (.rightKnee, "Right Knee"),
            (.leftAnkle, "Left Ankle"),
            (.rightAnkle, "Right Ankle"),
        ]

        for (joint, name) in keypoints {
            if let point = try? observation.recognizedPoint(joint),
               point.confidence > 0.3 {
                lines.append(String(format: "  %@: (%.3f, %.3f) confidence=%.2f",
                                    name, point.location.x, point.location.y, point.confidence))
            }
        }

        // Derive key alignment metrics
        lines.append("")
        lines.append("Computed alignment metrics:")

        if let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
           let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
           leftShoulder.confidence > 0.3, rightShoulder.confidence > 0.3 {
            let shoulderTilt = abs(leftShoulder.location.y - rightShoulder.location.y)
            let shoulderWidth = abs(leftShoulder.location.x - rightShoulder.location.x)
            lines.append(String(format: "  Shoulder tilt: %.3f (higher = more uneven)", shoulderTilt))
            lines.append(String(format: "  Shoulder width normalized: %.3f", shoulderWidth))
        }

        if let leftHip = try? observation.recognizedPoint(.leftHip),
           let rightHip = try? observation.recognizedPoint(.rightHip),
           leftHip.confidence > 0.3, rightHip.confidence > 0.3 {
            let hipTilt = abs(leftHip.location.y - rightHip.location.y)
            lines.append(String(format: "  Hip tilt: %.3f (higher = more uneven)", hipTilt))
        }

        if let nose = try? observation.recognizedPoint(.nose),
           let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
           let rightShoulder = try? observation.recognizedPoint(.rightShoulder),
           nose.confidence > 0.3, leftShoulder.confidence > 0.3, rightShoulder.confidence > 0.3 {
            let midShoulderX = (leftShoulder.location.x + rightShoulder.location.x) / 2
            let headForwardOffset = nose.location.x - midShoulderX
            lines.append(String(format: "  Head forward offset: %.3f (+ = forward head posture)", headForwardOffset))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Prompt Building

    private func buildPrompt(poseDescription: String) -> String {
        let profile = UserProfileService.shared.profile
        let profileContext = profile.map {
            "User: \($0.sex ?? "Unknown"), age \($0.ageDescription), activity level: \($0.activityLevel)"
        } ?? ""

        return """
        Assess the posture of someone who is \(selectedContext.promptDescription).

        \(profileContext)

        Body pose data from computer vision analysis:
        \(poseDescription)

        Provide a posture assessment with a score (0–100, where 100 is perfect alignment), 2–3 specific observations about what you see, and 1–2 corrective cues.

        Focus on: head position, shoulder level, spinal alignment, and hip symmetry.
        Use encouraging, non-clinical language. Avoid medical diagnoses.
        """
    }

    // MARK: - Parsing

    private func parseResponse(_ text: String) throws -> PostureCheckResult {
        let jsonText: String
        if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start <= end {
            jsonText = String(text[start...end])
        } else {
            jsonText = text
        }

        guard let data = jsonText.data(using: .utf8) else {
            throw PostureCheckError.parseError("Invalid response encoding")
        }

        let aiResponse = try JSONDecoder().decode(AIPostureResponse.self, from: data)

        return PostureCheckResult(
            context: selectedContext,
            score: max(0, min(100, aiResponse.score)),
            observations: aiResponse.observations,
            correctiveCues: aiResponse.correctiveCues
        )
    }

    // MARK: - History Persistence

    func loadHistory() async {
        // Load from UserDefaults first (offline-first)
        if let cached = loadHistoryFromDefaults() {
            history = cached
        }
        // Sync from Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await db.collection("users").document(uid)
                .collection("postureChecks")
                .order(by: "captureDate", descending: true)
                .limit(to: 30)
                .getDocuments()

            let firestoreResults: [PostureCheckResult] = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let contextRaw = data["context"] as? String,
                      let context = PostureContext(rawValue: contextRaw),
                      let score = data["score"] as? Int,
                      let observations = data["observations"] as? [String],
                      let cues = data["correctiveCues"] as? [String],
                      let timestamp = data["captureDate"] as? Timestamp else { return nil }
                return PostureCheckResult(
                    id: UUID(),
                    context: context,
                    score: score,
                    observations: observations,
                    correctiveCues: cues,
                    captureDate: timestamp.dateValue(),
                    firestoreId: doc.documentID
                )
            }

            if !firestoreResults.isEmpty {
                history = firestoreResults
                saveHistoryToDefaults(firestoreResults)
            }
        } catch {
            logger.warning("Could not load posture history from Firestore: \(error.localizedDescription)")
        }
    }

    private func save(result: PostureCheckResult) async {
        // Prepend to in-memory history
        var updated = history
        updated.insert(result, at: 0)
        if updated.count > 30 { updated = Array(updated.prefix(30)) }
        history = updated
        saveHistoryToDefaults(updated)

        // Save to Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let data: [String: Any] = [
            "context": result.context.rawValue,
            "score": result.score,
            "observations": result.observations,
            "correctiveCues": result.correctiveCues,
            "captureDate": Timestamp(date: result.captureDate)
        ]
        do {
            try await db.collection("users").document(uid)
                .collection("postureChecks").addDocument(data: data)
        } catch {
            logger.warning("Could not save posture check to Firestore: \(error.localizedDescription)")
        }
    }

    // MARK: - UserDefaults Cache

    private let historyDefaultsKey = "PostureCheckHistory"

    private func loadHistoryFromDefaults() -> [PostureCheckResult]? {
        guard let data = UserDefaults.standard.data(forKey: historyDefaultsKey) else { return nil }
        return try? JSONDecoder().decode([PostureCheckResult].self, from: data)
    }

    private func saveHistoryToDefaults(_ results: [PostureCheckResult]) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: historyDefaultsKey)
    }
}

// MARK: - Errors

enum PostureCheckError: LocalizedError {
    case imageConversionFailed
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed: return "Could not process the image. Please try again."
        case .parseError(let msg): return "Analysis response error: \(msg)"
        }
    }
}

// MARK: - UserProfile Extension

private extension UserProfile {
    var ageDescription: String {
        let years = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        return "\(years)"
    }
}
