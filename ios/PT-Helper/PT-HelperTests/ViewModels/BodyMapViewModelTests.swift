import XCTest
@testable import PT_Helper

// MARK: - BodyMapViewModel Tests (non-Firebase parts)

@MainActor
final class BodyMapViewModelTests: XCTestCase {

    // Note: BodyMapViewModel calls Firebase in init(), so we test
    // properties/methods on a fresh instance where Firebase is not authenticated.

    func testInitialSideIsFront() {
        let vm = BodyMapViewModel()
        XCTAssertEqual(vm.currentSide, .front)
    }

    func testRegionsAreLoaded() {
        let vm = BodyMapViewModel()
        XCTAssertFalse(vm.regions.isEmpty, "Regions should be loaded on init")
        // We know the body map has 30 regions from the source (6 center + 12 bilateral × 2)
        XCTAssertEqual(vm.regions.count, 30, "Should have 30 body regions")
    }

    func testAllRegionsStartUnselected() {
        let vm = BodyMapViewModel()
        XCTAssertTrue(vm.regions.allSatisfy { !$0.isSelected }, "All regions should start unselected")
    }

    func testSelectedRegionsInitiallyEmpty() {
        let vm = BodyMapViewModel()
        XCTAssertTrue(vm.selectedRegions.isEmpty, "No regions should be selected initially")
    }

    func testToggleSelection() {
        let vm = BodyMapViewModel()
        let firstRegion = vm.regions[0]
        XCTAssertFalse(firstRegion.isSelected)

        vm.toggleSelection(for: firstRegion)
        XCTAssertTrue(vm.regions[0].isSelected)
        XCTAssertEqual(vm.selectedRegions.count, 1)

        // Toggle back off
        vm.toggleSelection(for: vm.regions[0])
        XCTAssertFalse(vm.regions[0].isSelected)
        XCTAssertTrue(vm.selectedRegions.isEmpty)
    }

    func testToggleMultipleRegions() {
        let vm = BodyMapViewModel()

        // Select first 3 regions
        for i in 0..<3 {
            vm.toggleSelection(for: vm.regions[i])
        }
        XCTAssertEqual(vm.selectedRegions.count, 3)
    }

    func testClearAll() {
        let vm = BodyMapViewModel()

        // Select several regions
        for i in 0..<5 {
            vm.toggleSelection(for: vm.regions[i])
        }
        XCTAssertEqual(vm.selectedRegions.count, 5)

        vm.clearAll()
        XCTAssertTrue(vm.selectedRegions.isEmpty, "All selections should be cleared")
        XCTAssertTrue(vm.regions.allSatisfy { !$0.isSelected })
    }

    func testRegionsForCurrentSide_Front() {
        let vm = BodyMapViewModel()
        vm.currentSide = .front

        let frontRegions = vm.regionsForCurrentSide
        XCTAssertFalse(frontRegions.isEmpty)

        // All returned regions should include .front in their sides
        for region in frontRegions {
            XCTAssertTrue(region.sides.contains(.front), "\(region.name) should be on the front side")
        }
    }

    func testRegionsForCurrentSide_Back() {
        let vm = BodyMapViewModel()
        vm.currentSide = .back

        let backRegions = vm.regionsForCurrentSide
        XCTAssertFalse(backRegions.isEmpty)

        // All returned regions should include .back in their sides
        for region in backRegions {
            XCTAssertTrue(region.sides.contains(.back), "\(region.name) should be on the back side")
        }
    }

    func testFrontOnlyRegionsNotOnBack() {
        let vm = BodyMapViewModel()

        // "Chest" and "Abdomen" should be front-only
        let chest = vm.regions.first(where: { $0.name == "Chest" })
        XCTAssertNotNil(chest)
        XCTAssertTrue(chest!.sides.contains(.front))
        XCTAssertFalse(chest!.sides.contains(.back))

        let abdomen = vm.regions.first(where: { $0.name == "Abdomen" })
        XCTAssertNotNil(abdomen)
        XCTAssertTrue(abdomen!.sides.contains(.front))
        XCTAssertFalse(abdomen!.sides.contains(.back))
    }

    func testBackOnlyRegionsNotOnFront() {
        let vm = BodyMapViewModel()

        let upperBack = vm.regions.first(where: { $0.name == "Upper Back" })
        XCTAssertNotNil(upperBack)
        XCTAssertFalse(upperBack!.sides.contains(.front))
        XCTAssertTrue(upperBack!.sides.contains(.back))

        let lowerBack = vm.regions.first(where: { $0.name == "Lower Back" })
        XCTAssertNotNil(lowerBack)
        XCTAssertFalse(lowerBack!.sides.contains(.front))
        XCTAssertTrue(lowerBack!.sides.contains(.back))
    }

    func testBothSideRegions() {
        let vm = BodyMapViewModel()

        // Knees, shoulders, etc. should appear on both sides
        let rightKnee = vm.regions.first(where: { $0.name == "Right Knee" })
        XCTAssertNotNil(rightKnee)
        XCTAssertTrue(rightKnee!.sides.contains(.front))
        XCTAssertTrue(rightKnee!.sides.contains(.back))
    }

    func testRegionNamesAreUnique() {
        let vm = BodyMapViewModel()
        let names = vm.regions.map { $0.name }
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "All region names should be unique")
    }

    func testRegionZoneKeysAreUnique() {
        let vm = BodyMapViewModel()
        let keys = vm.regions.map { $0.zoneKey }
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "All zone keys should be unique")
    }
}
