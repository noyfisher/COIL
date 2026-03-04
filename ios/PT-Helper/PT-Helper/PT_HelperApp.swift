import SwiftUI
import FirebaseCore
import FirebaseFirestore
import UserNotifications

@main
struct PainPointApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        FirebaseApp.configure()   // uses GoogleService-Info.plist in this target

        // Enable explicit Firestore offline persistence (100 MB cache)
        let db = Firestore.firestore()
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings(sizeBytes: NSNumber(value: 100 * 1024 * 1024))
        db.settings = settings
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        SessionLogger.shared.log(.appForegrounded, category: .lifecycle, message: "App foregrounded")
                    case .background:
                        SessionLogger.shared.endSession()
                    default:
                        break
                    }
                }
        }
    }
}

/// AppDelegate for handling foreground notification presentation
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clear badge on tap
        UNUserNotificationCenter.current().setBadgeCount(0)
        completionHandler()
    }
}
