import XCTest
@testable import COIL

final class AgePolicyTests: XCTestCase {

    /// Fixed reference "today" so the boundary cases are deterministic regardless
    /// of when the suite runs.
    private let referenceDate = Date()

    private func dob(yearsAgo years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: -years, to: referenceDate)!
    }

    func testAge_ThirteenthBirthdayToday_Is13() {
        // Born exactly 13 years ago today → age is 13 on the boundary.
        let dob = self.dob(yearsAgo: 13)
        XCTAssertEqual(AgePolicy.age(from: dob, on: referenceDate), 13)
    }

    func testIsBlocked_TwelveYearsOld_True() {
        let dob = self.dob(yearsAgo: 12)
        XCTAssertTrue(AgePolicy.isBlocked(dateOfBirth: dob, on: referenceDate))
    }

    func testIsMinor_SeventeenYearsOld_True() {
        let dob = self.dob(yearsAgo: 17)
        XCTAssertTrue(AgePolicy.isMinor(dateOfBirth: dob, on: referenceDate))
    }

    func testIsMinor_EighteenYearsOld_False() {
        let dob = self.dob(yearsAgo: 18)
        XCTAssertFalse(AgePolicy.isMinor(dateOfBirth: dob, on: referenceDate))
    }
}
