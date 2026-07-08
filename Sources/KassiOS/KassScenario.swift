import XCTest

/// A reusable, named flow of steps — the KassiOS take on Kaspresso's `Scenario`.
///
/// Extract common journeys (log in, onboard, seed data) into a type and replay
/// them from any test via `KassTestCase.scenario(_:)`. The scenario runs against
/// the live test case, so it can drive `onScreen`, `step`, `device`, etc.
public protocol KassScenario {

    /// Human-readable name, grouped in the test report.
    var name: String { get }

    /// The steps to perform, given the test case they run in.
    func run(in test: KassTestCase)
}

public extension KassScenario {
    var name: String { String(describing: Self.self) }
}
