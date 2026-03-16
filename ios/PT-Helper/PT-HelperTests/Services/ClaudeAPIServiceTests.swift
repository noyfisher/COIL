import XCTest
@testable import PT_Helper

// MARK: - ClaudeAPIService Tests

final class ClaudeAPIServiceTests: XCTestCase {

    // MARK: - cleanJSONResponse Tests

    func testCleanJSON_plainJSON_unchanged() {
        let json = """
        {"key": "value"}
        """
        let result = ClaudeAPIService.cleanJSONResponse(json)
        XCTAssertEqual(result, "{\"key\": \"value\"}")
    }

    func testCleanJSON_jsonCodeFence_stripped() {
        let input = """
        ```json
        {"key": "value"}
        ```
        """
        let result = ClaudeAPIService.cleanJSONResponse(input)
        XCTAssertEqual(result, "{\"key\": \"value\"}")
    }

    func testCleanJSON_genericCodeFence_stripped() {
        let input = """
        ```
        {"key": "value"}
        ```
        """
        let result = ClaudeAPIService.cleanJSONResponse(input)
        XCTAssertEqual(result, "{\"key\": \"value\"}")
    }

    func testCleanJSON_whitespace_trimmed() {
        let input = "  \n  {\"key\": \"value\"}  \n  "
        let result = ClaudeAPIService.cleanJSONResponse(input)
        XCTAssertEqual(result, "{\"key\": \"value\"}")
    }

    func testCleanJSON_nestedBackticks_preserved() {
        let input = """
        ```json
        {"code": "use ```backticks``` for formatting"}
        ```
        """
        let result = ClaudeAPIService.cleanJSONResponse(input)
        // Inner backticks should remain; only outermost fences stripped
        XCTAssertTrue(result.contains("```backticks```"))
    }

    func testCleanJSON_noFences_unchanged() {
        let input = "{\"conditions\": [{\"name\": \"test\"}]}"
        let result = ClaudeAPIService.cleanJSONResponse(input)
        XCTAssertEqual(result, input)
    }

    func testCleanJSON_emptyString_returnsEmpty() {
        let result = ClaudeAPIService.cleanJSONResponse("")
        XCTAssertEqual(result, "")
    }

    func testCleanJSON_onlyFences_returnsEmpty() {
        let result = ClaudeAPIService.cleanJSONResponse("``````")
        XCTAssertEqual(result, "")
    }

    // MARK: - Error Description Tests

    func testClaudeAPIError_invalidURL_hasDescription() {
        let error = ClaudeAPIError.invalidURL
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("URL"))
    }

    func testClaudeAPIError_rateLimited_hasDescription() {
        let error = ClaudeAPIError.rateLimited
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("busy"))
    }

    func testClaudeAPIError_authenticationRequired_hasDescription() {
        let error = ClaudeAPIError.authenticationRequired
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("sign in"))
    }

    func testClaudeAPIError_noContent_hasDescription() {
        let error = ClaudeAPIError.noContent
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("empty"))
    }

    func testClaudeAPIError_invalidResponse_parsesAnthropicErrorJSON() {
        let errorJSON = "{\"error\": {\"message\": \"Rate limit exceeded\"}}"
        let error = ClaudeAPIError.invalidResponse(429, errorJSON)
        XCTAssertTrue(error.errorDescription!.contains("Rate limit exceeded"))
    }

    func testClaudeAPIError_invalidResponse_parsesProxyErrorJSON() {
        let errorJSON = "{\"error\": \"Server overloaded\"}"
        let error = ClaudeAPIError.invalidResponse(503, errorJSON)
        XCTAssertTrue(error.errorDescription!.contains("Server overloaded"))
    }

    func testClaudeAPIError_invalidResponse_fallsBackGracefully() {
        let error = ClaudeAPIError.invalidResponse(500, "not json")
        XCTAssertTrue(error.errorDescription!.contains("500"))
    }

    // MARK: - Request Type Tests

    func testAIRequestType_rawValues() {
        XCTAssertEqual(AIRequestType.analysis.rawValue, "analysis")
        XCTAssertEqual(AIRequestType.rehab_plan.rawValue, "rehab_plan")
    }

    // MARK: - Mock Protocol Conformance

    func testMockClaudeAPIService_conformsToProtocol() {
        let mock = MockClaudeAPIService()
        let service: ClaudeAPIServiceProtocol = mock
        XCTAssertNotNil(service)
    }
}
