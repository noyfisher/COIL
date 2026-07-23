import XCTest
@testable import COIL

/// P2-01 regression guard: sign-out clears the FCM token with a *bounded* wait.
///
/// The app enables Firestore offline persistence, so an offline `updateData`
/// completion never resolves. Before the fix, `clearFCMToken()` awaited that
/// write directly, so an offline sign-out suspended forever and `Auth.signOut()`
/// never ran — silently leaving a user signed in on a shared device. The write
/// is now wrapped in `awaitWithTimeout`, which must return even when the
/// operation never completes.
@MainActor
final class NotificationServiceTimeoutTests: XCTestCase {

    func testAwaitWithTimeout_operationCompletes_returnsAndRunsIt() async {
        let ran = Flag()
        let start = Date()
        await NotificationService.awaitWithTimeout(seconds: 5) {
            await ran.set()
        }
        let didRun = await ran.value
        XCTAssertTrue(didRun, "operation should have run to completion")
        XCTAssertLessThan(Date().timeIntervalSince(start), 4,
                          "a fast operation should return well before the timeout")
    }

    func testAwaitWithTimeout_operationHangs_returnsWithinBound() async {
        let start = Date()
        // Simulates the offline Firestore write whose completion never resolves.
        await NotificationService.awaitWithTimeout(seconds: 0.3) {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)  // 60s "hang"
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 5,
                          "a hanging operation must not block sign-out past the timeout (was \(elapsed)s)")
    }
}

private actor Flag {
    private(set) var value = false
    func set() { value = true }
}
