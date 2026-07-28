import XCTest

/// KassiOS 0.26.0 "Agent discovery": `device.dumpIdentifiers()` (the inventory
/// a coding agent scaffolds screens from) and the "did you mean?" suggestion
/// that lets a wrong-id guess self-correct.
final class IdentifierDiscoveryTests: KassTestCase {

    override func setUp() {
        super.setUp()
        config = KassConfig(accessibilityIdentifierPolicy: .enforce)
    }

    func test_dumpIdentifiers_returnsKnownDemoIdsWithCorrectTypes() {
        launch()
        onScreen(LoginScreen.self) { _ in }
        let inventory = device.dumpIdentifiers()
        let byId = Dictionary(uniqueKeysWithValues: inventory.map { ($0.identifier, $0) })

        XCTAssertEqual(byId["email"]?.type, "textField")
        XCTAssertEqual(byId["password"]?.type, "secureTextField")
        XCTAssertEqual(byId["signIn"]?.type, "button")
        // Default excludes elements without a real accessibility identifier.
        XCTAssertFalse(inventory.contains { $0.identifier.isEmpty })
    }

    func test_dumpIdentifiers_includingUnidentified_alsoListsLabelOnlyElements() {
        launch()
        onScreen(LoginScreen.self) { _ in }
        let identifiedOnly = device.dumpIdentifiers()
        let everything = device.dumpIdentifiers(includingUnidentified: true)
        XCTAssertGreaterThan(everything.count, identifiedOnly.count)
        XCTAssertTrue(everything.contains { $0.identifier.isEmpty })
    }

    func test_wrongIdGuess_failsWithDidYouMeanSuggestion() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { $0.welcome.assertVisible() }

        onScreen(HomeScreen.self) { home in
            // "welcom" is a deliberate one-letter-off near-miss of the real id
            // ("welcome") — proves the suggestion self-corrects a wrong-id guess.
            XCTExpectFailure(
                "deliberate near-miss id — exercises the 'did you mean?' suggestion",
                failingBlock: {
                    _ = home.staticText("welcom").within(timeout: 2).assertVisible()
                },
                issueMatcher: { issue in
                    issue.compactDescription.contains("did you mean") && issue.compactDescription.contains("welcome")
                }
            )
        }
    }
}
