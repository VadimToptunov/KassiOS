import XCTest
@testable import KassiOS

final class KassDiagnosticTests: XCTestCase {

    private func sample() -> KassDiagnostic {
        KassDiagnostic(
            action: "tap", kind: "tap", element: "login button", expectedIdentifier: "signIn",
            error: "does not exist", file: "LoginTests.swift", line: 42,
            flakySafetyEnabled: true, timeout: 15,
            interceptors: ["KassRetryInterceptor", "KassSystemAlertInterceptor"],
            elementState: KassDiagnostic.ElementState(
                exists: false, hittable: nil, resolvedIdentifier: nil, label: nil, frame: nil
            )
        )
    }

    func test_jsonData_isStableAndRoundTrips() throws {
        let data = sample().jsonData()
        let json = String(data: data, encoding: .utf8) ?? ""
        // Keys an agent would read.
        XCTAssertTrue(json.contains("\"action\""))
        XCTAssertTrue(json.contains("\"interceptors\""))
        XCTAssertTrue(json.contains("\"elementState\""))
        // Sorted keys → deterministic ordering.
        XCTAssertLessThan(json.range(of: "\"action\"")!.lowerBound, json.range(of: "\"error\"")!.lowerBound)

        let decoded = try JSONDecoder().decode(KassDiagnostic.self, from: data)
        XCTAssertEqual(decoded.action, "tap")
        XCTAssertEqual(decoded.line, 42)
        XCTAssertEqual(decoded.expectedIdentifier, "signIn")
        XCTAssertEqual(decoded.interceptors, ["KassRetryInterceptor", "KassSystemAlertInterceptor"])
        XCTAssertFalse(decoded.elementState.exists)
    }
}
