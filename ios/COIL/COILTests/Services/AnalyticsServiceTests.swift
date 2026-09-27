import XCTest
@testable import COIL

final class AnalyticsServiceTests: XCTestCase {

    // MARK: - Funnel Event Raw Values

    func testFunnelEvent_RawValues_AreCorrect() {
        XCTAssertEqual(AnalyticsService.FunnelEvent.appOpened.rawValue, "app_opened")
        XCTAssertEqual(AnalyticsService.FunnelEvent.signInCompleted.rawValue, "sign_in_completed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.onboardingStarted.rawValue, "onboarding_started")
        XCTAssertEqual(AnalyticsService.FunnelEvent.onboardingStepCompleted.rawValue, "onboarding_step_completed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.onboardingCompleted.rawValue, "onboarding_completed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.onboardingSkipped.rawValue, "onboarding_skipped")
        XCTAssertEqual(AnalyticsService.FunnelEvent.bodyMapOpened.rawValue, "body_map_opened")
        XCTAssertEqual(AnalyticsService.FunnelEvent.regionsSelected.rawValue, "regions_selected")
        XCTAssertEqual(AnalyticsService.FunnelEvent.assessmentStarted.rawValue, "assessment_started")
        XCTAssertEqual(AnalyticsService.FunnelEvent.assessmentCompleted.rawValue, "assessment_completed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.analysisCompleted.rawValue, "analysis_completed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.analysisFailed.rawValue, "analysis_failed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.rehabPlanGenerated.rawValue, "rehab_plan_generated")
        XCTAssertEqual(AnalyticsService.FunnelEvent.workoutStarted.rawValue, "workout_started")
        XCTAssertEqual(AnalyticsService.FunnelEvent.workoutCompleted.rawValue, "workout_completed")
        XCTAssertEqual(AnalyticsService.FunnelEvent.workoutEndedEarly.rawValue, "workout_ended_early")
    }

    // MARK: - Engagement Event Raw Values

    func testEngagementEvent_RawValues_AreCorrect() {
        XCTAssertEqual(AnalyticsService.EngagementEvent.exerciseSwapped.rawValue, "exercise_swapped")
        XCTAssertEqual(AnalyticsService.EngagementEvent.exerciseSkipped.rawValue, "exercise_skipped")
        XCTAssertEqual(AnalyticsService.EngagementEvent.planViewed.rawValue, "plan_viewed")
        XCTAssertEqual(AnalyticsService.EngagementEvent.recoveryInsightsViewed.rawValue, "recovery_insights_viewed")
        XCTAssertEqual(AnalyticsService.EngagementEvent.achievementEarned.rawValue, "achievement_earned")
        XCTAssertEqual(AnalyticsService.EngagementEvent.reassessmentStarted.rawValue, "reassessment_started")
        XCTAssertEqual(AnalyticsService.EngagementEvent.pdfExported.rawValue, "pdf_exported")
        XCTAssertEqual(AnalyticsService.EngagementEvent.tabSwitched.rawValue, "tab_switched")
        XCTAssertEqual(AnalyticsService.EngagementEvent.workoutResumed.rawValue, "workout_resumed")
    }

    // MARK: - Event Count Completeness

    func testFunnelEvent_HasExpectedCount() {
        // Ensures new events aren't silently added without tests
        let allCases: [AnalyticsService.FunnelEvent] = [
            .appOpened, .signInCompleted, .onboardingStarted, .onboardingStepCompleted,
            .onboardingCompleted, .onboardingSkipped, .bodyMapOpened, .regionsSelected,
            .assessmentStarted, .assessmentCompleted, .analysisCompleted, .analysisFailed,
            .rehabPlanGenerated, .workoutStarted, .workoutCompleted, .workoutEndedEarly
        ]
        XCTAssertEqual(allCases.count, 16, "Funnel events count changed — update tests")
    }

    func testEngagementEvent_HasExpectedCount() {
        let allCases: [AnalyticsService.EngagementEvent] = [
            .exerciseSwapped, .exerciseSkipped, .planViewed, .recoveryInsightsViewed,
            .achievementEarned, .reassessmentStarted, .pdfExported, .tabSwitched, .workoutResumed
        ]
        XCTAssertEqual(allCases.count, 9, "Engagement events count changed — update tests")
    }
}
