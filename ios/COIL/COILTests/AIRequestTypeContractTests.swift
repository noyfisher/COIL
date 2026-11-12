import XCTest
@testable import COIL

/// P3-02: pins the client side of the AI request-type contract. The canonical
/// list lives in `contracts/ai-request-types.json` and is enforced on the server
/// by `functions/test/contract.test.ts`. This asserts the iOS `AIRequestType`
/// enum matches that exact list, so a case added/renamed/removed on the client
/// without updating the contract + server (or vice versa) fails a test.
///
/// (Unit tests run sandboxed on the simulator and can't read the repo JSON at
/// runtime, so the expected list is mirrored here — keep it in sync with
/// contracts/ai-request-types.json.)
final class AIRequestTypeContractTests: XCTestCase {

    /// MUST equal contracts/ai-request-types.json → clientRequestTypes.
    private let contractTypes = [
        "analysis",
        "analysis_verify",
        "rehab_plan",
        "exercise_substitute",
        "recovery_insights",
        "form_analysis",
        "wellness_analysis",
        "wellness_verify",
        "wellness_plan",
    ]

    func testAIRequestTypeMatchesTheContract() {
        let actual = AIRequestType.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(actual, contractTypes.sorted(),
                       "AIRequestType drifted from contracts/ai-request-types.json — update the contract + functions server + this test together.")
    }

    func testDoesNotExposeScheduledOnlyType() {
        XCTAssertFalse(AIRequestType.allCases.map(\.rawValue).contains("nightly_report"))
    }
}
