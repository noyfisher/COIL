import Foundation
import UserNotifications
@testable import COIL

final class MockNotificationCenter: NotificationScheduling, @unchecked Sendable {
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []
    var removeAllCallCount: Int = 0
    var pendingStub: [UNNotificationRequest] = []

    func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: (@Sendable (Error?) -> Void)?) {
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
