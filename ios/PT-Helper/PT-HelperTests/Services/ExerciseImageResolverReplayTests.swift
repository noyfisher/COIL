import XCTest
@testable import PT_Helper

/// Replays a corpus of historical AI-generated exercise names against the
/// resolver and asserts ≥97% non-nil hit rate. Built from:
/// - All 151 known alias keys from the legacy Swift `aliasMap` (these ARE real
///   historical AI-generated names that were observed in production and corrected)
/// - ~20 hand-curated exotic names exercising different fuzzy layers (plural toggle,
///   synonym expansion, stripped qualifiers) plus a few intentionally novel names
///   that exist as the 3% headroom (e.g. "Underwater Basket Weaving Stretch").
///
/// Once telemetry from the in-app debug surface (PR 2.3) provides a real production
/// corpus, replace `historical_ai_exercise_names.json` with the top-N by count from
/// `missingExerciseImages` Firestore collection.
final class ExerciseImageResolverReplayTests: XCTestCase {

    private static let hitRateThreshold: Double = 0.97

    private func makeExercise(name: String) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: name, targetArea: "Test",
            description: "Test", sets: 3, reps: "10", restSeconds: 30,
            difficulty: .beginner, demonstrationIcon: "figure.flexibility",
            tips: [], contraindications: []
        )
    }

    private func loadCorpus() throws -> [String] {
        let bundle = Bundle(for: type(of: self))
        let url = try XCTUnwrap(
            bundle.url(forResource: "historical_ai_exercise_names", withExtension: "json"),
            "Fixture not bundled — confirm Fixtures dir is in test target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    @MainActor
    func testReplayHitRateMeetsThreshold() throws {
        let service = ExerciseImageService.shared
        let names = try loadCorpus()
        XCTAssertGreaterThan(names.count, 50, "Corpus suspiciously small")

        var hits = 0
        var misses: [String] = []
        for name in names {
            if service.imageKey(for: makeExercise(name: name)) != nil {
                hits += 1
            } else {
                misses.append(name)
            }
        }
        let rate = Double(hits) / Double(names.count)

        // Surface the actual rate so trends are visible in test logs even on pass.
        print("Resolver replay: \(hits)/\(names.count) (\(String(format: "%.2f%%", rate * 100)))")
        if !misses.isEmpty {
            print("Misses (\(misses.count)):")
            for m in misses.prefix(20) { print("  - \(m)") }
        }

        XCTAssertGreaterThanOrEqual(
            rate, Self.hitRateThreshold,
            "Hit rate \(rate) below \(Self.hitRateThreshold) — \(misses.count) misses"
        )
    }
}
