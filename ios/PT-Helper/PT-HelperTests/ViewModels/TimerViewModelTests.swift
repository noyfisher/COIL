import XCTest
@testable import PT_Helper

// MARK: - TimerViewModel Tests

final class TimerViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = TimerViewModel()

        XCTAssertEqual(vm.timer.duration, 300, "Default duration should be 5 minutes")
        XCTAssertEqual(vm.timer.timeRemaining, 300)
        XCTAssertFalse(vm.timer.isRunning)
    }

    func testTimeString_fiveMinutes() {
        let vm = TimerViewModel()

        XCTAssertEqual(vm.timeString, "05:00")
    }

    // MARK: - Start / Stop

    func testStart_setsRunningTrue() {
        let vm = TimerViewModel()

        vm.start()

        XCTAssertTrue(vm.timer.isRunning)
        vm.stop() // cleanup
    }

    func testStop_setsRunningFalse() {
        let vm = TimerViewModel()
        vm.start()

        vm.stop()

        XCTAssertFalse(vm.timer.isRunning)
    }

    func testStart_calledTwice_doesNotResubscribe() {
        let vm = TimerViewModel()

        vm.start()
        vm.start() // should be a no-op

        XCTAssertTrue(vm.timer.isRunning)
        vm.stop()
    }

    // MARK: - Reset

    func testReset_restoresDuration() {
        let vm = TimerViewModel()
        vm.timer.timeRemaining = 100

        vm.reset()

        XCTAssertEqual(vm.timer.timeRemaining, 300, "Reset should restore to full duration")
        XCTAssertFalse(vm.timer.isRunning)
    }

    func testReset_stopsTimer() {
        let vm = TimerViewModel()
        vm.start()

        vm.reset()

        XCTAssertFalse(vm.timer.isRunning)
    }

    // MARK: - Timer Decrement (functional)

    func testTimerDecrement_afterOneSecond() async throws {
        let vm = TimerViewModel()
        vm.start()

        // Wait slightly more than 1 second for the timer to tick
        try await Task.sleep(nanoseconds: 1_200_000_000)

        XCTAssertLessThan(vm.timer.timeRemaining, 300, "Timer should have decremented")
        vm.stop()
    }

    func testTimerStopsAtZero() {
        let vm = TimerViewModel()
        vm.timer.timeRemaining = 1
        vm.start()

        // Simulate the internal updateTimer call sequence
        // After timeRemaining becomes 0, the timer should stop
        // We can't easily call updateTimer (it's private), but we can test via the
        // actual timer mechanism with a short wait
        let expectation = XCTestExpectation(description: "Timer reaches zero")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            XCTAssertEqual(vm.timer.timeRemaining, 0)
            XCTAssertFalse(vm.timer.isRunning, "Timer should auto-stop at zero")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
    }

    // MARK: - Time String Formatting

    func testTimeString_zeroSeconds() {
        let vm = TimerViewModel()
        vm.timer.timeRemaining = 0

        XCTAssertEqual(vm.timeString, "00:00")
    }

    func testTimeString_oneMinuteThirty() {
        let vm = TimerViewModel()
        vm.timer.timeRemaining = 90

        XCTAssertEqual(vm.timeString, "01:30")
    }

    func testTimeString_tenMinutes() {
        let vm = TimerViewModel()
        vm.timer.timeRemaining = 600

        XCTAssertEqual(vm.timeString, "10:00")
    }
}
