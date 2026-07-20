import Foundation

/// The category of a DSL action, so an interceptor can react to some kinds and
/// pass others straight through (e.g. handle system dialogs only around taps).
public enum KassActionKind: Sendable {
    case tap
    case type
    case clear
    case gesture
    case scroll
    case control
    case assert
    case wait
    case custom
}

/// Everything an interceptor needs to know about the action it is wrapping.
///
/// `name` is the human-readable action label (e.g. `"typeText('hi')"`);
/// `elementDescription` is the element it acts on. The timing fields carry the
/// *effective* budget for this call (already reflecting any `within(timeout:)`
/// override), so a retry interceptor can stay stateless.
public struct KassActionContext: Sendable {
    public let kind: KassActionKind
    public let name: String
    public let elementDescription: String
    public let identifier: String?
    public let timeout: TimeInterval
    public let pollInterval: TimeInterval
    public let flakySafetyEnabled: Bool
    public let file: StaticString
    public let line: UInt

    public init(
        kind: KassActionKind,
        name: String,
        elementDescription: String,
        identifier: String?,
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        flakySafetyEnabled: Bool,
        file: StaticString,
        line: UInt
    ) {
        self.kind = kind
        self.name = name
        self.elementDescription = elementDescription
        self.identifier = identifier
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.flakySafetyEnabled = flakySafetyEnabled
        self.file = file
        self.line = line
    }
}

/// A pluggable link in the chain every waiting DSL action flows through —
/// interactions, assertions, scrolls, collection assertions and wait-combinators
/// (non-waiting reads like `readValue()` are not actions and bypass it).
///
/// Interceptors compose in declared order (`config.interceptors[0]` is
/// outermost). Wrap `proceed` and call it — once for a plain observer, more than
/// once to retry, or not at all to short-circuit. Position relative to
/// ``KassRetryInterceptor`` decides whether you run once (before it, outside the
/// retry loop) or on every attempt (after it, inside the loop).
public protocol KassInterceptor: Sendable {
    /// Wrap `proceed`. Call it exactly once, or deliberately more (e.g. retry).
    @MainActor
    func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws
}

/// The built-in flaky-safety engine, expressed as an interceptor so it can be
/// reordered or replaced. Retries `proceed` until it stops throwing or the
/// shared time budget (`context.timeout`) elapses — the same semantics KassiOS
/// has always had, now a first-class link in the chain. Present in the default
/// `config.interceptors`; remove it to run every action exactly once.
public struct KassRetryInterceptor: KassInterceptor {
    public init() {}

    @MainActor
    public func intercept(_ context: KassActionContext, proceed: () throws -> Void) throws {
        try Waiter.retry(
            timeout: context.timeout,
            pollInterval: context.pollInterval,
            enabled: context.flakySafetyEnabled
        ) {
            try proceed()
        }
    }
}

/// Folds a list of interceptors around a terminal action and runs it.
/// `interceptors[0]` ends up outermost.
enum KassInterceptorChain {
    @MainActor
    static func run(
        _ interceptors: [KassInterceptor],
        context: KassActionContext,
        terminal: @escaping () throws -> Void
    ) throws {
        var proceed = terminal
        for interceptor in interceptors.reversed() {
            let next = proceed
            proceed = { try interceptor.intercept(context, proceed: next) }
        }
        try proceed()
    }
}
