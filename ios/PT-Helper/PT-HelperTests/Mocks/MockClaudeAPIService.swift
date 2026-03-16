import Foundation
@testable import PT_Helper

/// Mock implementation of ClaudeAPIServiceProtocol for unit testing.
/// Configure `responseToReturn` or `errorToThrow` before calling the API method.
///
/// For multi-call testing (e.g. the two-call verify pipeline), use `responsesQueue`
/// and `errorsQueue` which are consumed in FIFO order. When empty, they fall back
/// to `responseToReturn` and `errorToThrow` respectively.
final class MockClaudeAPIService: ClaudeAPIServiceProtocol {
    /// The response string to return on success (fallback when responsesQueue is empty).
    var responseToReturn: String = ""

    /// If set, the mock throws this error instead of returning a response (fallback when errorsQueue is empty).
    var errorToThrow: Error?

    /// Number of times `sendMessage` was called.
    private(set) var sendMessageCallCount = 0

    /// The most recent `requestType` passed to `sendMessage`.
    private(set) var lastRequestType: AIRequestType?

    /// The most recent `userMessage` passed to `sendMessage`.
    private(set) var lastUserMessage: String?

    /// Optional delay in seconds to simulate network latency.
    var simulatedDelay: TimeInterval = 0

    // MARK: - Multi-Call Support

    /// FIFO queue of responses. Pops the first element on each call.
    /// When empty, falls back to `responseToReturn`.
    var responsesQueue: [String] = []

    /// FIFO queue of per-call errors. Pops the first element on each call.
    /// If the popped value is non-nil, throws it. When empty, falls back to `errorToThrow`.
    var errorsQueue: [Error?] = []

    /// Ordered list of all request types across calls (for verifying call sequence).
    private(set) var allRequestTypes: [AIRequestType] = []

    /// Ordered list of all user messages across calls (for verifying message content).
    private(set) var allUserMessages: [String] = []

    func sendMessage(requestType: AIRequestType, userMessage: String) async throws -> String {
        sendMessageCallCount += 1
        lastRequestType = requestType
        lastUserMessage = userMessage
        allRequestTypes.append(requestType)
        allUserMessages.append(userMessage)

        if simulatedDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
        }

        // Check per-call error queue first, then fall back to global error
        if !errorsQueue.isEmpty {
            let queuedError = errorsQueue.removeFirst()
            if let error = queuedError {
                throw error
            }
        } else if let error = errorToThrow {
            throw error
        }

        // Return from queue if available, otherwise fall back to responseToReturn
        if !responsesQueue.isEmpty {
            return responsesQueue.removeFirst()
        }
        return responseToReturn
    }
}
