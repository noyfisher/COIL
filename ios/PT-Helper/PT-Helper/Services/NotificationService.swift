import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/// Seam for unit-testing scheduling without the real notification center.
protocol NotificationScheduling: AnyObject {
    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?)
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}
extension UNUserNotificationCenter: NotificationScheduling {}

/// Manages local + remote push notification reminders for rehab plan schedules.
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    private let center: NotificationScheduling
    private let defaults: UserDefaults

    @Published var isAuthorized: Bool = false
    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: "notif_reminder_hour") }
    }
    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: "notif_reminder_minute") }
    }
    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "notif_enabled") }
    }

    // MARK: - FCM Token

    @Published var fcmToken: String?

    // MARK: - Notification Type Preferences

    @Published var workoutRemindersEnabled: Bool {
        didSet { defaults.set(workoutRemindersEnabled, forKey: "notif_workout_reminders") }
    }
    @Published var reassessmentRemindersEnabled: Bool {
        didSet { defaults.set(reassessmentRemindersEnabled, forKey: "notif_reassessment_reminders") }
    }
    @Published var inactivityNudgesEnabled: Bool {
        didSet { defaults.set(inactivityNudgesEnabled, forKey: "notif_inactivity_nudges") }
    }

    // MARK: - Deep Link Queue (for cold-launch)

    /// Stores the target tab from a notification tap, consumed by MainTabView/DashboardMainTabView on appear.
    @Published var pendingDeepLink: String?

    init(center: NotificationScheduling = UNUserNotificationCenter.current(), defaults: UserDefaults = .standard, skipAuthCheck: Bool = false) {
        self.center = center
        self.defaults = defaults
        self.reminderHour = defaults.object(forKey: "notif_reminder_hour") as? Int ?? 9
        self.reminderMinute = defaults.object(forKey: "notif_reminder_minute") as? Int ?? 0
        self.isEnabled = defaults.object(forKey: "notif_enabled") as? Bool ?? false
        self.workoutRemindersEnabled = defaults.object(forKey: "notif_workout_reminders") as? Bool ?? true
        self.reassessmentRemindersEnabled = defaults.object(forKey: "notif_reassessment_reminders") as? Bool ?? true
        self.inactivityNudgesEnabled = defaults.object(forKey: "notif_inactivity_nudges") as? Bool ?? true
        if !skipAuthCheck { checkAuthorizationStatus() }
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                self.isAuthorized = granted
                if granted { self.isEnabled = true }
            }
            return granted
        } catch {
            AppLogger.data.error("Notification permission error: \(error.localizedDescription)")
            return false
        }
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Scheduling

    /// Schedule weekly reminders based on a plan's weeklySchedule
    func scheduleReminders(for plan: RehabPlan) {
        guard isEnabled, isAuthorized, workoutRemindersEnabled else { return }

        // Cancel existing reminders for this plan first
        cancelReminders(for: plan.id)

        for (dayIndex, exercises) in plan.weeklySchedule.enumerated() {
            guard !exercises.isEmpty else { continue }

            // Map dayIndex (0=Sun) to calendar weekday (1=Sun)
            let weekday = dayIndex + 1

            let content = UNMutableNotificationContent()
            let streak = StreakService.shared.streakData.currentStreak
            let exerciseText = exercises.count == 1 ? "1 exercise" : "\(exercises.count) exercises"
            // Personalize with streak stakes so reminders read as a personal nudge,
            // not a robotic alarm (audit #35 — also fixes the "(s)" pluralization).
            if streak >= 2 {
                content.title = "Keep your \(streak)-day streak alive 🔥"
                content.body = "\(plan.planName) — \(exerciseText) today keeps the chain going."
            } else {
                content.title = "Time for your exercises!"
                content.body = "\(plan.planName) — \(exerciseText) scheduled today."
            }
            content.sound = .default
            content.badge = 1
            content.userInfo = ["tab": "plans"]

            var dateComponents = DateComponents()
            dateComponents.weekday = weekday
            dateComponents.hour = reminderHour
            dateComponents.minute = reminderMinute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let identifier = notificationId(planId: plan.id, dayIndex: dayIndex)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    AppLogger.data.error("Failed to schedule notification: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancel all reminders for a specific plan
    func cancelReminders(for planId: UUID) {
        let identifiers = (0..<7).map { notificationId(planId: planId, dayIndex: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Cancel all app reminders
    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - Plan-lifecycle reconciliation (WS2)

    /// Last plans list handed over by SavedPlansViewModel's listener; lets
    /// Settings toggles resync without view-layer plumbing (SettingsView is
    /// presented from three contexts, one of them dead code — no @EnvironmentObject).
    private(set) var lastKnownPlans: [RehabPlan] = []

    /// Identifier prefixes owned by the reconciler; every pass removes all
    /// pending requests with these prefixes, then re-schedules from scratch.
    static let reconciledPrefixes = ["plan-", "reassess-", "activation-"]

    /// The one plan that gets weekly workout reminders: most recently started,
    /// not yet completed. Single plan only — two overlapping schedules would
    /// fire duplicate same-minute alerts (spam) and burn the 64-pending cap.
    static func reminderEligiblePlan(from plans: [RehabPlan]) -> RehabPlan? {
        plans.filter { $0.startDate != nil && !$0.isCompleted }
            .max { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// Store the latest plans and reconcile all plan-derived notifications.
    func syncPlanReminders(plans: [RehabPlan]) async {
        lastKnownPlans = plans
        await reconcile()
    }

    /// Re-run reconciliation with the last known plans (Settings toggles / time picker).
    func resyncReminders() async {
        await reconcile()
    }

    private func reconcile() async {
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier)
            .filter { id in Self.reconciledPrefixes.contains { id.hasPrefix($0) } }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        guard isEnabled, isAuthorized else { return }
        if workoutRemindersEnabled, let active = Self.reminderEligiblePlan(from: lastKnownPlans) {
            scheduleReminders(for: active)
        }
        // WS2-03 appends re-assessment scheduling here; WS2-04 the activation nudge.
    }

    // MARK: - Inactivity Nudge (audit #33)

    private let inactivityNudgeId = "inactivity-nudge"
    /// Days of no workout before the "come back" nudge fires.
    private let inactivityNudgeDays = 3

    /// (Re)schedules a "come back" nudge `inactivityNudgeDays` out, gated by the
    /// `inactivityNudgesEnabled` toggle (which previously did nothing). Call after
    /// each workout so the clock resets to the last active day; if the user keeps
    /// working out it never fires, and it lands only after a real lapse.
    func scheduleInactivityNudge() {
        cancelInactivityNudge()
        guard isEnabled, isAuthorized, inactivityNudgesEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your recovery misses you"
        content.body = "It's been a few days — a short session keeps your progress moving."
        content.sound = .default

        let seconds = TimeInterval(inactivityNudgeDays * 24 * 60 * 60)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: inactivityNudgeId, content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                AppLogger.data.error("Failed to schedule inactivity nudge: \(error.localizedDescription)")
            }
        }
    }

    func cancelInactivityNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [inactivityNudgeId])
    }

    /// Update reminder time and reschedule all active plans
    func updateReminderTime(hour: Int, minute: Int, plans: [RehabPlan]) {
        reminderHour = hour
        reminderMinute = minute
        // Reschedule all plans with new time
        for plan in plans {
            scheduleReminders(for: plan)
        }
    }

    // MARK: - FCM Token Management

    /// Called by AppDelegate when FCM registration token is received or refreshed.
    func updateFCMToken(_ token: String) {
        fcmToken = token
        AppLogger.data.info("FCM token updated: \(token.prefix(20))...")
        uploadTokenToFirestore()
    }

    /// Uploads the current FCM token to the user's Firestore document.
    private func uploadTokenToFirestore() {
        guard let token = fcmToken,
              let uid = Auth.auth().currentUser?.uid else { return }

        let db = Firestore.firestore()
        db.collection("users").document(uid).setData([
            "fcmToken": token,
            "fcmTokenUpdatedAt": FieldValue.serverTimestamp()
        ], merge: true) { error in
            if let error {
                AppLogger.data.error("Failed to upload FCM token: \(error.localizedDescription)")
            }
        }
    }

    /// Clears the FCM token from Firestore (called on sign-out).
    func clearFCMToken() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        fcmToken = nil

        let db = Firestore.firestore()
        db.collection("users").document(uid).updateData([
            "fcmToken": FieldValue.delete(),
            "fcmTokenUpdatedAt": FieldValue.delete()
        ]) { error in
            if let error {
                AppLogger.data.error("Failed to clear FCM token: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

    private func notificationId(planId: UUID, dayIndex: Int) -> String {
        "plan-\(planId.uuidString)-day-\(dayIndex)"
    }
}
