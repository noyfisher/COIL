import XCTest
@testable import PT_Helper

// MARK: - WorkoutViewModel Tests

@MainActor
final class WorkoutViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = WorkoutViewModel()
        XCTAssertTrue(vm.sessions.isEmpty)
    }

    func testAddSession() {
        let vm = WorkoutViewModel()
        let session = WorkoutSession(
            id: UUID(), date: Date(),
            duration: 1800, painLevel: 5.0, isCompleted: true
        )
        vm.addSession(session: session)

        XCTAssertEqual(vm.sessions.count, 1)
        XCTAssertEqual(vm.sessions.first?.painLevel, 5.0)
    }

    func testAddMultipleSessions() {
        let vm = WorkoutViewModel()
        for i in 1...5 {
            vm.addSession(session: WorkoutSession(
                id: UUID(), date: Date(),
                duration: Double(i * 600),
                painLevel: Double(i), isCompleted: true
            ))
        }
        XCTAssertEqual(vm.sessions.count, 5)
        // Sessions are inserted at front (newest first)
        XCTAssertEqual(vm.sessions.first?.painLevel, 5.0)
    }
}
