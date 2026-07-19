import XCTest
import Combine

extension XCTestCase {
    /// Awaits until `publisher` emits a value satisfying `predicate`, else fails at `timeout`.
    func wait<P: Publisher>(for publisher: P, until predicate: @escaping (P.Output) -> Bool,
                            timeout: TimeInterval = 5) async where P.Failure == Never {
        let exp = expectation(description: "publisher satisfies predicate")
        var done = false
        let c = publisher.sink { value in
            if !done, predicate(value) { done = true; exp.fulfill() }
        }
        await fulfillment(of: [exp], timeout: timeout)
        c.cancel()
    }
}
