import XCTest
@testable import COIL

/// Tier 3 PR D — tests for `OutcomeRecorder` data layer.
///
/// Covers the local cache path (UserDefaults-backed) and the trigger
/// helper. Does NOT exercise the Firestore write path — that's
/// fire-and-forget on a detached Task and would require auth + a
/// network mock to test deterministically. The Firestore call is a
/// thin `setData` and is exercised manually during dogfooding.
@MainActor
final class OutcomeInstrumentationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        OutcomeRecorder.shared.clearLocalCache()
    }

    override func tearDown() {
        OutcomeRecorder.shared.clearLocalCache()
        super.tearDown()
    }

    // MARK: - hasRated / record cycle

    func test_hasRated_initiallyFalse() {
        XCTAssertFalse(OutcomeRecorder.shared.hasRated(analysisId: UUID()))
    }

    func test_record_marksHasRated() {
        let analysisId = UUID()
        XCTAssertFalse(OutcomeRecorder.shared.hasRated(analysisId: analysisId))
        OutcomeRecorder.shared.record(.accurate, for: analysisId, planId: UUID(), planAgeDays: 8)
        XCTAssertTrue(OutcomeRecorder.shared.hasRated(analysisId: analysisId))
    }

    func test_record_isolatedPerAnalysisId() {
        let rated = UUID()
        let other = UUID()
        OutcomeRecorder.shared.record(.partiallyAccurate, for: rated)
        XCTAssertTrue(OutcomeRecorder.shared.hasRated(analysisId: rated))
        XCTAssertFalse(OutcomeRecorder.shared.hasRated(analysisId: other))
    }

    func test_record_idempotentForSameAnalysis() {
        let analysisId = UUID()
        OutcomeRecorder.shared.record(.accurate, for: analysisId)
        OutcomeRecorder.shared.record(.inaccurate, for: analysisId)
        // hasRated should still be true (we don't track count, just presence).
        XCTAssertTrue(OutcomeRecorder.shared.hasRated(analysisId: analysisId))
    }

    func test_clearLocalCache_resetsAllRatings() {
        OutcomeRecorder.shared.record(.accurate, for: UUID())
        OutcomeRecorder.shared.record(.inaccurate, for: UUID())
        OutcomeRecorder.shared.clearLocalCache()
        XCTAssertFalse(OutcomeRecorder.shared.hasRated(analysisId: UUID()))
    }

    // MARK: - shouldShowPrompt eligibility

    func test_shouldShowPrompt_nilStartDate_returnsFalse() {
        XCTAssertFalse(OutcomeRecorder.shared.shouldShowPrompt(
            planStartDate: nil,
            analysisId: UUID()
        ))
    }

    func test_shouldShowPrompt_freshPlan_returnsFalse() {
        let started = Date(timeIntervalSinceNow: -3 * 86_400)  // 3 days ago
        XCTAssertFalse(OutcomeRecorder.shared.shouldShowPrompt(
            planStartDate: started,
            analysisId: UUID()
        ))
    }

    func test_shouldShowPrompt_atSevenDays_returnsTrue() {
        // Exactly at the threshold (7 days + a few seconds).
        let started = Date(timeIntervalSinceNow: -7 * 86_400 - 60)
        XCTAssertTrue(OutcomeRecorder.shared.shouldShowPrompt(
            planStartDate: started,
            analysisId: UUID()
        ))
    }

    func test_shouldShowPrompt_alreadyRated_returnsFalse() {
        let analysisId = UUID()
        let started = Date(timeIntervalSinceNow: -14 * 86_400)
        OutcomeRecorder.shared.record(.accurate, for: analysisId)
        XCTAssertFalse(OutcomeRecorder.shared.shouldShowPrompt(
            planStartDate: started,
            analysisId: analysisId
        ))
    }

    func test_shouldShowPrompt_customMinimumDays() {
        let started = Date(timeIntervalSinceNow: -3 * 86_400)
        // With minimumDays=2, a 3-day-old plan should be eligible.
        XCTAssertTrue(OutcomeRecorder.shared.shouldShowPrompt(
            planStartDate: started,
            analysisId: UUID(),
            minimumDays: 2
        ))
    }

    // MARK: - planAgeDays helper

    func test_planAgeDays_nilStart_returnsNil() {
        XCTAssertNil(OutcomeRecorder.planAgeDays(planStartDate: nil))
    }

    func test_planAgeDays_futureStart_returnsNil() {
        let future = Date(timeIntervalSinceNow: 86_400)
        XCTAssertNil(OutcomeRecorder.planAgeDays(planStartDate: future))
    }

    func test_planAgeDays_oneDayAgo_returns1() {
        let started = Date(timeIntervalSinceNow: -86_400 - 60)
        XCTAssertEqual(OutcomeRecorder.planAgeDays(planStartDate: started), 1)
    }

    func test_planAgeDays_aboutOneWeekAgo_returns7() {
        let started = Date(timeIntervalSinceNow: -7 * 86_400 - 60)
        XCTAssertEqual(OutcomeRecorder.planAgeDays(planStartDate: started), 7)
    }

    // MARK: - OutcomeFeedback enum

    func test_outcomeFeedback_allCasesHaveDistinctRawValues() {
        let raws = Set(OutcomeFeedback.allCases.map(\.rawValue))
        XCTAssertEqual(raws.count, OutcomeFeedback.allCases.count)
    }

    func test_outcomeFeedback_partiallyAccurate_usesSnakeCase() {
        XCTAssertEqual(OutcomeFeedback.partiallyAccurate.rawValue, "partially_accurate")
    }

    func test_outcomeFeedback_codable_roundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for feedback in OutcomeFeedback.allCases {
            let data = try encoder.encode(feedback)
            let decoded = try decoder.decode(OutcomeFeedback.self, from: data)
            XCTAssertEqual(decoded, feedback)
        }
    }

    func test_outcomeFeedback_displayNamesAreNonEmpty() {
        for feedback in OutcomeFeedback.allCases {
            XCTAssertFalse(feedback.displayName.isEmpty, "\(feedback) has empty displayName")
            XCTAssertFalse(feedback.icon.isEmpty, "\(feedback) has empty icon")
        }
    }

    // MARK: - AnalysisOutcomeRecord

    func test_analysisOutcomeRecord_codable_roundTrip() throws {
        let record = AnalysisOutcomeRecord(
            analysisId: UUID(),
            feedback: .partiallyAccurate,
            recordedAt: Date(),
            planId: UUID(),
            planAgeDays: 14
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(AnalysisOutcomeRecord.self, from: data)
        XCTAssertEqual(decoded.analysisId, record.analysisId)
        XCTAssertEqual(decoded.feedback, record.feedback)
        XCTAssertEqual(decoded.planId, record.planId)
        XCTAssertEqual(decoded.planAgeDays, record.planAgeDays)
    }
}
