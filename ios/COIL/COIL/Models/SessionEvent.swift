import Foundation
import UIKit

/// A single event in the session trail for bug reproduction.
struct SessionEvent: Codable {
    let id: UUID
    let timestamp: Date
    let category: EventCategory
    let type: EventType
    let message: String
    let metadata: [String: String]?

    init(
        category: EventCategory,
        type: EventType,
        message: String,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.category = category
        self.type = type
        self.message = message
        self.metadata = metadata
    }

    enum EventCategory: String, Codable {
        case navigation
        case userAction
        case api
        case data
        case stateChange
        case error
        case lifecycle
        case auth
        case system
    }

    enum EventType: String, Codable {
        // Navigation
        case screenAppeared, screenDisappeared, tabSwitched
        case sheetPresented, sheetDismissed
        // User Actions
        case buttonTapped, toggleChanged, sliderChanged
        case regionSelected, regionDeselected, formSubmitted
        // API
        case apiCallStarted, apiCallSucceeded, apiCallFailed
        // Data
        case firestoreRead, firestoreWrite, firestoreDelete
        case cacheHit, cacheMiss
        // State
        case stateUpdated, loadingStarted, loadingFinished
        // Error
        case errorOccurred, errorRecovered
        // Lifecycle
        case appLaunched, appForegrounded, appBackgrounded
        // Auth
        case signInStarted, signInSucceeded, signInFailed, signedOut
        // System
        case connectivityChanged, memoryWarning
    }
}

/// Container for a full session log with device context.
struct SessionLog: Codable {
    let sessionId: UUID
    let userId: String
    let startedAt: Date
    var endedAt: Date?
    let deviceContext: DeviceContext
    var events: [SessionEvent]
    var crashMarker: Bool
}

/// Device and app context captured once per session.
struct DeviceContext: Codable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let deviceModel: String
    let locale: String
    let timezone: String
    let isTestFlight: Bool
    let connectionType: String

    @MainActor static func current() -> DeviceContext {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }

        return DeviceContext(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            osVersion: "iOS \(UIKit.UIDevice.current.systemVersion)",
            deviceModel: machine,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier,
            isTestFlight: Self.isRunningInTestFlight,
            connectionType: NetworkMonitor.shared.connectionType.description
        )
    }

    /// Detect TestFlight builds without using the iOS-18-deprecated `appStoreReceiptURL`.
    ///
    /// Heuristic: App Store builds have `embedded.mobileprovision` stripped at signing
    /// time, TestFlight (and Ad-Hoc/Enterprise) builds retain it. Combined with a
    /// `!DEBUG` guard, the presence of the provisioning profile reliably signals
    /// TestFlight in release-channel installs.
    ///
    /// The proper StoreKit 2 replacement is `AppTransaction.shared`, but that API
    /// is async — adopting it would force `DeviceContext.current()` async and
    /// ripple through every synchronous SessionLogger call site.
    private static var isRunningInTestFlight: Bool {
        #if DEBUG
        return false
        #else
        return Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil
        #endif
    }
}

extension NetworkMonitor.ConnectionType: CustomStringConvertible {
    var description: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "cellular"
        case .wired: return "wired"
        case .unknown: return "unknown"
        }
    }
}
