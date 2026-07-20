import XCTest

/// Exercises `KassSystemAlertInterceptor` against a real iOS system dialog:
/// tapping "Request Location" raises the springboard permission alert, and the
/// interceptor auto-accepts it, so the status flips to "authorized" without any
/// hand-written `addUIInterruptionMonitor`.
final class SystemAlertTests: KassTestCase {

    override func setUp() {
        super.setUp()
        // Retry first, then the alert handler so it runs on every attempt.
        config = KassConfig(interceptors: [
            KassRetryInterceptor(),
            KassSystemAlertInterceptor(.accept)
        ])
    }

    func test_systemAlertInterceptor_autoAllowsLocation() {
        launch()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.requestLocation.tap()
            // The permission dialog appears asynchronously; the interceptor
            // dismisses it on a retry of this assertion, then the status updates.
            home.locationStatus.within(timeout: 30).assertHasText("authorized")
        }
    }
}
