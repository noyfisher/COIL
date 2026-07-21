import XCTest
@testable import COIL

// MARK: - BodyRegion Tests

final class BodyRegionTests: XCTestCase {

    func testInitDefaults() {
        let region = BodyRegion(
            name: "Right Knee",
            zoneKey: "right_knee",
            sides: [.front, .back],
            frontPosition: CGPoint(x: 0.6, y: 0.7),
            backPosition: CGPoint(x: 0.4, y: 0.7)
        )
        XCTAssertEqual(region.name, "Right Knee")
        XCTAssertEqual(region.zoneKey, "right_knee")
        XCTAssertFalse(region.isSelected, "Regions should start unselected")
        XCTAssertEqual(region.sides.count, 2)
    }

    func testPositionForSide_Front() {
        let frontPos = CGPoint(x: 0.5, y: 0.3)
        let region = BodyRegion(
            name: "Chest", zoneKey: "chest",
            sides: [.front],
            frontPosition: frontPos, backPosition: nil
        )
        XCTAssertEqual(region.position(for: .front), frontPos)
        XCTAssertNil(region.position(for: .back))
    }

    func testPositionForSide_Back() {
        let backPos = CGPoint(x: 0.5, y: 0.4)
        let region = BodyRegion(
            name: "Upper Back", zoneKey: "upper_back",
            sides: [.back],
            frontPosition: nil, backPosition: backPos
        )
        XCTAssertNil(region.position(for: .front))
        XCTAssertEqual(region.position(for: .back), backPos)
    }

    func testPositionForSide_BothSides() {
        let front = CGPoint(x: 0.6, y: 0.7)
        let back = CGPoint(x: 0.4, y: 0.7)
        let region = BodyRegion(
            name: "Right Knee", zoneKey: "right_knee",
            sides: [.front, .back],
            frontPosition: front, backPosition: back
        )
        XCTAssertEqual(region.position(for: .front), front)
        XCTAssertEqual(region.position(for: .back), back)
    }

    func testIsSelectedToggleable() {
        var region = BodyRegion(
            name: "Test", zoneKey: "test",
            sides: [.front], frontPosition: nil, backPosition: nil
        )
        XCTAssertFalse(region.isSelected)
        region.isSelected = true
        XCTAssertTrue(region.isSelected)
        region.isSelected = false
        XCTAssertFalse(region.isSelected)
    }

    func testUniqueIds() {
        let r1 = BodyRegion(name: "A", zoneKey: "a", sides: [.front], frontPosition: nil, backPosition: nil)
        let r2 = BodyRegion(name: "A", zoneKey: "a", sides: [.front], frontPosition: nil, backPosition: nil)
        XCTAssertNotEqual(r1.id, r2.id, "Each region should get a unique UUID")
    }
}
