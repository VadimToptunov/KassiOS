import XCTest
@testable import KassiOS

@MainActor
final class KassInterceptorTests: XCTestCase {

    // A shared, main-actor-isolated sink the test doubles write into.
    @MainActor final class Recorder {
        var events: [String] = []
        var intercepts = 0
    }

    // Records enter/exit around `proceed`, so we can see composition order.
    struct RecordingInterceptor: KassInterceptor {
        let tag: String
        let recorder: Recorder
        @MainActor
        func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws {
            recorder.events.append("\(tag)-before")
            try proceed()
            recorder.events.append("\(tag)-after")
        }
    }

    // Counts how many times it is entered — to tell once vs per-attempt apart.
    struct CountingInterceptor: KassInterceptor {
        let recorder: Recorder
        let key: String
        @MainActor
        func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws {
            recorder.events.append(key)
            recorder.intercepts += 1
            try proceed()
        }
    }

    // Captures the context that flows through, for assertion.
    @MainActor final class ContextBox { var value: KassActionContext? }
    struct Capture: KassInterceptor {
        let box: ContextBox
        @MainActor
        func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws {
            box.value = context
            try proceed()
        }
    }

    private func context(
        timeout: TimeInterval = 1,
        pollInterval: TimeInterval = 0.02,
        flakySafetyEnabled: Bool = true
    ) -> KassActionContext {
        KassActionContext(
            kind: .tap,
            name: "tap",
            elementDescription: "login button",
            identifier: "signIn",
            timeout: timeout,
            pollInterval: pollInterval,
            flakySafetyEnabled: flakySafetyEnabled,
            file: #filePath,
            line: #line
        )
    }

    func test_composesOutermostFirst() throws {
        let recorder = Recorder()
        let chain: [KassInterceptor] = [
            RecordingInterceptor(tag: "A", recorder: recorder),
            RecordingInterceptor(tag: "B", recorder: recorder)
        ]
        try KassInterceptorChain.run(chain, context: context()) {
            recorder.events.append("terminal")
        }
        XCTAssertEqual(recorder.events, ["A-before", "B-before", "terminal", "B-after", "A-after"])
    }

    func test_emptyChain_runsTerminalOnce() throws {
        let recorder = Recorder()
        try KassInterceptorChain.run([], context: context()) {
            recorder.events.append("terminal")
        }
        XCTAssertEqual(recorder.events, ["terminal"])
    }

    func test_retryInterceptor_recoversAfterTransientFailures() throws {
        var attempts = 0
        try KassInterceptorChain.run([KassRetryInterceptor()], context: context()) {
            attempts += 1
            if attempts < 3 { throw KassError("not yet") }
        }
        XCTAssertEqual(attempts, 3)
    }

    func test_retryInterceptor_disabledViaContext_triesExactlyOnce() {
        var attempts = 0
        XCTAssertThrowsError(
            try KassInterceptorChain.run(
                [KassRetryInterceptor()],
                context: context(flakySafetyEnabled: false)
            ) {
                attempts += 1
                throw KassError("always")
            }
        )
        XCTAssertEqual(attempts, 1)
    }

    func test_noRetryInterceptor_doesNotRetry() {
        var attempts = 0
        XCTAssertThrowsError(
            try KassInterceptorChain.run([], context: context()) {
                attempts += 1
                throw KassError("always")
            }
        )
        XCTAssertEqual(attempts, 1)
    }

    /// The full-model payoff: an interceptor *before* retry runs once (outside
    /// the loop); one *after* retry runs on every attempt (inside the loop).
    func test_positionRelativeToRetry_decidesOnceVsPerAttempt() throws {
        let recorder = Recorder()
        let outer = CountingInterceptor(recorder: recorder, key: "outer")
        let inner = CountingInterceptor(recorder: recorder, key: "inner")
        var attempts = 0
        try KassInterceptorChain.run(
            [outer, KassRetryInterceptor(), inner],
            context: context()
        ) {
            attempts += 1
            if attempts < 3 { throw KassError("not yet") }
        }
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(recorder.events.filter { $0 == "outer" }.count, 1, "before retry → once")
        XCTAssertEqual(recorder.events.filter { $0 == "inner" }.count, 3, "after retry → per attempt")
    }

    func test_context_carriesActionMetadata() throws {
        let box = ContextBox()
        try KassInterceptorChain.run([Capture(box: box)], context: context(timeout: 7)) {}
        XCTAssertEqual(box.value?.kind, .tap)
        XCTAssertEqual(box.value?.name, "tap")
        XCTAssertEqual(box.value?.identifier, "signIn")
        XCTAssertEqual(box.value?.timeout, 7)
    }

    func test_defaultConfig_shipsRetryInterceptor() {
        XCTAssertEqual(KassConfig.default.interceptors.count, 1)
        XCTAssertTrue(KassConfig.default.interceptors.first is KassRetryInterceptor)
    }
}
