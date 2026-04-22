import XCTest
@testable import PT_Helper

@MainActor
final class BodyZoneTests: XCTestCase {

    /// Every one of the 30 region zoneKeys must map to exactly one zone.
    func testAllRegionKeysMappedToExactlyOneZone() {
        let viewModel = BodyMapViewModel()
        let allKeys = viewModel.regions.map(\.zoneKey)

        for key in allKeys {
            let matchingZones = BodyZone.allCases.filter { $0.regionZoneKeys.contains(key) }
            XCTAssertEqual(matchingZones.count, 1,
                           "zoneKey '\(key)' should map to exactly 1 zone, found \(matchingZones.count)")
        }
    }

    /// Reverse lookup returns the correct zone for every region key.
    func testZoneLookupForAllRegionKeys() {
        let viewModel = BodyMapViewModel()

        for region in viewModel.regions {
            let zone = BodyZone.zone(for: region.zoneKey)
            XCTAssertNotNil(zone, "BodyZone.zone(for: \"\(region.zoneKey)\") should not be nil")
            XCTAssertTrue(zone!.regionZoneKeys.contains(region.zoneKey))
        }
    }

    /// Each zone contains the expected number of regions.
    func testZoneRegionCounts() {
        XCTAssertEqual(BodyZone.headNeck.regionZoneKeys.count, 2)
        XCTAssertEqual(BodyZone.torso.regionZoneKeys.count, 4)
        XCTAssertEqual(BodyZone.leftArm.regionZoneKeys.count, 5)
        XCTAssertEqual(BodyZone.rightArm.regionZoneKeys.count, 5)
        XCTAssertEqual(BodyZone.leftLeg.regionZoneKeys.count, 7)
        XCTAssertEqual(BodyZone.rightLeg.regionZoneKeys.count, 7)
    }

    /// Total region count across all zones should be 30.
    func testTotalRegionCountIs30() {
        let total = BodyZone.allCases.reduce(0) { $0 + $1.regionZoneKeys.count }
        XCTAssertEqual(total, 30)
    }

    /// No region key appears in more than one zone.
    func testNoOverlappingRegionKeys() {
        var seen = Set<String>()
        for zone in BodyZone.allCases {
            for key in zone.regionZoneKeys {
                XCTAssertFalse(seen.contains(key), "Duplicate key '\(key)' found in zone \(zone.rawValue)")
                seen.insert(key)
            }
        }
    }

    /// Unknown keys return nil from zone lookup.
    func testZoneLookupForUnknownKey() {
        XCTAssertNil(BodyZone.zone(for: "nonexistent"))
        XCTAssertNil(BodyZone.zone(for: ""))
    }

    /// Every zone has a non-empty display name.
    func testDisplayName_allZones_nonEmpty() {
        for zone in BodyZone.allCases {
            XCTAssertFalse(zone.displayName.isEmpty, "\(zone.rawValue) should have a non-empty displayName")
        }
    }

    /// Every zone has a non-empty icon name.
    func testIconName_allZones_nonEmpty() {
        for zone in BodyZone.allCases {
            XCTAssertFalse(zone.iconName.isEmpty, "\(zone.rawValue) should have a non-empty iconName")
        }
    }

    /// Camera targets exist for every zone.
    func testCameraTargetExistsForEveryZone() {
        for zone in BodyZone.allCases {
            let target = BodyMapConstants.zoneCameraTargets[zone.rawValue]
            XCTAssertNotNil(target, "Missing camera target for zone \(zone.rawValue)")
        }
    }
}
