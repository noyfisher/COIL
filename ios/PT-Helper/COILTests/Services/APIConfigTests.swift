import XCTest
@testable import COIL

// MARK: - API Config Tests

final class APIConfigTests: XCTestCase {

    func testProxyURLIsValid() {
        let url = URL(string: APIConfig.claudeProxyURL)
        XCTAssertNotNil(url, "Proxy URL must be valid")
        XCTAssertEqual(url?.scheme, "https", "Proxy URL must use HTTPS")
        XCTAssertTrue(
            url?.host?.contains("cloudfunctions.net") == true,
            "Proxy URL should point to Cloud Functions"
        )
    }

    func testConfigHasOnlyProxyURL() {
        // After security hardening, model and max_tokens are server-side only
        XCTAssertFalse(APIConfig.claudeProxyURL.isEmpty, "Proxy URL must be configured")
    }
}
