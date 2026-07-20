import XCTest

/// Phase 4: the in-app network stub bridge. The demo app links `KassiOSStubs`
/// and calls `installIfConfigured()`, so `launch(stubs:)` fully controls what its
/// `URLSession` requests return — no real network, deterministic.
final class NetworkStubTests: KassTestCase {

    func test_stubbedResponse_drivesUI() {
        launch(stubs: [.json(urlContains: "/user", body: #"{"name":"Alex"}"#)])
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.fetchButton.tap()
            home.fetchResult.assertHasText("Alex")   // came from the stub, not the network
        }
    }

    func test_offline_failsDeterministically() {
        launch(offline: true)
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.fetchButton.tap()
            home.fetchResult.assertHasText("offline")   // URLError.notConnectedToInternet
        }
    }
}
