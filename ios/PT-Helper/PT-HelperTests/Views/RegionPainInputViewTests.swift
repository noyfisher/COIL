import XCTest
@testable import PT_Helper

/// Guards audit #19: the post-workout region-pain list must stay in lockstep with
/// the 3D body map's canonical `BodyZone` region keys, so pain logged after a
/// workout files under the same keys the body map / analysis use (no chart gaps).
final class RegionPainInputViewTests: XCTestCase {

    func testAllRegions_matchesCanonicalBodyZoneKeys() {
        let regions = RegionPainInputView.allRegions
        let canonical = BodyZone.allCases.flatMap { $0.regionZoneKeys }
        XCTAssertEqual(Set(regions), Set(canonical),
                       "Region pain keys must be sourced from BodyZone to avoid drift")
    }

    func testAllRegions_usesCorrectedKeys_notDriftedOnes() {
        let regions = Set(RegionPainInputView.allRegions)

        // Corrected canonical keys that the map actually uses.
        for key in ["abdomen", "left_thigh", "right_thigh", "left_calf_shin",
                    "left_glute", "right_glute", "left_hamstring", "right_hamstring"] {
            XCTAssertTrue(regions.contains(key), "Missing canonical key \(key)")
        }

        // Old drifted keys that broke chart alignment must be gone.
        for stale in ["core", "left_upper_thigh", "right_upper_thigh",
                      "left_lower_leg", "right_lower_leg"] {
            XCTAssertFalse(regions.contains(stale), "Stale drifted key \(stale) still present")
        }
    }
}
