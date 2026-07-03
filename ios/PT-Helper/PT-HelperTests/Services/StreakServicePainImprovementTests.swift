import XCTest
@testable import PT_Helper

/// Guards audit #37: the "pain_improved" achievement was in the catalog but had no
/// evaluation case, so it could never be earned. `evaluatePainImprovement` now
/// awards it when the trailing 7-day average post-workout pain is meaningfully
/// lower than the prior 7 days.
@MainActor
final class StreakServicePainImprovementTests: XCTestCase {

    private func painImprovedEarned(_ service: StreakService) -> Bool {
        service.achievements.first { $0.id == "pain_improved" }?.isEarned ?? false
    }

    func testAwardsWhenRecentPainLower() {
        let service = StreakService(skipFirebaseLoad: true)
        let prior = [8, 10, 12].map { TestFixtures.makeSession(daysAgo: $0, painLevel: 7) }
        let recent = [1, 3, 5].map { TestFixtures.makeSession(daysAgo: $0, painLevel: 3) }
        service.evaluatePainImprovement(sessions: prior + recent)
        XCTAssertTrue(painImprovedEarned(service))
    }

    func testNoAwardWhenPainSteady() {
        let service = StreakService(skipFirebaseLoad: true)
        let prior = [8, 10].map { TestFixtures.makeSession(daysAgo: $0, painLevel: 5) }
        let recent = [1, 3].map { TestFixtures.makeSession(daysAgo: $0, painLevel: 5) }
        service.evaluatePainImprovement(sessions: prior + recent)
        XCTAssertFalse(painImprovedEarned(service))
    }

    func testNoAwardWithoutEnoughData() {
        let service = StreakService(skipFirebaseLoad: true)
        let sessions = [TestFixtures.makeSession(daysAgo: 1, painLevel: 2)]
        service.evaluatePainImprovement(sessions: sessions)
        XCTAssertFalse(painImprovedEarned(service))
    }
}
