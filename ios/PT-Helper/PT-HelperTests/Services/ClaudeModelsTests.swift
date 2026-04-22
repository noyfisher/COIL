import XCTest
@testable import PT_Helper

// MARK: - Claude Request/Response Model Tests

final class ClaudeModelsTests: XCTestCase {

    func testClaudeProxyRequestEncoding() throws {
        let request = ClaudeProxyRequest(
            requestType: .analysis,
            messages: [ClaudeMessage(role: "user", content: "Analyze knee pain")]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["requestType"] as? String, "analysis", "Should encode request type")
        XCTAssertNil(json["model"], "Model should NOT be in client request (server-side only)")
        XCTAssertNil(json["max_tokens"], "max_tokens should NOT be in client request (server-side only)")
        XCTAssertNil(json["system"], "System prompt should NOT be in client request (server-side only)")

        let messages = json["messages"] as! [[String: String]]
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertEqual(messages[0]["content"], "Analyze knee pain")
    }

    func testClaudeProxyRequestEncoding_RehabPlan() throws {
        let request = ClaudeProxyRequest(
            requestType: .rehab_plan,
            messages: [ClaudeMessage(role: "user", content: "Build a rehab plan")]
        )

        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["requestType"] as? String, "rehab_plan")
    }

    func testClaudeResponseDecoding() throws {
        let json = """
        {
            "content": [
                {"type": "text", "text": "{\\"conditions\\":[]}" }
            ],
            "stop_reason": "end_turn"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ClaudeResponse.self, from: json)
        XCTAssertEqual(response.content.count, 1)
        XCTAssertEqual(response.content[0].type, "text")
        XCTAssertEqual(response.content[0].text, "{\"conditions\":[]}")
        XCTAssertEqual(response.stop_reason, "end_turn")
    }

    func testClaudeResponseDecoding_MultipleContentBlocks() throws {
        let json = """
        {
            "content": [
                {"type": "thinking", "text": "Let me analyze..."},
                {"type": "text", "text": "{\\"result\\":\\"ok\\"}"}
            ],
            "stop_reason": "end_turn"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(ClaudeResponse.self, from: json)
        XCTAssertEqual(response.content.count, 2)

        let textBlock = response.content.first(where: { $0.type == "text" })
        XCTAssertNotNil(textBlock)
        XCTAssertEqual(textBlock?.text, "{\"result\":\"ok\"}")
    }
}
