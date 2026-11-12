import XCTest
@testable import COIL

/// Client half of the cross-stack response contract.
///
/// The server's Zod schemas had tests and the Swift structs had hand-written fixtures, but
/// neither referenced the other — so each side only ever proved it was self-consistent. A
/// field renamed in `functions/src/response-schemas.ts` would ship, and the client would
/// simply stop decoding it, with no test failing on either stack. Because server prompts and
/// schemas deploy independently of iOS releases, that drift can reach production between
/// releases. `ShadowModeJSONParser`'s permissive fallback makes it quieter still.
///
/// These tests decode the **same fixtures** the server test validates
/// (`contracts/response-schemas/`, mirrored into the test bundle as `contract-*.json` and
/// pinned byte-for-byte by `functions/test/response-schema-contract.test.ts`).
///
/// Two checks per shape, because one alone is insufficient:
/// 1. **Decode** into the production type — catches renamed, removed, or retyped fields,
///    which make the decode throw.
/// 2. **Key-set comparison** — catches fields *added* server-side, which `JSONDecoder`
///    silently ignores. A decode-only test would pass while the client quietly dropped new
///    data.
///
/// The key set is read via `Mirror` over a decoded value rather than a hand-maintained
/// `CodingKeys` list: these types all use synthesized coding keys, so the stored-property
/// names are the JSON keys, and reflecting avoids ~120 lines of boilerplate that would
/// itself need keeping in sync. If a type ever adopts a custom `CodingKeys` mapping, this
/// comparison stops being valid for it — switch that type to an explicit key list then.
final class ResponseSchemaContractTests: XCTestCase {

