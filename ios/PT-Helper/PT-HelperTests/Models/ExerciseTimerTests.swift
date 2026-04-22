import XCTest
@testable import PT_Helper

// MARK: - ExerciseTimer Tests

final class ExerciseTimerTests: XCTestCase {

    func testTimerInitialization() {
        let timer = ExerciseTimer(duration: 300)
        XCTAssertEqual(timer.duration, 300)
        XCTAssertEqual(timer.timeRemaining, 300)
        XCTAssertFalse(timer.isRunning)
    }

    func testTimerStateChanges() {
        let timer = ExerciseTimer(duration: 60)
        timer.isRunning = true
        XCTAssertTrue(timer.isRunning)
        timer.timeRemaining = 30
        XCTAssertEqual(timer.timeRemaining, 30)
    }
}
