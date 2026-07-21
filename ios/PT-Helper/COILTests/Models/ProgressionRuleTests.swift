import XCTest
@testable import COIL

final class ProgressionRuleTests: XCTestCase {

    // MARK: - adjustedSets

    func testAdjustedSets_shortPlan_returnsBase() {
        // totalWeeks <= 2 hits the guard
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 1, totalWeeks: 2), 3)
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 2, totalWeeks: 2), 3)
    }

    func testAdjustedSets_adaptationPhase_returnsBase() {
        // progress < 0.3 → base
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 1, totalWeeks: 10), 3)
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 2, totalWeeks: 10), 3)
    }

    func testAdjustedSets_buildingPhase_returnsBasePlusOne() {
        // progress 0.3..<0.6 → base + 1
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 4, totalWeeks: 10), 4)
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 5, totalWeeks: 10), 4)
    }

    func testAdjustedSets_peakPhase_returnsBasePlusOne() {
        // progress 0.6..<0.9 → base + 1
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 7, totalWeeks: 10), 4)
    }

    func testAdjustedSets_taperPhase_returnsBase() {
        // progress >= 0.9 → base
        XCTAssertEqual(ProgressionRule.adjustedSets(base: 3, week: 10, totalWeeks: 10), 3)
    }

    // MARK: - adjustedReps (simple number)

    func testAdjustedReps_simpleNumber_adaptation_unchanged() {
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10", week: 1, totalWeeks: 10), "10")
    }

    func testAdjustedReps_simpleNumber_building_plusTwo() {
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10", week: 4, totalWeeks: 10), "12")
    }

    func testAdjustedReps_simpleNumber_peak_plusThree() {
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10", week: 7, totalWeeks: 10), "13")
    }

    func testAdjustedReps_simpleNumber_taper_returnsBase() {
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10", week: 10, totalWeeks: 10), "10")
    }

    // MARK: - adjustedReps (range and unparseable)

    func testAdjustedReps_rangeFormat_building_bothEndpointsIncremented() {
        // "10-12" at building phase → "12-14"
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10-12", week: 4, totalWeeks: 10), "12-14")
    }

    func testAdjustedReps_unparseableString_returnedAsIs() {
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "30 sec hold", week: 5, totalWeeks: 10), "30 sec hold")
    }

    func testAdjustedReps_shortPlan_returnsBase() {
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10", week: 1, totalWeeks: 2), "10")
        XCTAssertEqual(ProgressionRule.adjustedReps(base: "10-12", week: 1, totalWeeks: 2), "10-12")
    }

    // MARK: - adjustedDifficulty

    func testAdjustedDifficulty_shortPlan_returnsBase() {
        // totalWeeks <= 4 hits the guard
        XCTAssertEqual(ProgressionRule.adjustedDifficulty(base: .beginner, week: 3, totalWeeks: 4), .beginner)
    }

    func testAdjustedDifficulty_beginner_pastSixtyPercent_returnsIntermediate() {
        // progress >= 0.6, beginner → intermediate
        XCTAssertEqual(ProgressionRule.adjustedDifficulty(base: .beginner, week: 7, totalWeeks: 10), .intermediate)
    }

    func testAdjustedDifficulty_intermediate_pastSeventyFivePercent_returnsAdvanced() {
        // progress >= 0.75, intermediate → advanced
        XCTAssertEqual(ProgressionRule.adjustedDifficulty(base: .intermediate, week: 8, totalWeeks: 10), .advanced)
    }

    // MARK: - progressionNote

    func testProgressionNote_allPhases_returnCorrectStrings() {
        // Short plan → nil
        XCTAssertNil(ProgressionRule.progressionNote(week: 1, totalWeeks: 2))

        // Adaptation (< 0.3)
        XCTAssertEqual(ProgressionRule.progressionNote(week: 1, totalWeeks: 10), "Adaptation phase — focus on form")

        // Building (0.3..<0.6)
        XCTAssertEqual(ProgressionRule.progressionNote(week: 4, totalWeeks: 10), "Building phase — volume increasing")

        // Peak (0.6..<0.9)
        XCTAssertEqual(ProgressionRule.progressionNote(week: 7, totalWeeks: 10), "Peak phase — maintain intensity")

        // Taper (>= 0.9)
        XCTAssertEqual(ProgressionRule.progressionNote(week: 10, totalWeeks: 10), "Taper phase — preparing for re-assessment")
    }
}
