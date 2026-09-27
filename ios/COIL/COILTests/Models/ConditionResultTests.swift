import XCTest
@testable import COIL

// MARK: - ConditionResult Tests

final class ConditionResultTests: XCTestCase {

    func testRedFlagCondition() {
        let condition = ConditionResult(
            id: UUID(),
            conditionName: "Cauda Equina Syndrome",
            commonName: "Spinal Nerve Emergency",
            confidence: 30,
            explanation: "Urgent condition",
            whatItMeans: "Nerves at the base of your spine are being compressed",
            howToManage: "Go to the emergency room right away",
            isRedFlag: true,
            redFlagMessage: "Seek emergency care immediately",
            nextSteps: ["Go to ER"]
        )
        XCTAssertTrue(condition.isRedFlag)
        XCTAssertNotNil(condition.redFlagMessage)
        XCTAssertEqual(condition.commonName, "Spinal Nerve Emergency")
    }

    func testNonRedFlagCondition() {
        let condition = ConditionResult(
            id: UUID(),
            conditionName: "Muscle Strain",
            commonName: "Pulled Muscle",
            confidence: 80,
            explanation: "Common overuse injury",
            whatItMeans: "Some muscle fibers got stretched too far or torn slightly",
            howToManage: "Rest the area and apply ice for 15 minutes a few times a day",
            isRedFlag: false,
            redFlagMessage: nil,
            nextSteps: ["Rest", "Ice", "Stretch"]
        )
        XCTAssertFalse(condition.isRedFlag)
        XCTAssertNil(condition.redFlagMessage)
        XCTAssertEqual(condition.nextSteps.count, 3)
        XCTAssertEqual(condition.commonName, "Pulled Muscle")
        XCTAssertFalse(condition.whatItMeans.isEmpty)
        XCTAssertFalse(condition.howToManage.isEmpty)
    }
}
