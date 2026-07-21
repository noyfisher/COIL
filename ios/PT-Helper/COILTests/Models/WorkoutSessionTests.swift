import XCTest
@testable import COIL

// MARK: - WorkoutSession Tests

final class WorkoutSessionTests: XCTestCase {

    func testSessionCreation() {
        let session = WorkoutSession(
            id: UUID(),
            date: Date(),
            duration: 1800, // 30 minutes
            painLevel: 5.0,
            isCompleted: true
        )
        XCTAssertEqual(session.duration, 1800)
        XCTAssertEqual(session.painLevel, 5.0)
        XCTAssertTrue(session.isCompleted)
    }
}
