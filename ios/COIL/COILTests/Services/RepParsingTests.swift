import XCTest
@testable import COIL

/// Tier 2 tests for `RepSpecParser`. Covers the 9 required cases from the
/// Tier 2 DoD (`"10"`, `"10-15"`, `"30-40"`, `"40-50"`, `"Hold 30s"`, `""`,
/// `"three"`, `"As needed"`, `"Daily"`) plus extra shapes the parser must
/// handle in the wild.
final class RepParsingTests: XCTestCase {

    // MARK: - DoD required cases (9)

    func test_parse_10_returnsReps10() {
        XCTAssertEqual(RepSpecParser.parse("10"), .reps(10))
    }

    func test_parse_range10to15_returnsRange() {
        XCTAssertEqual(RepSpecParser.parse("10-15"), .repsRange(low: 10, high: 15))
    }

    func test_parse_range30to40_returnsRangeWithoutFlag() {
        // DoD: "30-40" must NOT be treated as out-of-range (legitimate low end).
        XCTAssertEqual(RepSpecParser.parse("30-40"), .repsRange(low: 30, high: 40))
    }

    func test_parse_range40to50_returnsRange() {
        // DoD: "40-50" is parsed; the validator decides it's implausible.
        XCTAssertEqual(RepSpecParser.parse("40-50"), .repsRange(low: 40, high: 50))
    }

    func test_parse_hold30s_returnsDuration30() {
        XCTAssertEqual(RepSpecParser.parse("Hold 30s"), .duration(seconds: 30))
    }

    func test_parse_empty_returnsUnknown() {
        XCTAssertEqual(RepSpecParser.parse(""), .unknown)
    }

    func test_parse_three_returnsUnknown() {
        // Spelled-out numbers are intentionally not parsed.
        XCTAssertEqual(RepSpecParser.parse("three"), .unknown)
    }

    func test_parse_asNeeded_returnsUnknown() {
        XCTAssertEqual(RepSpecParser.parse("As needed"), .unknown)
    }

    func test_parse_daily_returnsUnknown() {
        XCTAssertEqual(RepSpecParser.parse("Daily"), .unknown)
    }

    // MARK: - Additional duration shapes

    func test_parse_30seconds_returnsDuration() {
        XCTAssertEqual(RepSpecParser.parse("30 seconds"), .duration(seconds: 30))
    }

    func test_parse_hold3minutes_returnsDurationInSeconds() {
        XCTAssertEqual(RepSpecParser.parse("Hold 3 minutes"), .duration(seconds: 180))
    }

    func test_parse_2min_returnsDurationInSeconds() {
        XCTAssertEqual(RepSpecParser.parse("2 min"), .duration(seconds: 120))
    }

    // MARK: - Additional range shapes

    func test_parse_rangeWithEnDash_returnsRange() {
        XCTAssertEqual(RepSpecParser.parse("10–15"), .repsRange(low: 10, high: 15))
    }

    func test_parse_rangeWithTo_returnsRange() {
        XCTAssertEqual(RepSpecParser.parse("10 to 15"), .repsRange(low: 10, high: 15))
    }

    // MARK: - Edge cases

    func test_parse_whitespaceOnly_returnsUnknown() {
        XCTAssertEqual(RepSpecParser.parse("   "), .unknown)
    }

    func test_parse_onlyNumber_returnsReps() {
        XCTAssertEqual(RepSpecParser.parse("15"), .reps(15))
    }

    func test_parse_asToleratedReturnsUnknown() {
        XCTAssertEqual(RepSpecParser.parse("As tolerated"), .unknown)
    }
}
