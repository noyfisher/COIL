import Foundation
import FirebaseCrashlytics
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

    /// Upload throttling — prevents a burst of errors from each triggering a
    /// full Storage + Firestore write of the session log. Every upload writes
    /// the *entire* log (not a delta), so 10 errors in 30s would otherwise
    /// produce 10 increasingly-redundant uploads.
    private static let minUploadInterval: TimeInterval = 60
    private var lastUploadAt: Date?
    private var lastUploadedEventCount: Int = 0

    /// True when running inside a unit-test host. Tests drive ViewModels
    /// through this singleton, which leaves a deterministic orphaned session
    /// file behind; the next real launch then uploads that test trail via
    /// crash recovery under whichever user is signed in (the 170-event
    /// "Login-only" trail misdiagnosed as F4 in virtual-users/results/2026-06-09).
    /// In-memory logging stays on; disk persistence and uploads are disabled.
    private static let isTestHost =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("session_log_current.json")
    }
    private var previousLogURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
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
                try? previousData.write(to: previousLogURL, options: [.atomic, .completeFileProtection])
            }
            // Clean up
            try? fileManager.removeItem(at: currentLogURL)
        }

        // Upload any pending previous-session log — covers both a crash just
        // detected above and an orphaned file from an earlier attempt that
        // raced an auth transition (sign-out before the upload task ran).
        if fileManager.fileExists(atPath: previousLogURL.path) {
            Task { await uploadPreviousSessionLog() }
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
        lastUploadAt = nil
        lastUploadedEventCount = 0

        log(.appLaunched, category: .lifecycle, message: "Session started",
            metadata: crashDetected ? ["crashRecovery": "true"] : nil)
    }

    func endSession() {
        currentLog.endedAt = Date()
        log(.appBackgrounded, category: .lifecycle, message: "Session ended")
        persistToDisk()
    }

    /// Reopens the current session after a return to foreground. Clears
    /// `endedAt` so the crash detector in `startSession` can still flag a
    /// genuine crash that happens after the app was backgrounded once.
    /// Only persists when an ended session is actually being reopened —
    /// at cold launch `.active` fires before `startSession`, and persisting
    /// here would clobber the previous session's file before crash detection
    /// reads it.
    func resumeSession() {
        let wasEnded = currentLog.endedAt != nil
        currentLog.endedAt = nil
        log(.appForegrounded, category: .lifecycle, message: "App foregrounded")
        if wasEnded { persistToDisk() }
    }

    /// Completes and clears session logging on sign-out so the signing-out
    /// user's trail neither uploads under the next account nor bleeds into their
    /// in-memory session (P1-03). The trail is discarded rather than uploaded:
    /// by the time the auth listener reports sign-out the user's credentials are
    /// already gone, so it cannot be uploaded under its true owner — and
    /// uploading it under the next user is exactly the cross-account leak we are
    /// preventing. Invoked via `AccountSessionContext.signOutCleanup()`.
    func finalizeForSignOut() {
        log(.signedOut, category: .auth, message: "User signed out")
        // Discard the signing-out user's on-disk trail (owned by them; cannot be
        // uploaded now, and must never upload under the next account).
        try? fileManager.removeItem(at: currentLogURL)
        try? fileManager.removeItem(at: previousLogURL)
        // Reset the in-memory trail so the next account starts clean.
        currentLog = SessionLog(
            sessionId: UUID(),
            userId: "anonymous",
            startedAt: Date(),
            deviceContext: DeviceContext.current(),
            events: [],
            crashMarker: false
        )
        eventCount = 0
        eventsSinceLastPersist = 0
        lastUploadAt = nil
        lastUploadedEventCount = 0
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

        // Record non-fatal in Crashlytics for crash-free metrics
        Crashlytics.crashlytics().record(error: error, userInfo: ["context": context])

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
        guard !Self.isTestHost else { return }
        guard let data = try? encoder.encode(currentLog) else { return }
        try? data.write(to: currentLogURL, options: [.atomic, .completeFileProtection])
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
            try data.write(to: tempURL, options: [.atomic, .completeFileProtection])
            return tempURL
        } catch {
            AppLogger.data.error("Failed to export session log: \(error.localizedDescription)")
            return nil
        }
    }

    /// Removes all locally persisted session-log data (account deletion).
    func clearAllLocalData() {
        currentLog.events.removeAll()
        eventCount = 0
        eventsSinceLastPersist = 0
        lastUploadedEventCount = 0
        try? fileManager.removeItem(at: currentLogURL)
        try? fileManager.removeItem(at: previousLogURL)
    }

    // MARK: - Auto-Upload

    /// Whether a session log may be uploaded, given its immutable owner and the
    /// currently signed-in user. A log is bound to the account that created it;
    /// only that account may upload it (Storage rules enforce the same), so a
    /// mismatch means an account switch on a shared device and the log must be
    /// quarantined — never re-homed under the current account (P1-03).
    enum SessionLogUploadDecision: Equatable {
        case upload(owner: String)
        case skipNoUser            // nobody signed in — cannot upload now, keep for later
        case quarantineForeignOwner // belongs to a different (or anonymous) account
    }

    nonisolated static func uploadDecision(
        logOwner: String,
        currentUser: String?
    ) -> SessionLogUploadDecision {
        guard let currentUser else { return .skipNoUser }
        guard logOwner != "anonymous", logOwner == currentUser else {
            return .quarantineForeignOwner
        }
        return .upload(owner: logOwner)
    }

    /// - Parameter force: bypasses the time throttle (not the no-new-events
    ///   dedup). Used when the app is backgrounding — the last chance to
    ///   upload this session's trail before suspension.
    func uploadToFirestore(force: Bool = false) async {
        guard !Self.isTestHost else { return }

        // Bind the upload to the log's immutable owner, not whoever is currently
        // signed in. On an account switch this returns before any IO so one
        // user's trail is never written into another user's storage (P1-03).
        let userId: String
        switch Self.uploadDecision(logOwner: currentLog.userId,
                                   currentUser: Auth.auth().currentUser?.uid) {
        case .upload(let owner): userId = owner
        case .skipNoUser, .quarantineForeignOwner: return
        }

        // Dedup: skip if no new events since the last upload.
        if currentLog.events.count == lastUploadedEventCount { return }

        // Throttle: skip if we uploaded within the last minUploadInterval.
        // Next caller after the window will carry the accumulated events.
        if !force, let last = lastUploadAt,
           Date().timeIntervalSince(last) < Self.minUploadInterval {
            return
        }

        // Reserve the upload slot *before* doing the IO so concurrent callers
        // don't all race past the guard.
        lastUploadAt = Date()
        lastUploadedEventCount = currentLog.events.count

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
            var indexData: [String: Any] = [
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
            if let endedAt = currentLog.endedAt {
                indexData["endedAt"] = Timestamp(date: endedAt)
            }
            try await db.collection("sessionLogs").document(sessionId).setData(indexData)
            AppLogger.data.info("Session log uploaded: \(sessionId)")
        } catch {
            AppLogger.data.error("Failed to upload session log: \(error.localizedDescription)")
        }
    }

    private func uploadPreviousSessionLog() async {
        guard !Self.isTestHost else { return }
        guard let data = try? Data(contentsOf: previousLogURL),
              let previousLog = try? decoder.decode(SessionLog.self, from: data) else { return }

        // Upload only under the account that created this log. If the current
        // user differs (account switch on a shared device), Storage rules would
        // reject a write to the true owner's path anyway, and writing it under
        // the current user would leak one user's trail into another's account —
        // so quarantine it by erasing the local file instead (P1-03).
        let userId: String
        switch Self.uploadDecision(logOwner: previousLog.userId,
                                   currentUser: Auth.auth().currentUser?.uid) {
        case .upload(let owner):
            userId = owner
        case .skipNoUser:
            return  // no auth right now — leave the file for a later signed-in launch
        case .quarantineForeignOwner:
            try? fileManager.removeItem(at: previousLogURL)
            return
        }

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
