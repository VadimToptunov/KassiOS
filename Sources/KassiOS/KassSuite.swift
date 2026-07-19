import XCTest

/// A base class for a group of tests that share one configuration.
///
/// Override `configure()` once and every test in the subclass gets that
/// `KassConfig` — no repeating `config = …` in each `setUp`.
///
/// ```swift
/// class CheckoutSuite: KassSuite {
///     override func configure() -> KassConfig {
///         KassConfig(timeout: 20, reporter: AllureReporter(), accessibilityIdentifierPolicy: .enforce)
///     }
/// }
///
/// final class CartTests: CheckoutSuite { /* inherits the config */ }
/// ```
open class KassSuite: KassTestCase {

    /// The shared configuration for every test in this suite. Override to
    /// customize; defaults to `.default`. `nonisolated` so it can be called from
    /// the `nonisolated` `setUp()` — it only builds a `Sendable` `KassConfig`.
    nonisolated open func configure() -> KassConfig { .default }

    /// `nonisolated` to match `KassTestCase.setUp()`. Unlike that override,
    /// this one only touches plain (non-main-actor) state, so no isolation hop
    /// is needed.
    nonisolated open override func setUp() {
        super.setUp()
        config = configure()
    }
}

/// A structured test body: `before { } .after { } .run { }`.
///
/// `before` runs first; `after` is registered as an XCTest teardown block, so it
/// runs after the body **even if a step fails hard** (unlike a plain `defer`).
///
/// ```swift
/// before { launch() }
///     .after { device.screenshot("end") }
///     .run {
///         step("Add to cart") { … }
///         step("Checkout") { … }
///     }
/// ```
@MainActor
public final class KassRunBuilder {

    private let test: KassTestCase
    private var beforeBlock: (@MainActor () -> Void)?
    private var afterBlock: (@MainActor () -> Void)?

    init(test: KassTestCase) { self.test = test }

    @discardableResult
    public func before(_ block: @escaping @MainActor () -> Void) -> KassRunBuilder {
        beforeBlock = block
        return self
    }

    @discardableResult
    public func after(_ block: @escaping @MainActor () -> Void) -> KassRunBuilder {
        afterBlock = block
        return self
    }

    public func run(_ steps: () -> Void) {
        test.config.logger.log("▶︎ run")
        if let afterBlock = afterBlock {
            // `addTeardownBlock` requires a `@Sendable` closure because teardown
            // blocks are a general-purpose XCTest API. `MainActorBox` vouches for
            // `afterBlock` instead: XCTest always runs teardown blocks on the main
            // thread, so a same-actor, synchronous call here can never race.
            let box = MainActorBox(afterBlock)
            test.addTeardownBlock { @MainActor in box.value() }   // runs even if a step fails hard
        }
        beforeBlock?()
        steps()
    }
}

@MainActor
public extension KassTestCase {

    /// Starts a structured run with a `before` section.
    func before(_ block: @escaping @MainActor () -> Void) -> KassRunBuilder {
        KassRunBuilder(test: self).before(block)
    }

    /// Starts a structured run with an `after` section.
    func after(_ block: @escaping @MainActor () -> Void) -> KassRunBuilder {
        KassRunBuilder(test: self).after(block)
    }

    /// Runs a test body (no `before`/`after` sections).
    func run(_ steps: () -> Void) {
        KassRunBuilder(test: self).run(steps)
    }
}
