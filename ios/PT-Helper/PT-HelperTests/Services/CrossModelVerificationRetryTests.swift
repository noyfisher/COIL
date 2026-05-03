import XCTest
@testable import PT_Helper

/// Tier 2 PR D: tests for the retry wrapper in `CrossModelVerificationService`.
///
/// Tests exercise the pure `withRetry` helper directly with injected
/// operation closures. This bypasses Firebase auth and the network entirely,
/// so the tests are fast and deterministic.
///
/// Also covers `isRetryable(_:)` classification — which errors trigger retry
/// vs. which throw immediately — and the `.crossModelFailed → .serious`
/// warning helper.
final class CrossModelVerificationRetryTests: XCTestCase {

    // MARK: - isRetryable classification

    func testIsRetryable_networkError_true() {
        let err = CrossModelError.networkError(NSError(domain: "test", code: 0))
        XCTAssertTrue(CrossModelVerificationService.isRetryable(err))
    }

    func testIsRetryable_server500_true() {
        XCTAssertTrue(CrossModelVerificationService.isRetryable(.serverError(500)))
    }

    func testIsRetryable_server502_true() {
        XCTAssertTrue(CrossModelVerificationService.isRetryable(.serverError(502)))
    }

    func testIsRetryable_server503_true() {
        XCTAssertTrue(CrossModelVerificationService.isRetryable(.serverError(503)))
    }

