import Foundation

/// Strategy that settles the app before each interaction attempt.
///
/// KassiOS is poll-based by default: `Waiter` re-tries an interaction until the
/// UI is ready. A synchronizer adds an orthogonal guarantee — block until the
/// app is *idle* (no animations, in-flight network or pending main-queue work),
/// the way EarlGrey does — for stronger flaky-safety.
///
/// The core ships `NoOpSynchronizer` (pure polling) so it stays
/// dependency-free. Plug in a real backend via `KassConfig(synchronizer:)`; see
/// `Examples/EarlGreySynchronizer.swift` for an EarlGrey-backed adapter.
public protocol KassSynchronizer: Sendable {

    /// Block until the app under test is idle, treating `timeout` as the upper
    /// bound for a single settle. May return early; must not exceed `timeout`.
    func waitForIdle(timeout: TimeInterval)
}

/// Default backend: no explicit synchronization — relies on `Waiter` polling.
public struct NoOpSynchronizer: KassSynchronizer {
    public init() {}
    public func waitForIdle(timeout: TimeInterval) {}
}
