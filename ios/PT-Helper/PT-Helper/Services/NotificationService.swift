import Foundation
import UserNotifications

/// Manages local push notification reminders for rehab plan schedules.
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

    private init() {
        self.reminderHour = UserDefaults.standard.object(forKey: "notif_reminder_hour") as? Int ?? 9
        self.reminderMinute = UserDefaults.standard.object(forKey: "notif_reminder_minute") as? Int ?? 0
        self.isEnabled = UserDefaults.standard.object(forKey: "notif_enabled") as? Bool ?? false
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
            content.title = "Time for your exercises!"
            content.body = "\(plan.planName) — \(exercises.count) exercise(s) scheduled today"
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

    /// Update reminder time and reschedule all active plans
    func updateReminderTime(hour: Int, minute: Int, plans: [RehabPlan]) {
        reminderHour = hour
        reminderMinute = minute
        // Reschedule all plans with new time
        for plan in plans {
            scheduleReminders(for: plan)
        }
    }

    // MARK: - Helpers

    private func notificationId(planId: UUID, dayIndex: Int) -> String {
        "plan-\(planId.uuidString)-day-\(dayIndex)"
    }
}
