import XCTest
@testable import KassiOS

@MainActor
final class KassBuiltinInterceptorsTests: XCTestCase {

    final class CapturingLogger: KassLogger, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var messages: [String] { lock.lock(); defer { lock.unlock() }; return storage }
        func log(_ message: String) { lock.lock(); storage.append(message); lock.unlock() }
    }

    private func context() -> KassActionContext {
        KassActionContext(
            kind: .tap, name: "tap", elementDescription: "login button", identifier: "signIn",
            timeout: 1, pollInterval: 0.02, flakySafetyEnabled: true, file: #filePath, line: #line
        )
    }

    func test_logging_recordsStartAndSuccess() throws {
        let logger = CapturingLogger()
        try KassInterceptorChain.run([KassLoggingInterceptor(logger: logger)], context: context()) {}
        XCTAssertEqual(logger.messages.count, 2)
        XCTAssertTrue(logger.messages[0].contains("tap"))
        XCTAssertTrue(logger.messages[0].contains("login button"))
        XCTAssertTrue(logger.messages[1].hasPrefix("✓"))
    }

    func test_logging_recordsFailureAndRethrows() {
        let logger = CapturingLogger()
        XCTAssertThrowsError(
            try KassInterceptorChain.run([KassLoggingInterceptor(logger: logger)], context: context()) {
                throw KassError("boom")
            }
        )
        XCTAssertEqual(logger.messages.count, 2)
        XCTAssertTrue(logger.messages[1].hasPrefix("✗"))
        XCTAssertTrue(logger.messages[1].contains("boom"))
    }
}