    // MARK: - Fixture loading

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "contract-\(name)", withExtension: "json"),
            "contract-\(name).json is not bundled into COILTests"
        )
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: try fixtureData(name))
        } catch {
            XCTFail("""
                \(type) no longer decodes contracts/response-schemas/\(name).json: \(error)

                A required field was renamed, removed, or retyped on one side. Update the \
                fixture, the Zod schema, and this struct together.
                """)
            throw error
        }
    }

    /// Stored-property names of a value — equal to its JSON keys under synthesized coding.
    private func propertyNames(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    /// Keys of a JSON object, optionally after walking into a nested array's first element.
    private func jsonKeys(_ data: Data, arrayField: String? = nil) throws -> Set<String> {
        let root = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "Fixture root should be a JSON object"
        )
        guard let arrayField else { return Set(root.keys) }

        let array = try XCTUnwrap(root[arrayField] as? [[String: Any]],
                                  "Expected \(arrayField) to be an array of objects")
        let first = try XCTUnwrap(array.first, "\(arrayField) must not be empty in a fixture")
        return Set(first.keys)
    }

    private func assertKeysMatch(
        fixture fixtureKeys: Set<String>,
        type typeKeys: Set<String>,
        label: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let onlyInFixture = fixtureKeys.subtracting(typeKeys).sorted()
        let onlyInType = typeKeys.subtracting(fixtureKeys).sorted()

        XCTAssertTrue(onlyInFixture.isEmpty, """
            \(label): the server sends these fields and the Swift type ignores them: \
            \(onlyInFixture). JSONDecoder drops unknown keys silently, so the client is \
            discarding data rather than failing.
            """, file: file, line: line)

        XCTAssertTrue(onlyInType.isEmpty, """
            \(label): the Swift type declares these fields and the contract does not: \
            \(onlyInType). Either the fixture is incomplete or the field is client-only \
            and should not be on a wire type.
            """, file: file, line: line)
    }

    // MARK: - analysis / analysis_verify

    func testAnalysisResponse_decodesContractFixture() throws {
        let response = try decode(AIAnalysisResponse.self, from: "analysis")

        XCTAssertFalse(response.conditions.isEmpty)
        XCTAssertEqual(response.conditions.first?.commonName, "Runner's Knee")
    }

    func testAnalysisResponse_fieldsMatchContract() throws {
        let data = try fixtureData("analysis")
        let response = try decode(AIAnalysisResponse.self, from: "analysis")

        assertKeysMatch(fixture: try jsonKeys(data),
                        type: propertyNames(of: response),
                        label: "AIAnalysisResponse")

        assertKeysMatch(fixture: try jsonKeys(data, arrayField: "conditions"),
                        type: propertyNames(of: try XCTUnwrap(response.conditions.first)),
                        label: "AIConditionResult")
    }

    // MARK: - rehab_plan

    func testRehabResponse_decodesContractFixture() throws {
        let response = try decode(AIRehabResponse.self, from: "rehab_plan")

        XCTAssertEqual(response.exercises.first?.name, "Quad Sets")
        XCTAssertEqual(response.totalWeeks, 6)
    }

    func testRehabResponse_fieldsMatchContract() throws {
        let data = try fixtureData("rehab_plan")
        let response = try decode(AIRehabResponse.self, from: "rehab_plan")

        assertKeysMatch(fixture: try jsonKeys(data),
                        type: propertyNames(of: response),
                        label: "AIRehabResponse")

        assertKeysMatch(fixture: try jsonKeys(data, arrayField: "exercises"),
                        type: propertyNames(of: try XCTUnwrap(response.exercises.first)),
                        label: "AIRehabExercise")
    }

    /// `wellness_plan` reuses `rehabPlanSchema` server-side but is decoded by a *second*,
    /// copy-pasted Swift type. That doubles the drift surface for one server shape, so pin
    /// it against the same fixture.
    func testWellnessPlanResponse_matchesTheSameContractAsRehabPlan() throws {
        let data = try fixtureData("rehab_plan")
        let response = try decode(AIWellnessPlanResponse.self, from: "rehab_plan")

        assertKeysMatch(fixture: try jsonKeys(data),
                        type: propertyNames(of: response),
                        label: "AIWellnessPlanResponse")

        assertKeysMatch(fixture: try jsonKeys(data, arrayField: "exercises"),
                        type: propertyNames(of: try XCTUnwrap(response.exercises.first)),
                        label: "AIWellnessExercise")
    }

    // MARK: - exercise_substitute

    func testSubstituteResponse_decodesContractFixture() throws {
        let response = try decode(AISubstituteResponse.self, from: "exercise_substitute")

        XCTAssertEqual(response.substitutes.first?.name, "Straight Leg Raises")
    }

    func testSubstituteResponse_fieldsMatchContract() throws {
        let data = try fixtureData("exercise_substitute")
        let response = try decode(AISubstituteResponse.self, from: "exercise_substitute")

        assertKeysMatch(fixture: try jsonKeys(data),
                        type: propertyNames(of: response),
                        label: "AISubstituteResponse")

        assertKeysMatch(fixture: try jsonKeys(data, arrayField: "substitutes"),
                        type: propertyNames(of: try XCTUnwrap(response.substitutes.first)),
                        label: "AISubstituteExercise")
    }

    // MARK: - wellness_analysis / wellness_verify

    func testWellnessResponse_decodesContractFixture() throws {
        let response = try decode(AIWellnessResponse.self, from: "wellness_analysis")

        XCTAssertEqual(response.recommendations.first?.title, "Desk Posture Reset")
    }

    func testWellnessResponse_fieldsMatchContract() throws {
        let data = try fixtureData("wellness_analysis")
        let response = try decode(AIWellnessResponse.self, from: "wellness_analysis")

        assertKeysMatch(fixture: try jsonKeys(data),
                        type: propertyNames(of: response),
                        label: "AIWellnessResponse")

        assertKeysMatch(fixture: try jsonKeys(data, arrayField: "recommendations"),
                        type: propertyNames(of: try XCTUnwrap(response.recommendations.first)),
                        label: "AIWellnessRecommendation")
    }

    // MARK: - form_analysis

    func testFormFeedbackResponse_decodesContractFixture() throws {
        let response = try decode(AIFormFeedbackResponse.self, from: "form_analysis")

        XCTAssertEqual(response.verdict, "good")
        XCTAssertEqual(response.overallScore, 82.5, accuracy: 0.001,
                       "The contract permits a fractional score; the wire type must accept one")
    }

    /// `AIFormFeedbackResponse` deliberately decodes two server shapes: `formAnalysisSchema`
    /// and the cross-session `agentFormAnalysisSchema` superset validated in
    /// `form-agent.ts`. So the contract's keys must be a *subset* of the type's fields
    /// rather than an exact match — but every contract key must still be present, which is
    /// the direction that catches a rename.
    func testFormFeedbackResponse_containsEveryContractField() throws {
        let data = try fixtureData("form_analysis")
        let response = try decode(AIFormFeedbackResponse.self, from: "form_analysis")

        let contractKeys = try jsonKeys(data)
        let typeKeys = propertyNames(of: response)

        let missing = contractKeys.subtracting(typeKeys).sorted()
        XCTAssertTrue(missing.isEmpty,
                      "AIFormFeedbackResponse is missing contract fields: \(missing)")

        let agentOnly = typeKeys.subtracting(contractKeys)
        XCTAssertEqual(agentOnly, ["progressTrends", "recurringIssues", "sessionComparison"],
                       """
                       The only fields on the type beyond form_analysis should be the \
                       cross-session agent extras. Anything else here is drift.
                       """)
    }
}
