import XCTest
@testable import KassiOSStubs

final class KassStubMatchingTests: XCTestCase {

    private func def(_ urlContains: String, method: String? = nil, offline: Bool = false) -> KassStubDefinition {
        KassStubDefinition(
            urlContains: urlContains, method: method, statusCode: 200,
            headers: [:], body: "{}", failWithOffline: offline
        )
    }

    override func tearDown() {
        KassStubURLProtocol.stubs = []
        super.tearDown()
    }

    func test_match_byURLSubstring() {
        KassStubURLProtocol.stubs = [def("/user")]
        XCTAssertNotNil(KassStubURLProtocol.match(URLRequest(url: URL(string: "https://api.example.com/user/42")!)))
        XCTAssertNil(KassStubURLProtocol.match(URLRequest(url: URL(string: "https://api.example.com/orders")!)))
    }

    func test_match_narrowsByMethod() {
        KassStubURLProtocol.stubs = [def("/user", method: "POST")]
        var post = URLRequest(url: URL(string: "https://x/user")!); post.httpMethod = "POST"
        var get = URLRequest(url: URL(string: "https://x/user")!); get.httpMethod = "GET"
        XCTAssertNotNil(KassStubURLProtocol.match(post))
        XCTAssertNil(KassStubURLProtocol.match(get))
    }

    func test_offlineStub_withEmptySubstring_matchesEverything() {
        KassStubURLProtocol.stubs = [def("", offline: true)]
        XCTAssertNotNil(KassStubURLProtocol.match(URLRequest(url: URL(string: "https://anything/at/all")!)))
    }

    func test_canInit_reflectsMatch() {
        KassStubURLProtocol.stubs = [def("/user")]
        XCTAssertTrue(KassStubURLProtocol.canInit(with: URLRequest(url: URL(string: "https://x/user")!)))
        XCTAssertFalse(KassStubURLProtocol.canInit(with: URLRequest(url: URL(string: "https://x/nope")!)))
    }

    func test_decodesTestSideWireShape() throws {
        // The exact JSON the test-side KassStub.json(...) encodes.
        let json = #"[{"urlContains":"/user","statusCode":200,"headers":{},"body":"{}","failWithOffline":false}]"#
        let stubs = try JSONDecoder().decode([KassStubDefinition].self, from: Data(json.utf8))
        XCTAssertEqual(stubs.first?.urlContains, "/user")
        XCTAssertEqual(stubs.first?.statusCode, 200)
    }
}
