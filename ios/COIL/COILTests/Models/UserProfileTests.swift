import XCTest
@testable import COIL

// MARK: - UserProfile Tests

final class UserProfileTests: XCTestCase {

    // MARK: - Construction

    func testDefaultUserProfile() {
        let profile = UserProfile(
            userId: "test-uid",
            firstName: "John",
            lastName: "Doe",
            dateOfBirth: Date(),
            sex: "Male",
            heightFeet: 5,
            heightInches: 10,
            weight: 175.0,
            medicalConditions: [],
            otherMedicalConditions: nil,
            surgeries: [],
            injuries: [],
            activityLevel: "Moderately Active",
            primarySport: nil
        )

        XCTAssertEqual(profile.id, "test-uid")
        XCTAssertEqual(profile.firstName, "John")
        XCTAssertEqual(profile.lastName, "Doe")
        XCTAssertEqual(profile.sex, "Male")
        XCTAssertEqual(profile.heightFeet, 5)
        XCTAssertEqual(profile.heightInches, 10)
        XCTAssertEqual(profile.weight, 175.0)
        XCTAssertTrue(profile.medicalConditions.isEmpty)
        XCTAssertNil(profile.otherMedicalConditions)
        XCTAssertTrue(profile.surgeries.isEmpty)
        XCTAssertTrue(profile.injuries.isEmpty)
        XCTAssertEqual(profile.activityLevel, "Moderately Active")
        XCTAssertNil(profile.primarySport)
    }

    func testIdentifiableUsesUserId() {
        let profile = UserProfile(
            userId: "abc-123",
            firstName: "", lastName: "",
            dateOfBirth: Date(), sex: "",
            heightFeet: 0, heightInches: 0, weight: 0,
            medicalConditions: [], otherMedicalConditions: nil,
            surgeries: [], injuries: [],
            activityLevel: "", primarySport: nil
        )
        XCTAssertEqual(profile.id, "abc-123")
    }

    // MARK: - Age Calculation

    func testAgeCalculation_25YearsOld() {
        let calendar = Calendar.current
        let dob = calendar.date(byAdding: .year, value: -25, to: Date())!
        let profile = makeProfile(dateOfBirth: dob)
        XCTAssertEqual(profile.age, 25)
    }

    func testAgeCalculation_NewbornToday() {
        let profile = makeProfile(dateOfBirth: Date())
        XCTAssertEqual(profile.age, 0)
    }

    func testAgeCalculation_Elderly() {
        let calendar = Calendar.current
        let dob = calendar.date(byAdding: .year, value: -80, to: Date())!
        let profile = makeProfile(dateOfBirth: dob)
        XCTAssertEqual(profile.age, 80)
    }

    // MARK: - Nested Types

    func testSurgeryHasUniqueId() {
        let s1 = UserProfile.Surgery(name: "ACL Repair", year: 2020)
        let s2 = UserProfile.Surgery(name: "ACL Repair", year: 2020)
        XCTAssertNotEqual(s1.id, s2.id)
    }

    func testInjuryHasUniqueId() {
        let i1 = UserProfile.Injury(bodyArea: "Knee", description: "Torn meniscus", isCurrent: true)
        let i2 = UserProfile.Injury(bodyArea: "Knee", description: "Torn meniscus", isCurrent: true)
        XCTAssertNotEqual(i1.id, i2.id)
    }

    // MARK: - Mutability

    func testUserIdIsMutable() {
        var profile = makeProfile()
        profile.userId = "new-uid"
        XCTAssertEqual(profile.userId, "new-uid")
        XCTAssertEqual(profile.id, "new-uid")
    }

    func testMedicalConditionsAreMutable() {
        var profile = makeProfile()
        XCTAssertTrue(profile.medicalConditions.isEmpty)
        profile.medicalConditions = ["Diabetes", "Asthma"]
        XCTAssertEqual(profile.medicalConditions.count, 2)
    }

    // MARK: - Helper

    private func makeProfile(
        userId: String = "test",
        dateOfBirth: Date = Date()
    ) -> UserProfile {
        UserProfile(
            userId: userId,
            firstName: "Test", lastName: "User",
            dateOfBirth: dateOfBirth, sex: "Male",
            heightFeet: 5, heightInches: 10, weight: 175,
            medicalConditions: [], otherMedicalConditions: nil,
            surgeries: [], injuries: [],
            activityLevel: "Active", primarySport: nil
        )
    }
}
