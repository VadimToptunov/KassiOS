import XCTest
@testable import KassiOS

@MainActor
final class KassFlakyTrackerTests: XCTestCase {

    override func setUp() { super.setUp(); KassFlakyTracker.shared.reset() }
    override func tearDown() { KassFlakyTracker.shared.reset(); super.tearDown() }

    private func context() -> KassActionContext {
        KassActionContext(
            kind: .tap, name: "tap", elementDescription: "login button", identifier: nil,
            timeout: 1, pollInterval: 0.01, flakySafetyEnabled: true, file: #filePath, line: #line
        )
    }

    func test_recordAndDrain_thenCleared() {
        KassFlakyTracker.shared.record(action: "tap", attempts: 2)
        XCTAssertEqual(KassFlakyTracker.shared.drain(), [KassFlakyRecovery(action: "tap", attempts: 2)])
        XCTAssertTrue(KassFlakyTracker.shared.drain().isEmpty)   // drain cleared it
    }

    func test_retryInterceptor_recordsRecoveryAfterRetries() throws {
        var attempts = 0
        try KassInterceptorChain.run([KassRetryInterceptor()], context: context()) {
            attempts += 1
            if attempts < 3 { throw KassError("not yet") }
        }
        let recoveries = KassFlakyTracker.shared.drain()
        XCTAssertEqual(recoveries.count, 1)
        XCTAssertEqual(recoveries.first?.action, "tap")
        XCTAssertEqual(recoveries.first?.attempts, 3)
    }

    func test_retryInterceptor_noRecoveryOnFirstTry() throws {
        try KassInterceptorChain.run([KassRetryInterceptor()], context: context()) { /* succeeds immediately */ }
        XCTAssertTrue(KassFlakyTracker.shared.drain().isEmpty)
    }
}
