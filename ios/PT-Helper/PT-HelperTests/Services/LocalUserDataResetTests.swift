import XCTest
@testable import PT_Helper

@MainActor
final class LocalUserDataResetTests: XCTestCase {
    private let checkpointKey = "GuidedWorkoutCheckpoint"
    private let completionKey = "exerciseCompletions_Squats"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: checkpointKey)
        UserDefaults.standard.removeObject(forKey: completionKey)
        super.tearDown()
    }

    func testClearAllLocalWorkoutState_RemovesCheckpointAndCompletionKeys() {
        // Seed a workout checkpoint blob and a per-exercise completion counter.
        UserDefaults.standard.set(Data([0x01, 0x02, 0x03]), forKey: checkpointKey)
        UserDefaults.standard.set(5, forKey: completionKey)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: checkpointKey))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: completionKey), 5)

        GuidedWorkoutViewModel.clearAllLocalWorkoutState()

        XCTAssertNil(UserDefaults.standard.data(forKey: checkpointKey),
                     "Checkpoint should be removed after clearing local workout state")
        XCTAssertNil(UserDefaults.standard.object(forKey: completionKey),
                     "Per-exercise completion counter should be removed after clearing local workout state")
    }
}
