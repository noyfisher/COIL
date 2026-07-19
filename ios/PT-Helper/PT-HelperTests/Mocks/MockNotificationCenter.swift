import Foundation
import UserNotifications
@testable import PT_Helper

final class MockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var removeAllCallCount: Int = 0
    var pendingStub: [UNNotificationRequest] = []

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)?) {
        addedRequests.append(request)
        completionHandler?(nil)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        removeAllCallCount += 1
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        pendingStub + addedRequests
    }
}
