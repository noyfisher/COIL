import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

/// Manages local + remote push notification reminders for rehab plan schedules.
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized: Bool = false
    @Published var reminderHour: Int {
        didSet { UserDefaults.standard.set(reminderHour, forKey: "notif_reminder_hour") }
    }
    @Published var reminderMinute: Int {
        didSet { UserDefaults.standard.set(reminderMinute, forKey: "notif_reminder_minute") }
    }
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "notif_enabled") }
    }

    // MARK: - FCM Token

    @Published var fcmToken: String?

    // MARK: - Notification Type Preferences

    @Published var workoutRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(workoutRemindersEnabled, forKey: "notif_workout_reminders") }
    }
    @Published var reassessmentRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(reassessmentRemindersEnabled, forKey: "notif_reassessment_reminders") }
    }
    @Published var inactivityNudgesEnabled: Bool {
        didSet { UserDefaults.standard.set(inactivityNudgesEnabled, forKey: "notif_inactivity_nudges") }
    }

    // MARK: - Deep Link Queue (for cold-launch)

    /// Stores the target tab from a notification tap, consumed by ThreeTabView on appear.
    @Published var pendingDeepLink: String?

    private init() {
        self.reminderHour = UserDefaults.standard.object(forKey: "notif_reminder_hour") as? Int ?? 9
        self.reminderMinute = UserDefaults.standard.object(forKey: "notif_reminder_minute") as? Int ?? 0
        self.isEnabled = UserDefaults.standard.object(forKey: "notif_enabled") as? Bool ?? false
        self.workoutRemindersEnabled = UserDefaults.standard.object(forKey: "notif_workout_reminders") as? Bool ?? true
        self.reassessmentRemindersEnabled = UserDefaults.standard.object(forKey: "notif_reassessment_reminders") as? Bool ?? true
        self.inactivityNudgesEnabled = UserDefaults.standard.object(forKey: "notif_inactivity_nudges") as? Bool ?? true
        checkAuthorizationStatus()
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
        guard isEnabled, isAuthorized else { return }

        // Cancel existing reminders for this plan first
        cancelReminders(for: plan.id)

        let center = UNUserNotificationCenter.current()

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
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Cancel all app reminders
    func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().setBadgeCount(0)
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
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                AppLogger.data.error("Failed to schedule inactivity nudge: \(error.localizedDescription)")
            }
        }
    }

    func cancelInactivityNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [inactivityNudgeId])
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
