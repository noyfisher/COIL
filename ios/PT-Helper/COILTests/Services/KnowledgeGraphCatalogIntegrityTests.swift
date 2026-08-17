import XCTest
@testable import COIL

/// Cross-file invariant: every exercise id referenced by the bundled medical knowledge
/// graph must resolve in the bundled exercise image catalog.
///
/// Why this matters beyond a missing illustration: `ImageAvailabilityValidator` is
/// **step 1 of 9** in `ResponseValidationPipeline.validateRehabPlan`, and it *renames*
/// exercises it cannot resolve. The knowledge-graph contraindication check is step 3.
/// So an unresolvable exercise is silently substituted away *before* the safety check
/// ever sees its name — the contraindication never fires. The exercise disappears
/// because it lacks an image, not because anything recognised it as unsafe.
///
/// These two files are maintained independently (the catalog by `scripts/*.py`, the
/// graph by hand), so nothing else couples them.
final class KnowledgeGraphCatalogIntegrityTests: XCTestCase {

    /// Exercise ids known to be unresolvable, pending a clinical decision on what they
    /// should map to. Both are `unsafeExercises` entries, so picking a substitute is a
    /// medical judgement, not a mechanical rename — see the note in the test below.
    ///
    /// Added 2026-08-09. Shrink this list; never grow it.
    private static let knownUnresolvedIDs: Set<String> = [
        "nordic-hamstring-curl",   // unsafe for: hamstring-strain
        "standing-toe-touch",      // unsafe for: referred-pain-lower-back
    ]

    private struct ImageEntry: Decodable {
        let name: String
        let aliases: [String]?
    }

    private struct Graph: Decodable {
        struct Condition: Decodable {
            let safeExercises: [String]?
            let unsafeExercises: [String]?
        }
        let conditions: [String: Condition]
    }

    private func loadJSON(_ name: String) throws -> Data {
        let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        return try Data(contentsOf: try XCTUnwrap(url, "\(name).json not bundled"))
    }

    /// Mirrors the normalisation `ExerciseImageService` applies before matching:
    /// case-folded, non-alphanumerics collapsed to single dashes.
    private func normalize(_ s: String) -> String {
        let folded = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(folded)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    private func resolvableTokens() throws -> Set<String> {
        let mapping = try JSONDecoder().decode([String: ImageEntry].self, from: loadJSON("exercise_image_mapping"))
        var tokens = Set<String>()
        for (key, entry) in mapping {
            tokens.insert(normalize(key))
            tokens.insert(normalize(entry.name))
            for alias in entry.aliases ?? [] { tokens.insert(normalize(alias)) }
        }
        return tokens
    }

    private func graphExerciseIDs() throws -> Set<String> {
        let graph = try JSONDecoder().decode(Graph.self, from: loadJSON("medical_knowledge_graph"))
        var ids = Set<String>()
        for condition in graph.conditions.values {
            ids.formUnion(condition.safeExercises ?? [])
            ids.formUnion(condition.unsafeExercises ?? [])
        }
        return ids
    }

    // MARK: - Tests

    func testEveryGraphExerciseID_resolvesInImageCatalog() throws {
        let tokens = try resolvableTokens()
        let ids = try graphExerciseIDs()

        let unresolved = ids
            .filter { !tokens.contains(normalize($0)) }
            .filter { !Self.knownUnresolvedIDs.contains($0) }
            .sorted()

        XCTAssertTrue(
            unresolved.isEmpty,
            """
            Knowledge-graph exercise ids with no match in exercise_image_mapping.json: \(unresolved).
            These will be silently substituted by ImageAvailabilityValidator (step 1) before the \
            contraindication check (step 3) can see them. Either add the exercise to the image \
            catalog or correct the id in medical_knowledge_graph.json.
            """
        )
    }

    /// Guards the allowlist itself: once an id is fixed it must be removed from
    /// `knownUnresolvedIDs`, otherwise the list quietly outlives the problem and starts
    /// masking genuine regressions on those ids.
    func testKnownUnresolvedAllowlist_containsOnlyStillUnresolvedIDs() throws {
        let tokens = try resolvableTokens()

        let nowResolvable = Self.knownUnresolvedIDs
            .filter { tokens.contains(normalize($0)) }
            .sorted()

        XCTAssertTrue(nowResolvable.isEmpty,
                      "These ids now resolve — remove them from knownUnresolvedIDs: \(nowResolvable)")
    }

    /// The allowlist should only ever cover ids the graph still references. A stale entry
    /// means the id was deleted from the graph and the allowlist was not cleaned up.
    func testKnownUnresolvedAllowlist_containsOnlyIDsStillInTheGraph() throws {
        let ids = try graphExerciseIDs()

        let stale = Self.knownUnresolvedIDs.filter { !ids.contains($0) }.sorted()

        XCTAssertTrue(stale.isEmpty,
                      "These ids are no longer in the knowledge graph — remove them from knownUnresolvedIDs: \(stale)")
    }
}
