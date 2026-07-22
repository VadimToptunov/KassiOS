import XCTest

/// Phase 3 Tier C: device control through the host `kassios-agent`.
///
/// These `XCTSkip` unless the agent is running and its port/token reached the
/// test target (see the CI "Run the host agent" step). That's the graceful
/// degradation the roadmap asks for — never a hang, never a false failure.
final class DeviceTierCTests: KassTestCase {

    private let demoBundleID = "com.kassios.KassDemo"

    /// Pre-granting location via the agent means the app's request finds it
    /// already authorized — no springboard dialog at all.
    func test_permissions_grantLocation_thenNoDialog() throws {
        launch()  // installs the app so simctl privacy can target it
        try device.permissions.grant(.location, for: demoBundleID)

        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c"); $0.signIn.tap() }
        onScreen(HomeScreen.self) { home in
            home.requestLocation.tap()
            home.locationStatus.assertHasText("authorized")
        }
        // Leave location un-granted so SystemAlertTests (which runs after this,
        // alphabetically) still gets a real permission dialog to handle.
        try? device.permissions.reset(.location, for: demoBundleID)
    }

    /// Freezing the status bar (deterministic screenshots) round-trips through
    /// the agent; the app keeps working afterwards.
    func test_statusBar_freeze() throws {
        try device.statusBar.freeze(time: "9:41", battery: 100, cellularBars: 4)
        launch()
        onScreen(LoginScreen.self) { $0.email.assertVisible() }
    }

    /// Screen recording round-trips through the agent: start, a trivial
    /// interaction, stop — the returned mp4 bytes should be non-empty. Only
    /// runs when the agent is actually reachable; skips cleanly otherwise
    /// (matching the rest of this file, which relies on `KassAgentClient.require()`
    /// to `XCTSkip`, this test checks `fromEnvironment` directly since it wants
    /// to skip before doing any recording bookkeeping).
    func test_recording_startStop_returnsVideoBytes() throws {
        guard KassAgentClient.fromEnvironment() != nil else {
            throw XCTSkip("Tier C needs the host bridge — see other tests in this file for the fix.")
        }
        launch()
        try device.startRecording()
        onScreen(LoginScreen.self) { $0.email.typeText("a@b.c") }
        let data = try device.stopRecording()
        XCTAssertNotNil(data)
        XCTAssertFalse(data?.isEmpty ?? true)
    }
}
