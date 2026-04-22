import XCTest
@testable import PT_Helper

// MARK: - ClaudeAPIError Tests

final class ClaudeAPIErrorTests: XCTestCase {

    func testInvalidURLError() {
        let error = ClaudeAPIError.invalidURL
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("URL"))
    }

    func testNetworkError() {
        let underlyingError = NSError(domain: "NSURLErrorDomain", code: -1009, userInfo: [
            NSLocalizedDescriptionKey: "The Internet connection appears to be offline."
        ])
        let error = ClaudeAPIError.networkError(underlyingError)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("network"))
    }

    func testInvalidResponse_WithAPIErrorJSON() {
        let apiErrorBody = """
        {"type":"error","error":{"type":"invalid_request_error","message":"model: field required"}}
        """
        let error = ClaudeAPIError.invalidResponse(400, apiErrorBody)
        let description = error.errorDescription!
        XCTAssertTrue(description.contains("model: field required"), "Should parse API error message")
    }

    func testInvalidResponse_WithoutJSON() {
        let error = ClaudeAPIError.invalidResponse(500, "Internal Server Error")
        let description = error.errorDescription!
        XCTAssertTrue(description.contains("500"), "Should include status code")
    }

    func testDecodingError() {
        let error = ClaudeAPIError.decodingError(NSError(domain: "", code: 0))
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("process"))
    }

    func testNoContentError() {
        let error = ClaudeAPIError.noContent
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("empty"))
    }

    func testRateLimitedError() {
        let error = ClaudeAPIError.rateLimited
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("busy"))
    }

    func testAuthenticationRequiredError() {
        let error = ClaudeAPIError.authenticationRequired
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("sign in"))
    }

    func testInvalidResponse_WithProxyErrorJSON() {
        // Proxy returns { "error": "Rate limit exceeded..." } style errors
        let proxyErrorBody = """
        {"error":"Rate limit exceeded. Please wait before trying again."}
        """
        let error = ClaudeAPIError.invalidResponse(429, proxyErrorBody)
        let description = error.errorDescription!
        XCTAssertTrue(description.contains("Rate limit exceeded"), "Should parse proxy error message")
    }
}
