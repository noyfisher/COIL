import XCTest
@testable import COIL

@MainActor
final class BodyMapViewModelZoneTests: XCTestCase {

    func testRegionsInZone_returnsCorrectSubset() {
        let vm = BodyMapViewModel()

        let headNeckRegions = vm.regions(in: .headNeck)
        XCTAssertEqual(headNeckRegions.count, 2)
        XCTAssertTrue(headNeckRegions.contains(where: { $0.zoneKey == "head" }))
        XCTAssertTrue(headNeckRegions.contains(where: { $0.zoneKey == "neck" }))
    }

    func testRegionsInZone_legHas7Regions() {
        let vm = BodyMapViewModel()

        let leftLeg = vm.regions(in: .leftLeg)
        XCTAssertEqual(leftLeg.count, 7)
        let expectedKeys = ["left_hip", "left_glute", "left_thigh", "left_hamstring",
                            "left_knee", "left_calf_shin", "left_ankle_foot"]
        for key in expectedKeys {
            XCTAssertTrue(leftLeg.contains(where: { $0.zoneKey == key }),
                          "Left leg should contain \(key)")
        }
    }

    func testSelectedCountInZone_initiallyZero() {
        let vm = BodyMapViewModel()
        XCTAssertEqual(vm.selectedCount(in: .torso), 0)
    }

    func testSelectedCountInZone_countsCorrectly() {
        let vm = BodyMapViewModel()

        // Select a torso region
        if let chestRegion = vm.regions.first(where: { $0.zoneKey == "chest" }) {
            vm.toggleSelection(for: chestRegion)
        }
        XCTAssertEqual(vm.selectedCount(in: .torso), 1)

        // Select another torso region
        if let abdomenRegion = vm.regions.first(where: { $0.zoneKey == "abdomen" }) {
            vm.toggleSelection(for: abdomenRegion)
        }
        XCTAssertEqual(vm.selectedCount(in: .torso), 2)

        // Select a non-torso region — torso count should stay the same
        if let kneeRegion = vm.regions.first(where: { $0.zoneKey == "left_knee" }) {
            vm.toggleSelection(for: kneeRegion)
        }
        XCTAssertEqual(vm.selectedCount(in: .torso), 2)
        XCTAssertEqual(vm.selectedCount(in: .leftLeg), 1)
    }

    func testActiveZone_initiallyNil() {
        let vm = BodyMapViewModel()
        XCTAssertNil(vm.activeZone)
    }
}
