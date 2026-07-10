import Foundation

/// Allure severity levels.
public enum KassSeverity: String {
    case blocker, critical, normal, minor, trivial
}

/// Test metadata for the structured report (Allure labels & links). No-ops when
/// no reporter is configured.
public extension KassTestCase {

    func severity(_ severity: KassSeverity) { addLabel("severity", severity.rawValue) }
    func epic(_ value: String)    { addLabel("epic", value) }
    func feature(_ value: String) { addLabel("feature", value) }
    func story(_ value: String)   { addLabel("story", value) }
    func owner(_ value: String)   { addLabel("owner", value) }
    func tag(_ value: String)     { addLabel("tag", value) }

    /// Links this test to an issue tracker item.
    func issue(_ name: String, _ url: String) { addLink(name: name, url: url, type: "issue") }
    /// Links this test to a test-management-system item.
    func tms(_ name: String, _ url: String) { addLink(name: name, url: url, type: "tms") }

    private func addLabel(_ name: String, _ value: String) {
        startReportingIfNeeded()
        config.reporter?.addLabel(name, value: value)
    }

    private func addLink(name: String, url: String, type: String) {
        startReportingIfNeeded()
        config.reporter?.addLink(name: name, url: url, type: type)
    }
}
