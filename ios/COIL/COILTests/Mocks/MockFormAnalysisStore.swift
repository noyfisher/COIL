import Foundation
@testable import COIL

/// Mock implementation of FormAnalysisStoreProtocol for unit testing.
/// Configure `priorCountToReturn` to control agent-path routing; saved records
/// are captured in `savedRecords` for assertions.
final class MockFormAnalysisStore: FormAnalysisStoreProtocol {
    /// The prior-session count returned by `priorSessionCount`.
    var priorCountToReturn: Int = 0

    /// All records passed to `save`, in order.
    private(set) var savedRecords: [FormAnalysisRecord] = []

    /// The most recent exerciseName passed to `priorSessionCount`.
    private(set) var lastQueriedExerciseName: String?

    /// Number of times `priorSessionCount` was called.
    private(set) var priorSessionCountCallCount = 0

    func save(_ record: FormAnalysisRecord) async {
        savedRecords.append(record)
    }

    func priorSessionCount(exerciseName: String) async -> Int {
        priorSessionCountCallCount += 1
        lastQueriedExerciseName = exerciseName
        return priorCountToReturn
    }
}
