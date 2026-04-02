import SwiftUI
import FirebaseCore
import FirebaseCrashlytics
import FirebaseFirestore
import GoogleSignIn
import FirebaseMessaging
import UserNotifications

@main
struct PainPointApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    init() {
        FirebaseApp.configure()   // uses GoogleService-Info.plist in this target
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)

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
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        SessionLogger.shared.log(.appForegrounded, category: .lifecycle, message: "App foregrounded")
                        AnalyticsService.shared.log(.appOpened)
                    case .background:
                        SessionLogger.shared.endSession()
                    default:
                        break
                    }
                }
                .task {
                    TestDataSeeder.seedIfNeeded()
                }
        }
    }
}

/// AppDelegate for handling foreground notification presentation
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        Messaging.messaging().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            NotificationService.shared.updateFCMToken(fcmToken ?? "")
        }
    }

    /// Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Clear badge on tap
        UNUserNotificationCenter.current().setBadgeCount(0)

        // Parse deep link from notification payload
        let userInfo = response.notification.request.content.userInfo
        if let tab = userInfo["tab"] as? String {
            NotificationService.shared.pendingDeepLink = tab
            NotificationCenter.default.post(name: .deepLink, object: nil)
        }

        completionHandler()
    }
}
