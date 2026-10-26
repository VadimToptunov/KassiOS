import XCTest

/// A small, synchronous HTTP client for arranging state through an app's API
/// before the UI test drives the screen: "create the transfer via the API, check
/// it in the history via the UI" instead of tapping through the whole flow first.
///
/// Each call is recorded as an activity in the test report ("POST /v1/transfers →
/// 201") with the request and response bodies attached. Foundation only.
///
/// ```swift
/// let api = KassHTTP(baseURL: URL(string: "http://localhost:8080")!,
///                    headers: ["Authorization": "Bearer \(token)"])
/// api.post("/v1/transfers", json: ["from": "EUR", "amount": "100.00"], expect: 201)
/// ```
@MainActor
public struct KassHTTP {

    /// One response. `status` is 0 when the request never got an answer.
    public struct Response: Sendable {
        public let status: Int
        public let headers: [String: String]
        public let body: Data

        /// The body as UTF-8 text.
        public var text: String { String(bytes: body, encoding: .utf8) ?? "" }

        /// The body parsed as JSON (object, array or scalar), or nil if it isn't JSON.
        public var json: Any? { try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) }

        /// A top-level string or number field of a JSON object body, as text.
        public subscript(field: String) -> String? {
            guard let object = json as? [String: Any], let value = object[field] else { return nil }
            if let string = value as? String { return string }
            return value is NSNull ? nil : "\(value)"
        }
    }

    public var baseURL: URL
    /// Sent with every request; per-call headers override these.
    public var headers: [String: String]
    public var timeout: TimeInterval
    let session: URLSession

    public init(baseURL: URL, headers: [String: String] = [:], timeout: TimeInterval = 15) {
        self.init(baseURL: baseURL, headers: headers, timeout: timeout, session: URLSession(configuration: .ephemeral))
    }

    init(baseURL: URL, headers: [String: String], timeout: TimeInterval, session: URLSession) {
        self.baseURL = baseURL
        self.headers = headers
        self.timeout = timeout
        self.session = session
    }

    /// Sends one request. `json` is serialized as the body (with a JSON content
    /// type). With `expect`, a different status fails the test (the response is
    /// still returned). A transport failure fails the test and returns status 0.
    @discardableResult
    public func request(
        _ method: String,
        _ path: String,
        json: Any? = nil,
        headers extra: [String: String] = [:],
        expect: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Response {
        var request = URLRequest(url: Self.url(baseURL, path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers.merging(extra, uniquingKeysWith: { _, new in new }) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed, .sortedKeys])
        }
        let outcome = Self.send(request, session: session, timeout: timeout)
        let response = outcome.response
        let title = "\(method) \(path) → \(response.status == 0 ? "no response" : String(response.status))"
        XCTContext.runActivity(named: title) { activity in
            if let body = request.httpBody {
                activity.add(XCTAttachment(data: body, uniformTypeIdentifier: "public.json"))
            }
            if !response.body.isEmpty {
                activity.add(XCTAttachment(string: response.text))
            }
        }
        if let error = outcome.error {
            XCTFail("KassiOS: \(method) \(path) got no response: \(error)", file: file, line: line)
        } else if let expect, response.status != expect {
            let body = response.text.prefix(300)
            XCTFail("KassiOS: \(method) \(path) answered \(response.status), expected \(expect): \(body)", file: file, line: line)
        }
        return response
    }

    @discardableResult
    public func get(_ path: String, headers: [String: String] = [:], expect: Int? = nil,
                    file: StaticString = #filePath, line: UInt = #line) -> Response {
        request("GET", path, headers: headers, expect: expect, file: file, line: line)
    }

    @discardableResult
    public func post(_ path: String, json: Any? = nil, headers: [String: String] = [:], expect: Int? = nil,
                     file: StaticString = #filePath, line: UInt = #line) -> Response {
        request("POST", path, json: json, headers: headers, expect: expect, file: file, line: line)
    }

    @discardableResult
    public func put(_ path: String, json: Any? = nil, headers: [String: String] = [:], expect: Int? = nil,
                    file: StaticString = #filePath, line: UInt = #line) -> Response {
        request("PUT", path, json: json, headers: headers, expect: expect, file: file, line: line)
    }

    @discardableResult
    public func delete(_ path: String, headers: [String: String] = [:], expect: Int? = nil,
                       file: StaticString = #filePath, line: UInt = #line) -> Response {
        request("DELETE", path, headers: headers, expect: expect, file: file, line: line)
    }

    /// `path` may carry a query ("/v1/transactions?limit=5"); it's appended to the base as is.
    nonisolated static func url(_ base: URL, _ path: String) -> URL {
        let root = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        let tail = path.hasPrefix("/") ? path : "/" + path
        return URL(string: root + tail) ?? base
    }

    private final class Box: @unchecked Sendable {
        var response = Response(status: 0, headers: [:], body: Data())
        var error: Error?
    }

    private static func send(_ request: URLRequest, session: URLSession, timeout: TimeInterval) -> (response: Response, error: Error?) {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        session.dataTask(with: request) { data, urlResponse, error in
            if let http = urlResponse as? HTTPURLResponse {
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields { headers["\(key)"] = "\(value)" }
                box.response = Response(status: http.statusCode, headers: headers, body: data ?? Data())
            }
            box.error = error
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + timeout + 1) == .timedOut {
            return (box.response, URLError(.timedOut))
        }
        return (box.response, box.error)
    }
}
