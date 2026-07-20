import XCTest

/// A network stub: match requests by a URL substring and replay a canned
/// response — or fail them offline. Passed to the app via
/// `KassTestCase.launch(networkStubs:)`; the app serves them with the
/// `KassiOSStubs` product (Phase 4, the in-app stub bridge).
///
/// The test-side copy of the wire contract shared with `KassiOSStubs`; keep the
/// Codable shape identical.
public struct KassStub: Codable, Sendable {
    let urlContains: String
    let method: String?
    let statusCode: Int
    let headers: [String: String]
    let body: String
    let failWithOffline: Bool

    /// Replays `body` (default 200 / `application/json`) for requests whose URL
    /// contains `urlContains`. Narrow to a verb with `method`.
    public static func json(
        urlContains: String,
        status: Int = 200,
        body: String,
        method: String? = nil,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) -> KassStub {
        KassStub(
            urlContains: urlContains, method: method, statusCode: status,
            headers: headers, body: body, failWithOffline: false
        )
    }

    /// Fails matching requests with `URLError.notConnectedToInternet` — a
    /// deterministic stand-in for "offline". Empty `urlContains` matches every
    /// request (whole-app offline).
    public static func offline(urlContains: String = "") -> KassStub {
        KassStub(
            urlContains: urlContains, method: nil, statusCode: 0,
            headers: [:], body: "", failWithOffline: true
        )
    }
}

public extension KassTestCase {

    /// Launches with a network stub bundle: the app (linking `KassiOSStubs` in
    /// debug) intercepts matching requests and replays them, so a test never
    /// depends on the real network. Stubs are encoded into `KASS_STUBS_JSON`.
    /// (Distinct from `launch(stubs:)`, whose `[String: String]` sets the older
    /// `KASS_STUB_*` env convention the app interprets itself.)
    @discardableResult
    func launch(
        networkStubs: [KassStub],
        arguments: [String] = [],
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        var merged = environment
        if let data = try? JSONEncoder().encode(networkStubs), let json = String(data: data, encoding: .utf8) {
            merged["KASS_STUBS_JSON"] = json
        }
        return launch(arguments: arguments, environment: merged)
    }

    /// Launches with every request failing offline — the deterministic form of
    /// "no network". Shorthand for `launch(networkStubs: [.offline()])`.
    @discardableResult
    func launch(offline: Bool, arguments: [String] = [], environment: [String: String] = [:]) -> XCUIApplication {
        launch(networkStubs: offline ? [.offline()] : [], arguments: arguments, environment: environment)
    }
}
