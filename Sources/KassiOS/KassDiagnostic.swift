import XCTest

/// A machine-readable snapshot of a failed element interaction — designed to be
/// **handed to a coding agent**, not parsed out of an `.xcresult` after the fact.
/// Attached as JSON when a `perform`-backed interaction or a scroll fails (and
/// mirrored into the structured report).
public struct KassDiagnostic: Codable, Sendable {

    /// A structured rectangle — fields, not a stringified `CGRect`, so an agent
    /// reads them directly.
    public struct Frame: Codable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    /// The resolved element's live state at the moment of failure.
    public struct ElementState: Codable, Sendable {
        public let exists: Bool
        public let hittable: Bool?
        public let resolvedIdentifier: String?
        public let label: String?
        public let frame: Frame?
    }

    public let action: String              // e.g. "tap", "typeText('hi')"
    public let kind: String                // the KassActionKind
    public let element: String             // the element's human description
    public let expectedIdentifier: String? // the id it was asked to resolve by
    public let error: String
    public let file: String
    public let line: UInt
    public let flakySafetyEnabled: Bool
    public let timeout: TimeInterval
    public let interceptors: [String]      // active interceptor type names
    public let elementState: ElementState

    /// Pretty, stable JSON — the artifact an agent reads.
    public func jsonData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

extension KassElement {

    /// Builds the failure diagnostic from the already-resolved `element` (pass the
    /// same snapshot used for the human-readable message so the two can't disagree
    /// if the app animates between resolves).
    func makeDiagnostic(
        action: String, kind: KassActionKind, error: Error, file: StaticString, line: UInt, element: XCUIElement
    ) -> KassDiagnostic {
        let exists = element.exists
        let frame = exists ? element.frame : nil
        return KassDiagnostic(
            action: action,
            kind: "\(kind)",
            element: description,
            expectedIdentifier: expectedIdentifier,
            error: "\(error)",
            file: "\(file)",
            line: line,
            flakySafetyEnabled: config.flakySafetyEnabled,
            timeout: config.timeout,
            interceptors: config.interceptors.map { String(describing: type(of: $0)) },
            elementState: KassDiagnostic.ElementState(
                exists: exists,
                hittable: exists ? element.isHittable : nil,
                resolvedIdentifier: exists ? element.identifier : nil,
                label: exists ? element.label : nil,
                frame: frame.map { KassDiagnostic.Frame(x: $0.origin.x, y: $0.origin.y, width: $0.width, height: $0.height) }
            )
        )
    }

    /// Attaches the diagnostic JSON to the `.xcresult` and the structured report.
    func attachDiagnostic(_ diagnostic: KassDiagnostic) {
        let data = diagnostic.jsonData()
        guard !data.isEmpty else {
            config.logger.log("⚠️ KassiOS: could not encode the diagnostic for '\(diagnostic.action)'")
            return
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "KassiOS diagnostic (JSON)"
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "🔎 KassiOS diagnostic — \(diagnostic.action)") { $0.add(attachment) }
        config.reporter?.attach(name: "KassiOS diagnostic", type: "application/json", data: data)
    }
}
