import Foundation

// The **in-app** half of KassiOS network stubbing (Phase 4, Option 1). The app
// imports this product *in debug only* and calls `KassiOSStubs.installIfConfigured()`
// at launch. If the UI test passed stubs via the launch environment
// (`KassTestCase.launch(stubs:)`), a `URLProtocol` intercepts matching requests
// and replays a canned response — or fails offline — instead of hitting the
// network. No server, no ports; works on the simulator and real devices.

/// The app-side entry point. Call once at startup (guarded by `#if DEBUG`).
public enum KassiOSStubs {

    /// Installs the stub `URLProtocol` if the launch environment carries stubs.
    /// A no-op otherwise, so it's safe to call unconditionally in debug builds.
    public static func installIfConfigured(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let json = environment["KASS_STUBS_JSON"],
              let data = json.data(using: .utf8),
              let stubs = try? JSONDecoder().decode([KassStubDefinition].self, from: data),
              !stubs.isEmpty else { return }
        KassStubURLProtocol.stubs = stubs
        URLProtocol.registerClass(KassStubURLProtocol.self)
    }
}

/// The app-side copy of a stub. Matches the Codable shape encoded by KassiOS's
/// test-side `KassStub` (they're separate modules sharing the wire contract).
struct KassStubDefinition: Codable {
    let urlContains: String
    let method: String?
    let statusCode: Int
    let headers: [String: String]
    let body: String
    let failWithOffline: Bool
}

/// Replays stubbed responses for requests the app makes through `URLSession.shared`
/// (and any session whose configuration includes registered protocols).
final class KassStubURLProtocol: URLProtocol {
    // Set once during `installIfConfigured`, before any request runs.
    nonisolated(unsafe) static var stubs: [KassStubDefinition] = []

    /// The first stub matching `request` by URL substring (and method, if set).
    static func match(_ request: URLRequest) -> KassStubDefinition? {
        guard let url = request.url?.absoluteString else { return nil }
        return stubs.first { stub in
            // An empty substring matches everything (Swift's contains("") is false).
            (stub.urlContains.isEmpty || url.contains(stub.urlContains))
                && (stub.method == nil || stub.method?.uppercased() == request.httpMethod?.uppercased())
        }
    }

    // These override URLProtocol's class methods, so they must be `class func`.
    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool { match(request) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        guard let stub = Self.match(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if stub.failWithOffline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: stub.headers
        ) ?? HTTPURLResponse()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
