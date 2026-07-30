import Foundation
import XCTest

/// Built-in idle backend: polls a cheap signature of the accessibility tree and
/// settles once it stops changing, without requiring EarlGrey.
///
/// This is the classic "wait until the UI stops changing" heuristic — while an
/// animation, reflow or async layout pass is in flight, the tree's signature
/// keeps changing; once it holds steady for `stableFor`, the app is considered
/// idle. It never blocks longer than `timeout`, matching `KassSynchronizer`'s
/// contract.
///
/// Opt in via ``KassConfig``:
///
///     config = KassConfig(synchronizer: StabilizingSynchronizer())
///
/// The default remains `NoOpSynchronizer` — this type is additive, not a
/// behaviour change for existing suites.
public struct StabilizingSynchronizer: KassSynchronizer {

    /// How long the signature must stay unchanged to be considered settled.
    let stableFor: TimeInterval

    /// Delay between polls while waiting for the signature to hold steady.
    let pollInterval: TimeInterval

    /// Returns a cheap hash of "what the UI currently looks like". Injected so
    /// the settle loop is unit-testable without a simulator.
    ///
    /// Values are compared for equality only; a hash collision between two
    /// genuinely different trees would be read as "no change". With a 64-bit,
    /// per-run-seeded `String.hashValue` that probability is negligible for a
    /// single settle, so the loop trades it for not holding a large tree dump
    /// in memory across polls.
    let signature: @Sendable () -> Int

    /// Creates a synchronizer that settles on the live app's accessibility tree.
    ///
    /// The default signature snapshots `XCUIApplication().debugDescription` —
    /// the full accessibility-tree dump, which changes whenever a label, value,
    /// frame or enabled-state changes anywhere on screen. `debugDescription` is
    /// relatively expensive to compute, which is why the default `pollInterval`
    /// is 50ms and this synchronizer is opt-in rather than the default.
    public init(stableFor: TimeInterval = 0.1, pollInterval: TimeInterval = 0.05) {
        self.init(stableFor: stableFor, pollInterval: pollInterval) {
            // Every wait path calls `waitForIdle` on the main actor, but the
            // `KassSynchronizer` requirement isn't `@MainActor`-typed and a
            // custom interceptor could route `proceed` onto a background queue.
            // Rather than trip an opaque `fatalError` inside `assumeIsolated`,
            // degrade off-main to a constant signature — the loop then simply
            // settles after `stableFor` instead of crashing.
            guard Thread.isMainThread else { return 0 }
            return MainActor.assumeIsolated {
                XCUIApplication().debugDescription.hashValue
            }
        }
    }

    /// Testable init: caller supplies the signature, so the settle loop can be
    /// exercised without an `XCUIApplication`.
    init(stableFor: TimeInterval, pollInterval: TimeInterval, signature: @escaping @Sendable () -> Int) {
        self.stableFor = stableFor
        self.pollInterval = pollInterval
        self.signature = signature
    }

    public func waitForIdle(timeout: TimeInterval) {
        guard stableFor > 0, timeout > 0 else { return }

        let deadline = Date().addingTimeInterval(timeout)
        var lastSignature: Int?
        var lastChangeTime = Date()

        while true {
            // Timestamp *after* `signature()` so a slow tree dump is charged
            // against the shared timeout budget rather than being invisible.
            let current = signature()
            let now = Date()
            if current != lastSignature {
                lastSignature = current
                lastChangeTime = now
            }

            if now.timeIntervalSince(lastChangeTime) >= stableFor { return }
            if now >= deadline { return }

            let remaining = deadline.timeIntervalSince(now)
            guard remaining > 0 else { return }
            Thread.sleep(forTimeInterval: min(pollInterval, remaining))
        }
    }
}
