import XCTest
@testable import KassiOS

/// The pure parts of 1.8.0's reliability features: outcome checks, auto-scroll,
/// keyboard cover, one-snapshot reads and the HTTP helper.
final class KassReliabilityTests: XCTestCase {

    // MARK: Outcome checks

    func testTypedTextMatchesExactlyOrThroughTheFieldsFormatting() {
        XCTAssertTrue(KassTextMatch.matches("Alex", typed: "Alex"))
        XCTAssertTrue(KassTextMatch.matches("2,000", typed: "2000"))
        XCTAssertTrue(KassTextMatch.matches("4111 1111 1111 1111", typed: "4111111111111111"))
        XCTAssertFalse(KassTextMatch.matches("200", typed: "2000"))
        XCTAssertFalse(KassTextMatch.matches("Amount", typed: "2000"), "a placeholder isn't the typed text")
        XCTAssertFalse(KassTextMatch.matches("", typed: "--"), "nothing to compare once formatting is stripped")
    }

    @MainActor
    func testPollingStopsAsSoonAsTheConditionHolds() {
        var calls = 0
        XCTAssertTrue(kassPoll(within: 5) { calls += 1; return calls == 3 })
        XCTAssertEqual(calls, 3)
        XCTAssertFalse(kassPoll(within: 0.2) { false })
    }

    // MARK: Auto-scroll

    func testScrollDirectionFollowsWhereTheElementIs() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        XCTAssertEqual(KassAutoScroll.direction(toward: CGRect(x: 0, y: 900, width: 100, height: 40), in: screen), .up)
        let cutOff = CGRect(x: 0, y: 780, width: 100, height: 40)
        XCTAssertEqual(KassAutoScroll.direction(toward: cutOff, in: screen), .up, "cut off at the bottom")
        XCTAssertEqual(KassAutoScroll.direction(toward: CGRect(x: 0, y: -200, width: 100, height: 40), in: screen), .down)
        XCTAssertEqual(KassAutoScroll.direction(toward: CGRect(x: 500, y: 100, width: 100, height: 40), in: screen), .left)
        XCTAssertEqual(KassAutoScroll.direction(toward: CGRect(x: -300, y: 100, width: 100, height: 40), in: screen), .right)
        let onScreen = CGRect(x: 0, y: 100, width: 100, height: 40)
        XCTAssertNil(KassAutoScroll.direction(toward: onScreen, in: screen), "on screen: covered, not scrolled away")
        XCTAssertNil(KassAutoScroll.direction(toward: .zero, in: screen))
    }

    // MARK: Keyboard

    func testTheKeyboardCoversWhatReachesItsAccessoryBar() {
        let keyboard = CGRect(x: 0, y: 500, width: 400, height: 300)
        XCTAssertTrue(KassKeyboard.covers(CGRect(x: 0, y: 520, width: 100, height: 40), keyboard: keyboard))
        XCTAssertTrue(KassKeyboard.covers(CGRect(x: 0, y: 440, width: 100, height: 40), keyboard: keyboard), "under the accessory bar")
        XCTAssertFalse(KassKeyboard.covers(CGRect(x: 0, y: 100, width: 100, height: 40), keyboard: keyboard))
        XCTAssertFalse(KassKeyboard.covers(CGRect(x: 0, y: 520, width: 100, height: 40), keyboard: .zero), "no keyboard")
    }

    // MARK: One-snapshot reads

    private struct Node {
        let id: String
        let value: Any?
        let label: String
        var children: [Node] = []
    }

    func testSnapshotReadTakesTheFirstMatchAndPrefersValueOverLabel() {
        let tree = Node(id: "root", value: nil, label: "", children: [
            Node(id: "total", value: "€17,890.75", label: "Total"),
            Node(id: "group", value: nil, label: "", children: [
                Node(id: "eur", value: "", label: "€4,820.55"),
                Node(id: "total", value: "shadowed", label: ""),
            ]),
        ])
        let texts = KassSnapshotRead.texts(in: tree, identifiers: ["total", "eur", "absent"], children: { $0.children }) {
            ($0.id, $0.value, $0.label)
        }
        XCTAssertEqual(texts, ["total": "€17,890.75", "eur": "€4,820.55"])
    }

    // MARK: HTTP helper

    func testPathsJoinTheBaseWithOrWithoutSlashes() {
        let base = URL(string: "http://localhost:8080/")!
        XCTAssertEqual(KassHTTP.url(base, "/v1/accounts").absoluteString, "http://localhost:8080/v1/accounts")
        XCTAssertEqual(KassHTTP.url(URL(string: "http://h")!, "v1/x?limit=5").absoluteString, "http://h/v1/x?limit=5")
    }

    @MainActor
    func testRequestsCarryHeadersAndJsonAndExposeTheAnswer() {
        StubProtocol.reply = (201, #"{"id":"tx-1","amount":"-100.00","n":3}"#)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = KassHTTP(baseURL: URL(string: "http://test")!, headers: ["Authorization": "Bearer t", "X-A": "1"],
                           timeout: 5, session: URLSession(configuration: configuration))
        let response = api.post("/v1/transfers", json: ["amount": "100.00"], headers: ["X-A": "2"], expect: 201)
        XCTAssertEqual(response.status, 201)
        XCTAssertEqual(response["id"], "tx-1")
        XCTAssertEqual(response["n"], "3")
        XCTAssertNil(response["missing"])
        let sent = StubProtocol.lastRequest
        XCTAssertEqual(sent?.httpMethod, "POST")
        XCTAssertEqual(sent?.url?.absoluteString, "http://test/v1/transfers")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "X-A"), "2", "per-call headers win")
        XCTAssertEqual(sent?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(StubProtocol.lastBody, #"{"amount":"100.00"}"#)
    }

    @MainActor
    func testAnUnexpectedStatusFailsTheTest() {
        StubProtocol.reply = (422, #"{"type":"insufficientFunds"}"#)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let api = KassHTTP(baseURL: URL(string: "http://test")!, headers: [:], timeout: 5, session: URLSession(configuration: configuration))
        XCTExpectFailure("422 isn't the expected 201") {
            _ = api.post("/v1/transfers", json: [:], expect: 201)
        }
    }
}

/// Answers every request with `reply` and remembers what was sent.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var reply: (Int, String) = (200, "{}")
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: String?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            Self.lastBody = String(bytes: data, encoding: .utf8)
        } else {
            Self.lastBody = request.httpBody.flatMap { String(bytes: $0, encoding: .utf8) }
        }
        let headers = ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.0, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
