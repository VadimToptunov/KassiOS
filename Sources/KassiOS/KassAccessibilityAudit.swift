import XCTest

/// How a failed accessibility-identifier audit is reported.
public enum KassAuditSeverity: Sendable {
    /// Log it and attach the report — but let the test pass.
    case warn
    /// `XCTFail` the test.
    case fail
}

/// One element the audit flagged: a hittable, interactive element with no
/// accessibility identifier (so a test can only reach it by fragile label text).
public struct KassA11yFinding: Sendable, Equatable {
    public let elementType: String
    public let label: String
}

enum KassAccessibilityAudit {

    /// The interactive element types worth an identifier. Static, non-interactive
    /// text/images are excluded — as is `.link`, which is dominated by WKWebView
    /// content that can't carry a settable identifier (add it explicitly via
    /// `types:` if your native links need auditing).
    static let interactiveTypes: [XCUIElement.ElementType] = [
        .button, .textField, .secureTextField, .searchField, .switch,
        .slider, .stepper, .segmentedControl, .picker, .menuButton
    ]

    /// The pure rule — factored out so it's unit-testable without a simulator.
    /// An element is flagged when it's hittable, has no identifier, and its label
    /// isn't allowlisted (decorative / system-provided elements).
    static func isUnidentified(
        identifier: String, isHittable: Bool, label: String, allowlist: Set<String>
    ) -> Bool {
        isHittable && identifier.isEmpty && !allowlist.contains(label)
    }

    @MainActor
    static func findings(
        in app: XCUIApplication,
        types: [XCUIElement.ElementType],
        allowingLabels: [String]
    ) -> [KassA11yFinding] {
        let allow = Set(allowingLabels)
        var out: [KassA11yFinding] = []
        for type in types {
            for element in app.descendants(matching: type).allElementsBoundByAccessibilityElement
            where isUnidentified(identifier: element.identifier, isHittable: element.isHittable,
                                 label: element.label, allowlist: allow) {
                out.append(KassA11yFinding(elementType: KassScreen.typeName(type), label: element.label))
            }
        }
        return out
    }
}

public extension KassTestCase {

    /// Audits the **current screen** for hittable, interactive elements missing an
    /// accessibility identifier — the ones a suite can only reach by brittle label
    /// text. Each finding is logged, attached to the report (with a screenshot),
    /// and — at `.fail` severity — fails the test. Returns the findings so callers
    /// can assert on them.
    ///
    /// - Parameters:
    ///   - types: element types to check (default: the interactive controls).
    ///   - allowingLabels: labels legitimately without an id (decorative/system).
    ///   - severity: `.fail` (default) or `.warn`.
    @discardableResult
    func auditAccessibilityIdentifiers(
        types: [XCUIElement.ElementType]? = nil,
        allowingLabels: [String] = [],
        severity: KassAuditSeverity = .fail,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [KassA11yFinding] {
        // Settle first, like every other read path, so we don't scan mid-animation.
        config.synchronizer.waitForIdle(timeout: config.timeout)
        let findings = KassAccessibilityAudit.findings(
            in: app, types: types ?? KassAccessibilityAudit.interactiveTypes, allowingLabels: allowingLabels
        )
        guard !findings.isEmpty else { return [] }

        let report = findings.map { "• \($0.elementType) '\($0.label)'" }.joined(separator: "\n")
        let message = "\(findings.count) hittable element(s) without an accessibility identifier:\n\(report)"
        config.logger.log("⚠️ KassiOS accessibility audit — \(message)")
        device.attachText("Accessibility audit", message)
        device.screenshot("Accessibility audit")

        if severity == .fail {
            XCTFail("KassiOS accessibility audit: \(message)", file: file, line: line)
        }
        return findings
    }
}
