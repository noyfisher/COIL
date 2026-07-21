import XCTest
@testable import COIL

// MARK: - PainAssessment Enum Tests

final class PainAssessmentEnumTests: XCTestCase {

    func testPainTypeCount() {
        XCTAssertEqual(PainAssessment.PainType.allCases.count, 8)
    }

    func testPainTypeDisplayNames() {
        XCTAssertEqual(PainAssessment.PainType.sharp.displayName, "Sharp")
        XCTAssertEqual(PainAssessment.PainType.dull.displayName, "Dull")
        XCTAssertEqual(PainAssessment.PainType.burning.displayName, "Burning")
        XCTAssertEqual(PainAssessment.PainType.throbbing.displayName, "Throbbing")
        XCTAssertEqual(PainAssessment.PainType.aching.displayName, "Aching")
        XCTAssertEqual(PainAssessment.PainType.stabbing.displayName, "Stabbing")
        XCTAssertEqual(PainAssessment.PainType.tingling.displayName, "Tingling")
        XCTAssertEqual(PainAssessment.PainType.tightness.displayName, "Tightness")
    }

    func testPainDurationCount() {
        XCTAssertEqual(PainAssessment.PainDuration.allCases.count, 6)
    }

    func testPainFrequencyCount() {
        XCTAssertEqual(PainAssessment.PainFrequency.allCases.count, 5)
    }

    func testPainOnsetCount() {
        XCTAssertEqual(PainAssessment.PainOnset.allCases.count, 5)
    }

    func testAllEnumsHaveNonEmptyDisplayNames() {
        for painType in PainAssessment.PainType.allCases {
            XCTAssertFalse(painType.displayName.isEmpty, "\(painType) has empty display name")
        }
        for duration in PainAssessment.PainDuration.allCases {
            XCTAssertFalse(duration.displayName.isEmpty, "\(duration) has empty display name")
        }
        for frequency in PainAssessment.PainFrequency.allCases {
            XCTAssertFalse(frequency.displayName.isEmpty, "\(frequency) has empty display name")
        }
        for onset in PainAssessment.PainOnset.allCases {
            XCTAssertFalse(onset.displayName.isEmpty, "\(onset) has empty display name")
        }
    }
}
