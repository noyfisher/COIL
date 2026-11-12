import XCTest
@testable import COIL

/// Exercises the **real bundled** `medical_knowledge_graph.json` — the file that decides
/// which exercises are contraindicated for which conditions in production.
///
/// Every other knowledge-graph test injects a hand-built fixture via `init(graph:)`.
/// That covers the matching *logic* but never the *data*, and the data is the part
/// edited by hand. The failure mode is silent: `loadGraph` catches its decode error,
/// logs, and leaves `isLoaded = false`, after which `verify` returns `.unverified` for
/// everything — so a corrupt or mis-edited graph disables contraindication checking for
/// every user with no crash and no user-visible signal.
///
/// `COILTests` is a hosted target (`TEST_HOST = COIL.app`), so `Bundle.main` resolves to
/// the real app bundle here and the production `init()` path is directly testable. The
/// "avoid bundle loading issues" note in `KnowledgeGraphServiceTests` is stale.
final class KnowledgeGraphRealDataTests: XCTestCase {

    /// Conditions that legitimately carry no contraindications today. Pinned so that a
    /// *new* condition added without an `unsafeExercises` list fails instead of silently
    /// shipping with contraindication checking disabled for it.
    ///
    /// Verified against the graph on 2026-08-09.
    private static let conditionsWithNoContraindications: Set<String> = [
        "it-band-syndrome",
        "lateral-ankle-sprain",
        "plantar-fasciitis",
        "piriformis-syndrome",
    ]

