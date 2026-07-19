import Foundation

/// Vouches that a non-`Sendable` value is safe to hand across an isolation
/// boundary that requires `Sendable`, because it is only ever touched from the
/// main actor from that point on.
///
/// Two call sites need this:
/// - `KassTestCase.setUp()`/`tearDown()` override XCTestCase's `nonisolated`
///   (Objective-C) lifecycle hooks, but XCUITest only ever calls them on the
///   main thread. Boxing `self` before entering `MainActor.assumeIsolated`
///   sidesteps the Swift 6 "sending self" diagnostic for a value the compiler
///   otherwise can't prove stays on one actor — the box is the proof.
/// - `KassRunBuilder.run()` bridges an `@MainActor` closure into
///   `XCTestCase.addTeardownBlock`, which requires `@Sendable`.
struct MainActorBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
