import XCTest
@testable import COIL

final class PreventionWeeklyReviewEngineTests: XCTestCase {

    private let referenceDate = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 5))! // a Thursday

    func testBuildReview_noActivity_zeroSessionsAndEncouragingInsight() {
        let review = PreventionWeeklyReviewEngine.buildReview(completions: [], feedback: [], referenceDate: referenceDate)

        XCTAssertEqual(review.sessionCount, 0)
        XCTAssertTrue(review.completionsByCategory.isEmpty)
        XCTAssertFalse(review.positiveInsight.isEmpty)
        XCTAssertFalse(review.positiveInsight.lowercased().contains("risk"))
    }

    func testBuildReview_countsCompletionsByCategory() {
        let completions = [
            TestFixtures.makeCompletion(categories: [.mobilityControl], completedDate: referenceDate),
            TestFixtures.makeCompletion(categories: [.mobilityControl, .recoveryHabits], completedDate: referenceDate.addingTimeInterval(-3600)),
            TestFixtures.makeCompletion(categories: [.strengthCapacity], completedDate: referenceDate.addingTimeInterval(-7200))
        ]

        let review = PreventionWeeklyReviewEngine.buildReview(completions: completions, feedback: [], referenceDate: referenceDate)

        XCTAssertEqual(review.sessionCount, 3)
        XCTAssertEqual(review.completionsByCategory[.mobilityControl], 2)
        XCTAssertEqual(review.completionsByCategory[.recoveryHabits], 1)
        XCTAssertEqual(review.completionsByCategory[.strengthCapacity], 1)
    }

    func testBuildReview_excludesCompletionsOutsideTheWeek() {
        let farOutside = Calendar.current.date(byAdding: .day, value: -30, to: referenceDate)!
        let completions = [TestFixtures.makeCompletion(completedDate: farOutside)]

        let review = PreventionWeeklyReviewEngine.buildReview(completions: completions, feedback: [], referenceDate: referenceDate)

        XCTAssertEqual(review.sessionCount, 0)
    }

    func testBuildReview_topCategoryDrivesPositiveInsight() {
        let completions = [
            TestFixtures.makeCompletion(categories: [.mobilityControl], completedDate: referenceDate),
            TestFixtures.makeCompletion(categories: [.mobilityControl], completedDate: referenceDate),
            TestFixtures.makeCompletion(categories: [.balance], completedDate: referenceDate)
        ]

        let review = PreventionWeeklyReviewEngine.buildReview(completions: completions, feedback: [], referenceDate: referenceDate)

        XCTAssertTrue(review.positiveInsight.contains("2"))
        XCTAssertTrue(review.positiveInsight.lowercased().contains("mobility"))
    }

    func testBuildReview_multipleToughFeedback_suggestsShorterOptionsNextWeek() {
        let feedback = [
            TestFixtures.makeFeedback(difficulty: .tooMuch, submittedDate: referenceDate),
            TestFixtures.makeFeedback(difficulty: .tooMuch, submittedDate: referenceDate.addingTimeInterval(-3600))
        ]

        let review = PreventionWeeklyReviewEngine.buildReview(completions: [], feedback: feedback, referenceDate: referenceDate)

        XCTAssertTrue(review.nextWeekAdjustment.lowercased().contains("shorter"))
    }

    func testBuildReview_mostCommonContext_surfacedInAdjustment() {
        let completions = [
            TestFixtures.makeCompletion(context: .deskHeavy, completedDate: referenceDate),
            TestFixtures.makeCompletion(context: .deskHeavy, completedDate: referenceDate),
            TestFixtures.makeCompletion(context: .activeDay, completedDate: referenceDate)
        ]

        let review = PreventionWeeklyReviewEngine.buildReview(completions: completions, feedback: [], referenceDate: referenceDate)

        XCTAssertEqual(review.mostCommonContext, .deskHeavy)
        XCTAssertTrue(review.nextWeekAdjustment.lowercased().contains("desk"))
    }

    /// No medical claims, risk scores, or predictive/diagnostic language —
    /// a hard product constraint on the weekly review.
    func testBuildReview_neverUsesRiskOrDiagnosticLanguage() {
        let completions = [TestFixtures.makeCompletion(categories: [.balance], completedDate: referenceDate)]
        let feedback = [TestFixtures.makeFeedback(difficulty: .tooMuch, pain: .concerning, submittedDate: referenceDate)]

        let review = PreventionWeeklyReviewEngine.buildReview(completions: completions, feedback: feedback, referenceDate: referenceDate)

        let bannedTerms = ["risk score", "diagnos", "predict", "likely to injure"]
        for text in [review.positiveInsight, review.nextWeekAdjustment] {
            for term in bannedTerms {
                XCTAssertFalse(text.lowercased().contains(term), "'\(text)' should not contain '\(term)'")
            }
        }
    }
}
