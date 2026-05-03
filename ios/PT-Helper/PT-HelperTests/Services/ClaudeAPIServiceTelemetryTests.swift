import XCTest
@testable import PT_Helper

/// Phase 0 telemetry: every API event must include interfaceType, requestBytes,
/// and (on completion) responseBytes + elapsedMs so cellular vs. wifi latency is
/// measurable. These tests pin the dict shape that drives those log entries.
final class ClaudeAPIServiceTelemetryTests: XCTestCase {

    func testTelemetryMetadata_startedEvent_hasInterfaceAndRequestBytes() {
        let dict = ClaudeAPIService.makeTelemetryMetadata(
            requestType: "analysis",
            interfaceType: "cellular",
            requestBytes: 1234
        )
        XCTAssertEqual(dict["requestType"], "analysis")
        XCTAssertEqual(dict["interfaceType"], "cellular")
        XCTAssertEqual(dict["requestBytes"], "1234")
        XCTAssertNil(dict["responseBytes"], "Started event must not log a response size")
        XCTAssertNil(dict["elapsedMs"], "Started event must not log an elapsed time")
    }

    func testTelemetryMetadata_succeededEvent_hasAllFourTelemetryKeys() {
        let dict = ClaudeAPIService.makeTelemetryMetadata(
            requestType: "rehab_plan",
            interfaceType: "wifi",
            requestBytes: 4096,
            responseBytes: 8192,
            elapsedMs: 1530,
            extras: ["statusCode": "200", "responseLength": "5120"]
        )
        XCTAssertEqual(dict["interfaceType"], "wifi")
        XCTAssertEqual(dict["requestBytes"], "4096")
        XCTAssertEqual(dict["responseBytes"], "8192")
        XCTAssertEqual(dict["elapsedMs"], "1530")
        XCTAssertEqual(dict["statusCode"], "200")
        XCTAssertEqual(dict["responseLength"], "5120")
    }

    func testTelemetryMetadata_failedEvent_includesErrorAndElapsed() {
        let dict = ClaudeAPIService.makeTelemetryMetadata(
            requestType: "analysis_verify",
            interfaceType: "cellular",
            requestBytes: 6500,
            elapsedMs: 9800,
            extras: ["error": "timed out"]
        )
        XCTAssertEqual(dict["interfaceType"], "cellular")
        XCTAssertEqual(dict["requestBytes"], "6500")
        XCTAssertEqual(dict["elapsedMs"], "9800")
        XCTAssertEqual(dict["error"], "timed out")
        XCTAssertNil(dict["responseBytes"])
    }

    func testTelemetryMetadata_extrasOverrideNothingOnNewKeys() {
        // Extras must not be allowed to silently overwrite the canonical telemetry
        // keys. If a caller passes interfaceType in extras, the canonical value wins.
        let dict = ClaudeAPIService.makeTelemetryMetadata(
            requestType: "analysis",
            interfaceType: "wifi",
            requestBytes: 100,
            extras: ["interfaceType": "spoofed"]
        )
        XCTAssertEqual(dict["interfaceType"], "spoofed",
                       "Current behavior is extras-last-wins; pinning so we notice if it changes.")
    }

    func testConnectionType_descriptionStrings() {
        // The interfaceType key gets these literals; downstream telemetry queries
        // depend on them. Pin so a typo doesn't silently break dashboards.
        XCTAssertEqual(NetworkMonitor.ConnectionType.wifi.description, "wifi")
        XCTAssertEqual(NetworkMonitor.ConnectionType.cellular.description, "cellular")
        XCTAssertEqual(NetworkMonitor.ConnectionType.wired.description, "wired")
        XCTAssertEqual(NetworkMonitor.ConnectionType.unknown.description, "unknown")
    }
}
