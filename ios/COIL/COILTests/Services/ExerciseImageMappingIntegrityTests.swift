import XCTest
@testable import COIL

/// Asserts catalog-level invariants on the bundled `exercise_image_mapping.json`.
/// Catches drift between the Python rebuild script and the iOS bundle, plus
/// schema violations that would silently degrade image resolution at runtime.
///
/// PNGs are NOT bundled with the iOS app (they're served from Firebase Storage),
/// so the file-existence assertion lives in the Python check
/// (`scripts/check_image_mapping_integrity.py`) — this file only validates the
/// shape of the bundled JSON.
final class ExerciseImageMappingIntegrityTests: XCTestCase {

    private struct ImageEntry: Decodable {
        let name: String
        let filename: String
        let category: String
        let target_area: String
        let end_filename: String?
        let body_position: String?
        let aliases: [String]?
    }

    private func loadMapping() throws -> [String: ImageEntry] {
        let bundle = Bundle(for: type(of: self))
        let appBundle = Bundle.main
        let url = bundle.url(forResource: "exercise_image_mapping", withExtension: "json")
            ?? appBundle.url(forResource: "exercise_image_mapping", withExtension: "json")
        let resolved = try XCTUnwrap(url, "exercise_image_mapping.json not bundled")
        let data = try Data(contentsOf: resolved)
        return try JSONDecoder().decode([String: ImageEntry].self, from: data)
    }

    func testMappingDecodesCleanly() throws {
        let mapping = try loadMapping()
        XCTAssertGreaterThan(mapping.count, 100, "Catalog suspiciously small")
    }

    func testEveryEntryHasRequiredFields() throws {
        let mapping = try loadMapping()
        for (key, entry) in mapping {
            XCTAssertFalse(entry.name.isEmpty, "\(key): empty name")
            XCTAssertFalse(entry.filename.isEmpty, "\(key): empty filename")
            XCTAssertFalse(entry.category.isEmpty, "\(key): empty category")
            XCTAssertFalse(entry.target_area.isEmpty, "\(key): empty target_area")
        }
    }

    func testFilenameMatchesKey() throws {
        let mapping = try loadMapping()
        var violations: [String] = []
        for (key, entry) in mapping {
            if entry.filename != "\(key).png" {
                violations.append("\(key) → \(entry.filename)")
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "filename != key.png in \(violations.count) entries: \(violations.prefix(5))"
        )
    }

    func testAliasesAreUniqueAcrossCatalog() throws {
        let mapping = try loadMapping()
        var aliasOwners: [String: [String]] = [:]
        for (canonical, entry) in mapping {
            for alias in entry.aliases ?? [] {
                aliasOwners[alias, default: []].append(canonical)
            }
        }
        let duplicates = aliasOwners.filter { $0.value.count > 1 }
        XCTAssertTrue(
            duplicates.isEmpty,
            "\(duplicates.count) aliases claimed by >1 canonical: \(duplicates.prefix(5))"
        )
    }

    func testBundledAliasesCount() throws {
        let mapping = try loadMapping()
        let totalAliases = mapping.values.compactMap { $0.aliases }.reduce(0) { $0 + $1.count }
        XCTAssertGreaterThan(
            totalAliases, 100,
            "Bundled aliases count suspiciously low — did seed_aliases_from_swift.py run?"
        )
    }

    func testBodyPositionCoverage() throws {
        let mapping = try loadMapping()
        let withBP = mapping.values.filter { $0.body_position != nil }.count
        let coverage = Double(withBP) / Double(mapping.count)
        XCTAssertGreaterThan(
            coverage, 0.95,
            "body_position coverage \(coverage) below 95% — did rebuild_image_mapping.py run after the metadata change?"
        )
    }

    func testNormalizedTargetAreaParsesCompoundStrings() {
        // Round-2 audit caught: the normalizer must split on `,`, `&`, `/` and strip parens.
        XCTAssertEqual(
            ExerciseImageService.normalizedTargetArea("Knee"),
            ["knee"]
        )
        XCTAssertEqual(
            ExerciseImageService.normalizedTargetArea("Rotator Cuff, Scapular Stabilizers & Posterior Shoulder"),
            ["rotator cuff", "scapular stabilizers", "posterior shoulder"]
        )
        XCTAssertEqual(
            ExerciseImageService.normalizedTargetArea("Hip Flexors/Extensors"),
            ["hip flexors", "extensors"]
        )
        XCTAssertEqual(
            ExerciseImageService.normalizedTargetArea("Core (Transverse Abdominis)"),
            ["core", "transverse abdominis"]
        )
    }
}