    private func realGraphData() throws -> Data {
        let url = Bundle(for: type(of: self)).url(forResource: "medical_knowledge_graph", withExtension: "json")
            ?? Bundle.main.url(forResource: "medical_knowledge_graph", withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "medical_knowledge_graph.json is not bundled"))
    }

    private func realGraph() throws -> KnowledgeGraph {
        try JSONDecoder().decode(KnowledgeGraph.self, from: realGraphData())
    }

    // MARK: - Decoding + load path

    func testRealGraph_decodesCleanly() throws {
        let graph = try realGraph()

        XCTAssertFalse(graph.version.isEmpty, "Graph must carry a version")
        XCTAssertGreaterThanOrEqual(graph.conditions.count, 20,
                                    "Condition count collapsed — suspect a botched edit to the graph")
    }

    /// The production initializer, exercised end to end. If the file stops being bundled
    /// (target-membership regression) or stops decoding, `verify` silently degrades to
    /// `.unverified` — this catches that without needing access to the private `isLoaded`.
    func testProductionInit_loadsBundledGraph_andVerifiesAKnownContraindication() {
        let service = KnowledgeGraphService()

        let tier = service.verify(exercise: "Bulgarian Split Squat",
                                  forCondition: "patellofemoral pain syndrome")

        guard case .contraindicated = tier else {
            return XCTFail("""
                Expected a known contraindicated pair to be flagged, got \(tier).
                `.unverified` here means the bundled graph failed to load and every \
                exercise is now silently passing the contraindication check.
                """)
        }
    }

    func testProductionInit_resolvesAKnownConditionByDisplayName() throws {
        let service = KnowledgeGraphService()

        let match = service.lookupCondition("patellofemoral pain syndrome")

        XCTAssertEqual(match?.id, "patellofemoral-pain-syndrome")
    }

    // MARK: - Per-condition data integrity

    func testEveryCondition_hasRequiredFieldsPopulated() throws {
        let graph = try realGraph()

        for (id, condition) in graph.conditions {
            XCTAssertFalse(condition.names.isEmpty, "\(id): needs at least one name to be matchable")
            XCTAssertFalse(condition.icd10.isEmpty, "\(id): missing ICD-10 code")
            XCTAssertFalse(condition.bodyRegions.isEmpty, "\(id): missing bodyRegions")
            XCTAssertFalse(condition.safeExercises.isEmpty,
                           "\(id): no safeExercises — nothing can ever verify as safe for this condition")
        }
    }

    /// A condition with no `unsafeExercises` can never flag anything as contraindicated.
    /// That's legitimate for a few conditions, but it should be a deliberate, reviewed
    /// choice rather than something a new entry falls into by omission.
    func testConditionsWithoutContraindications_matchTheReviewedAllowlist() throws {
        let graph = try realGraph()

        let actual = Set(graph.conditions.filter { $0.value.unsafeExercises.isEmpty }.keys)

        let unexpected = actual.subtracting(Self.conditionsWithNoContraindications).sorted()
        XCTAssertTrue(unexpected.isEmpty, """
            These conditions ship with an empty unsafeExercises list, so contraindication \
            checking is effectively off for them: \(unexpected). Add contraindications, or \
            add the id to conditionsWithNoContraindications with a reviewed justification.
            """)

        let nowPopulated = Self.conditionsWithNoContraindications.subtracting(actual).sorted()
        XCTAssertTrue(nowPopulated.isEmpty,
                      "These now have contraindications — remove them from the allowlist: \(nowPopulated)")
    }

    /// If an exercise appears in both lists for one condition, `verify` resolves the
    /// contradiction silently (unsafe wins) and the data error is never surfaced.
    func testSafeAndUnsafeExercises_areDisjointPerCondition() throws {
        let graph = try realGraph()

        for (id, condition) in graph.conditions {
            let both = Set(condition.safeExercises).intersection(condition.unsafeExercises).sorted()
            XCTAssertTrue(both.isEmpty, "\(id): listed as both safe and unsafe: \(both)")
        }
    }

    func testConditionIDs_areKebabCase() throws {
        let graph = try realGraph()

        for id in graph.conditions.keys {
            XCTAssertNotNil(id.range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression),
                            "\(id): condition ids must be kebab-case to match the lookup tables")
        }
    }

    /// `JSONDecoder` silently keeps the *last* value for a duplicated key, so two people
    /// each adding the same condition id produces a clean decode that quietly drops one
    /// definition. Only a raw-text scan can see it.
    func testNoDuplicateConditionIDs_inRawJSON() throws {
        let raw = try XCTUnwrap(String(data: try realGraphData(), encoding: .utf8))
        let graph = try realGraph()

        let pattern = try NSRegularExpression(pattern: #"^\s{4}"([a-z0-9-]+)"\s*:\s*\{"#, options: .anchorsMatchLines)
        let matches = pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
        let ids = matches.compactMap { Range($0.range(at: 1), in: raw).map { String(raw[$0]) } }

        XCTAssertEqual(ids.count, graph.conditions.count, """
            Raw JSON has \(ids.count) condition keys but decoding produced \
            \(graph.conditions.count) — a duplicate key silently overwrote an entry.
            """)
    }

    // MARK: - Fail-open behaviour

    /// Pins the fact that a corrupt graph degrades to "nothing is contraindicated" rather
    /// than crashing. This is the current, deliberate design — but it means corruption is
    /// invisible at runtime, which is why the integrity assertions above exist. If this
    /// ever becomes fail-closed, this test should be updated, not deleted.
    func testMalformedGraph_failsOpenToUnverified_ratherThanCrashing() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kg-malformed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(#"{ "version": "1.0", "conditions": "not-an-object" }"#.utf8)
            .write(to: dir.appendingPathComponent("medical_knowledge_graph.json"))

        let service = KnowledgeGraphService(bundle: try XCTUnwrap(Bundle(path: dir.path)))

        // The same pair the production graph flags as contraindicated.
        let tier = service.verify(exercise: "Bulgarian Split Squat",
                                  forCondition: "patellofemoral pain syndrome")

        XCTAssertEqual(tier, .unverified,
                       "A corrupt graph must degrade to .unverified (fail-open), not crash or falsely verify")
    }

    // MARK: - v2

    /// v2 is not in the repo yet (`KnowledgeGraphFeatureFlag` defaults off and the merge
    /// logic is covered by `KnowledgeGraphExpansionTests` with fixtures). This activates
    /// on its own the moment the file lands, rather than claiming coverage that can't exist.
    func testV2Graph_ifBundled_decodesCleanly() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "medical_knowledge_graph_v2", withExtension: "json")
            ?? Bundle.main.url(forResource: "medical_knowledge_graph_v2", withExtension: "json")
        try XCTSkipIf(url == nil, "medical_knowledge_graph_v2.json is not bundled yet")

        let graph = try JSONDecoder().decode(KnowledgeGraph.self, from: Data(contentsOf: url!))

        XCTAssertFalse(graph.conditions.isEmpty, "A bundled v2 graph must contain conditions")
    }
}
