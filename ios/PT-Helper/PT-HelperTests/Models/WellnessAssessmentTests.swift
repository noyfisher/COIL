import XCTest
@testable import PT_Helper

final class WellnessAssessmentTests: XCTestCase {

    // MARK: - GoalCategory

    func testGoalCategory_allCases_haveNonEmptyDisplayName() {
        for category in GoalCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty, "\(category.rawValue) should have a non-empty displayName")
        }
    }

    func testGoalCategory_allCases_haveNonEmptyIcon() {
        for category in GoalCategory.allCases {
            XCTAssertFalse(category.icon.isEmpty, "\(category.rawValue) should have a non-empty icon")
        }
    }

    func testGoalCategory_rawValues_areSnakeCase() {
        for category in GoalCategory.allCases {
            // rawValues should not contain uppercase letters (snake_case convention)
            XCTAssertEqual(category.rawValue, category.rawValue.lowercased(),
                           "\(category.rawValue) should be snake_case")
        }
    }

    func testGoalCategory_codable_roundTrip() throws {
        for category in GoalCategory.allCases {
            let data = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(GoalCategory.self, from: data)
            XCTAssertEqual(decoded, category)
        }
    }

    // MARK: - Nested Enum DisplayNames

    func testImpactLevel_allCases_haveNonEmptyDisplayName() {
        for level in WellnessAssessment.ImpactLevel.allCases {
            XCTAssertFalse(level.displayName.isEmpty, "\(level.rawValue) should have a non-empty displayName")
        }
    }

    func testDuration_allCases_haveNonEmptyDisplayName() {
        for duration in WellnessAssessment.Duration.allCases {
            XCTAssertFalse(duration.displayName.isEmpty, "\(duration.rawValue) should have a non-empty displayName")
        }
    }

    func testTimeOfDay_allCases_haveNonEmptyDisplayName() {
        for time in WellnessAssessment.TimeOfDay.allCases {
            XCTAssertFalse(time.displayName.isEmpty, "\(time.rawValue) should have a non-empty displayName")
        }
    }

    func testPriorAttempt_allCases_haveNonEmptyDisplayName() {
        for attempt in WellnessAssessment.PriorAttempt.allCases {
            XCTAssertFalse(attempt.displayName.isEmpty, "\(attempt.rawValue) should have a non-empty displayName")
        }
    }

    func testCommitmentLevel_allCases_haveNonEmptyDisplayName() {
        for level in WellnessAssessment.CommitmentLevel.allCases {
            XCTAssertFalse(level.displayName.isEmpty, "\(level.rawValue) should have a non-empty displayName")
        }
    }

    // MARK: - WellnessAssessment Codable

    func testWellnessAssessment_codable_roundTrip() throws {
        let assessment = WellnessAssessment(
            id: UUID(),
            goalCategory: .improvePosture,
            customGoalText: nil,
            impactLevel: .moderate,
            motivationLevel: 7,
            duration: .fewMonths,
            timeOfDay: [.morning, .evening],
            dailyActivitiesAffected: ["Sitting at desk"],
            currentHabits: ["Walking"],
            priorAttempts: [.stretching, .exercise],
            commitmentLevel: .fifteenMin,
            specificContext: "Office work",
            additionalNotes: nil
        )

        let data = try JSONEncoder().encode(assessment)
        let decoded = try JSONDecoder().decode(WellnessAssessment.self, from: data)

        XCTAssertEqual(decoded.id, assessment.id)
        XCTAssertEqual(decoded.goalCategory, .improvePosture)
        XCTAssertEqual(decoded.impactLevel, .moderate)
        XCTAssertEqual(decoded.motivationLevel, 7)
        XCTAssertEqual(decoded.duration, .fewMonths)
        XCTAssertEqual(decoded.timeOfDay, [.morning, .evening])
        XCTAssertEqual(decoded.commitmentLevel, .fifteenMin)
        XCTAssertEqual(decoded.specificContext, "Office work")
    }
}