    func testIsRetryable_server400_false() {
        // 4xx is a client error — retrying won't help.
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.serverError(400)))
    }

    func testIsRetryable_server401_false() {
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.serverError(401)))
    }

    func testIsRetryable_server429_false() {
        // 429 rate-limit: technically transient but the cross-verify endpoint
        // applies its own quota; retrying just burns quota faster. Leave as
        // non-retryable and let the user retry later.
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.serverError(429)))
    }

    func testIsRetryable_authenticationRequired_false() {
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.authenticationRequired))
    }

    func testIsRetryable_invalidURL_false() {
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.invalidURL))
    }

    func testIsRetryable_decodingError_false() {
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.decodingError))
    }

    func testIsRetryable_invalidResponse_false() {
        XCTAssertFalse(CrossModelVerificationService.isRetryable(.invalidResponse))
    }

    // MARK: - withRetry attempt counting

    /// 3 retryable failures → rethrows after 3 attempts, counter confirms 3 calls.
    func testWithRetry_threeNetworkFailures_throwsAfterThreeAttempts() async {
        let counter = AttemptCounter()
        let delays: [Duration] = [.zero, .zero, .zero]

        do {
            _ = try await CrossModelVerificationService.withRetry(delays: delays) {
                await counter.increment()
                throw CrossModelError.networkError(NSError(domain: "test", code: 0))
            }
            XCTFail("Expected withRetry to throw after exhausting attempts")
        } catch let error as CrossModelError {
            if case .networkError = error {
                // Expected
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Expected CrossModelError, got \(error)")
        }

        let attempts = await counter.value
        XCTAssertEqual(attempts, 3, "Should make exactly 3 attempts (one per delay slot)")
    }

    /// Fail twice then succeed on the 3rd try → returns successfully with 3 calls.
    func testWithRetry_twoFailuresThenSuccess_returnsOnThirdAttempt() async throws {
        let counter = AttemptCounter()
        let delays: [Duration] = [.zero, .zero, .zero]

        let result = try await CrossModelVerificationService.withRetry(delays: delays) {
            let attemptNumber = await counter.increment()
            if attemptNumber < 3 {
                throw CrossModelError.networkError(NSError(domain: "test", code: 0))
            }
            return "recovered"
        }

        XCTAssertEqual(result, "recovered")
        let attempts = await counter.value
        XCTAssertEqual(attempts, 3, "Should have called 3 times (two failures + one success)")
    }

    /// Non-retryable error → rethrows immediately without consuming remaining attempts.
    func testWithRetry_nonRetryableError_throwsAfterFirstAttempt() async {
        let counter = AttemptCounter()
        let delays: [Duration] = [.zero, .zero, .zero]

        do {
            _ = try await CrossModelVerificationService.withRetry(delays: delays) {
                await counter.increment()
                throw CrossModelError.authenticationRequired
            }
            XCTFail("Expected withRetry to throw")
        } catch let error as CrossModelError {
            if case .authenticationRequired = error {
                // Expected
            } else {
                XCTFail("Expected authenticationRequired, got \(error)")
            }
        } catch {
            XCTFail("Expected CrossModelError, got \(error)")
        }

        let attempts = await counter.value
        XCTAssertEqual(attempts, 1, "Non-retryable errors should throw without retrying")
    }

    /// 4xx status code → non-retryable, throws immediately.
    func testWithRetry_clientError_throwsAfterFirstAttempt() async {
        let counter = AttemptCounter()
        let delays: [Duration] = [.zero, .zero, .zero]

        do {
            _ = try await CrossModelVerificationService.withRetry(delays: delays) {
                await counter.increment()
                throw CrossModelError.serverError(400)
            }
            XCTFail("Expected withRetry to throw")
        } catch let error as CrossModelError {
            if case .serverError(let code) = error {
                XCTAssertEqual(code, 400)
            } else {
                XCTFail("Expected serverError(400), got \(error)")
            }
        } catch {
            XCTFail("Expected CrossModelError, got \(error)")
        }

        let attempts = await counter.value
        XCTAssertEqual(attempts, 1, "4xx errors should not be retried")
    }

    /// Success on first attempt → exactly 1 call, no retries.
    func testWithRetry_successFirstAttempt_noRetries() async throws {
        let counter = AttemptCounter()
        let delays: [Duration] = [.zero, .zero, .zero]

        let result = try await CrossModelVerificationService.withRetry(delays: delays) {
            await counter.increment()
            return 42
        }

        XCTAssertEqual(result, 42)
        let attempts = await counter.value
        XCTAssertEqual(attempts, 1)
    }

    /// Mixed 5xx then 4xx: first attempt 5xx (retryable), second attempt 4xx
    /// (non-retryable) → throws the 4xx immediately after 2 attempts.
    func testWithRetry_retryableThenNonRetryable_throwsNonRetryableImmediately() async {
        let counter = AttemptCounter()
        let delays: [Duration] = [.zero, .zero, .zero]

        do {
            _ = try await CrossModelVerificationService.withRetry(delays: delays) {
                let n = await counter.increment()
                if n == 1 {
                    throw CrossModelError.serverError(502)
                }
                throw CrossModelError.serverError(400)
            }
            XCTFail("Expected withRetry to throw")
        } catch let error as CrossModelError {
            if case .serverError(let code) = error {
                XCTAssertEqual(code, 400, "Should rethrow the non-retryable 4xx, not the earlier 5xx")
            } else {
                XCTFail("Expected serverError(400), got \(error)")
            }
        } catch {
            XCTFail("Expected CrossModelError, got \(error)")
        }

        let attempts = await counter.value
        XCTAssertEqual(attempts, 2, "Should stop as soon as a non-retryable error surfaces")
    }

    // MARK: - crossModelFailureWarning helper

    func testCrossModelFailureWarning_emitsSerious() {
        let warning = ResponseValidationPipeline.crossModelFailureWarning(exerciseName: "Jump Squat")
        XCTAssertEqual(warning.severity, .serious)
        XCTAssertTrue(warning.message.contains("Jump Squat"))
    }

    func testCrossModelFailureWarning_messageIsActionable() {
        // The message should mention PT consultation so the user knows the
        // plan path forward, not just that something failed.
        let warning = ResponseValidationPipeline.crossModelFailureWarning(exerciseName: "Deep Squat")
        XCTAssertTrue(warning.message.lowercased().contains("physical therapist"))
    }

    // MARK: - Defaults sanity check

    func testDefaultRetryDelays_haveThreeAttempts() {
        // DoD: the production retry schedule is 3 attempts.
        XCTAssertEqual(CrossModelVerificationService.defaultRetryDelays.count, 3)
    }

    func testDefaultRetryDelays_areExponential() {
        let delays = CrossModelVerificationService.defaultRetryDelays
        XCTAssertEqual(delays.count, 3)
        XCTAssertEqual(delays[0], .seconds(1))
        XCTAssertEqual(delays[1], .seconds(2))
        XCTAssertEqual(delays[2], .seconds(4))
    }
}

// MARK: - Helpers

/// Actor-isolated counter so test closures can increment safely across
/// suspension points without data-race warnings.
private actor AttemptCounter {
    private(set) var value: Int = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
