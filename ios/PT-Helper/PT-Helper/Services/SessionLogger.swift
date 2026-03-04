import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

/// Persistent session event logger for tester bug reproduction.
/// Captures a timestamped trail of user actions, navigation, API calls,
/// and errors that can be exported or auto-uploaded to Firebase.
@MainActor
class SessionLogger: ObservableObject {
    static let shared = SessionLogger()

    @Published private(set) var eventCount: Int = 0

    private var currentLog: SessionLog
    private let maxEvents = 500
    private let persistBatchSize = 10
    private var eventsSinceLastPersist = 0

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    private var currentLogURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("session_log_current.json")
    }
    private var previousLogURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("session_log_previous.json")
    }

    private init() {
        currentLog = SessionLog(
            sessionId: UUID(),
            userId: "anonymous",
            startedAt: Date(),
            deviceContext: DeviceContext.current(),
            events: [],
            crashMarker: false
        )
    }

    // MARK: - Session Lifecycle

    func startSession(userId: String) {
        // Check for crash from previous session
        var crashDetected = false
        if let previousData = try? Data(contentsOf: currentLogURL),
           let previousLog = try? decoder.decode(SessionLog.self, from: previousData) {
            if previousLog.endedAt == nil {
                crashDetected = true
                // Save previous log for crash recovery upload
                try? previousData.write(to: previousLogURL, options: .atomic)
                Task { await uploadPreviousSessionLog() }
            }
            // Clean up
            try? fileManager.removeItem(at: currentLogURL)
        }

        currentLog = SessionLog(
            sessionId: UUID(),
            userId: userId,
            startedAt: Date(),
            deviceContext: DeviceContext.current(),
            events: [],
            crashMarker: crashDetected
        )
        eventCount = 0
        eventsSinceLastPersist = 0

        log(.appLaunched, category: .lifecycle, message: "Session started",
            metadata: crashDetected ? ["crashRecovery": "true"] : nil)
    }

    func endSession() {
        currentLog.endedAt = Date()
        log(.appBackgrounded, category: .lifecycle, message: "Session ended")
        persistToDisk()
    }

    // MARK: - Logging API

    func log(
        _ type: SessionEvent.EventType,
        category: SessionEvent.EventCategory,
        message: String,
        metadata: [String: String]? = nil
    ) {
        let event = SessionEvent(category: category, type: type, message: message, metadata: metadata)
        currentLog.events.append(event)
        eventCount = currentLog.events.count
        trimEventsIfNeeded()

        eventsSinceLastPersist += 1
        if eventsSinceLastPersist >= persistBatchSize {
            persistToDisk()
        }
    }

    // MARK: - Convenience Methods

    func logNavigation(_ type: SessionEvent.EventType, screen: String, metadata: [String: String]? = nil) {
        var meta = metadata ?? [:]
        meta["screen"] = screen
        log(type, category: .navigation, message: screen, metadata: meta)
    }

    func logUserAction(_ type: SessionEvent.EventType, action: String, metadata: [String: String]? = nil) {
        var meta = metadata ?? [:]
        meta["action"] = action
        log(type, category: .userAction, message: action, metadata: meta)
    }

    func logAPI(_ type: SessionEvent.EventType, endpoint: String, metadata: [String: String]? = nil) {
        var meta = metadata ?? [:]
        meta["endpoint"] = endpoint
        log(type, category: .api, message: endpoint, metadata: meta)
    }

    func logError(_ error: Error, context: String, metadata: [String: String]? = nil) {
        var meta = metadata ?? [:]
        meta["context"] = context
        meta["errorDomain"] = String(describing: Swift.type(of: error))
        meta["errorDescription"] = error.localizedDescription
        log(.errorOccurred, category: .error, message: "\(context): \(error.localizedDescription)", metadata: meta)

        // Auto-upload on critical errors
        Task { await uploadToFirestore() }
    }

    func logStateChange(viewModel: String, property: String, value: String) {
        log(.stateUpdated, category: .stateChange, message: "\(viewModel).\(property) = \(value)",
            metadata: ["viewModel": viewModel, "property": property, "value": value])
    }

    // MARK: - Persistence

    private func persistToDisk() {
        eventsSinceLastPersist = 0
        guard let data = try? encoder.encode(currentLog) else { return }
        try? data.write(to: currentLogURL, options: .atomic)
    }

    // MARK: - Export

    func exportAsShareableFile() -> URL? {
        guard let data = try? encoder.encode(currentLog) else { return nil }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let dateString = dateFormatter.string(from: Date())
        let sessionPrefix = currentLog.sessionId.uuidString.prefix(8)
        let fileName = "pt-helper-session-\(sessionPrefix)-\(dateString).json"
        let tempURL = fileManager.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            AppLogger.data.error("Failed to export session log: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Auto-Upload

    func uploadToFirestore() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let jsonData = try? encoder.encode(currentLog) else { return }

        let db = Firestore.firestore()
        let sessionId = currentLog.sessionId.uuidString

        do {
            // Upload full JSON to Firebase Storage
            let storageRef = Storage.storage().reference()
                .child("sessionLogs/\(userId)/\(sessionId).json")
            let metadata = StorageMetadata()
            metadata.contentType = "application/json"
            _ = try await storageRef.putDataAsync(jsonData, metadata: metadata)

            // Write index document to Firestore
            let indexData: [String: Any] = [
                "sessionId": sessionId,
                "userId": userId,
                "startedAt": Timestamp(date: currentLog.startedAt),
                "crashMarker": currentLog.crashMarker,
                "eventCount": currentLog.events.count,
                "appVersion": currentLog.deviceContext.appVersion,
                "buildNumber": currentLog.deviceContext.buildNumber,
                "deviceModel": currentLog.deviceContext.deviceModel,
                "osVersion": currentLog.deviceContext.osVersion,
                "uploadedAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("sessionLogs").document(sessionId).setData(indexData)
            AppLogger.data.info("Session log uploaded: \(sessionId)")
        } catch {
            AppLogger.data.error("Failed to upload session log: \(error.localizedDescription)")
        }
    }

    private func uploadPreviousSessionLog() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let data = try? Data(contentsOf: previousLogURL),
              let previousLog = try? decoder.decode(SessionLog.self, from: data) else { return }

        let sessionId = previousLog.sessionId.uuidString

        do {
            let storageRef = Storage.storage().reference()
                .child("sessionLogs/\(userId)/\(sessionId).json")
            let metadata = StorageMetadata()
            metadata.contentType = "application/json"
            _ = try await storageRef.putDataAsync(data, metadata: metadata)

            let indexData: [String: Any] = [
                "sessionId": sessionId,
                "userId": userId,
                "startedAt": Timestamp(date: previousLog.startedAt),
                "crashMarker": true,
                "eventCount": previousLog.events.count,
                "appVersion": previousLog.deviceContext.appVersion,
                "buildNumber": previousLog.deviceContext.buildNumber,
                "deviceModel": previousLog.deviceContext.deviceModel,
                "osVersion": previousLog.deviceContext.osVersion,
                "uploadedAt": FieldValue.serverTimestamp()
            ]
            try await Firestore.firestore().collection("sessionLogs").document(sessionId).setData(indexData)
            AppLogger.data.info("Crash session log uploaded: \(sessionId)")

            // Clean up
            try? fileManager.removeItem(at: previousLogURL)
        } catch {
            AppLogger.data.error("Failed to upload crash session log: \(error.localizedDescription)")
        }
    }

    // MARK: - Bounding

    private func trimEventsIfNeeded() {
        if currentLog.events.count > maxEvents {
            let overflow = currentLog.events.count - maxEvents
            currentLog.events.removeFirst(overflow)
        }
    }
}
