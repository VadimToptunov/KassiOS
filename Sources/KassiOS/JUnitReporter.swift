import Foundation

/// Writes JUnit XML — one `<uuid>.xml` per test — into a directory most CI
/// systems understand (Jenkins, GitLab, Azure, …). Complements `AllureReporter`
/// via the same `KassReporter` protocol.
///
/// The directory comes from `$KASS_JUNIT_PATH`, else a `<temp>/junit-results`
/// folder. Each file holds one `<testsuite>` with one `<testcase>`; point your
/// CI's JUnit collector at the folder to merge them.
public final class JUnitReporter: KassReporter {

    private let resultsDir: URL
    private let logger: KassLogger
    private let lock = NSLock()

    private var testName = ""
    private var suite = ""
    private var startMillis: Int64 = 0

    public init(resultsPath: String? = nil, logger: KassLogger = ConsoleKassLogger()) {
        let path = resultsPath
            ?? ProcessInfo.processInfo.environment["KASS_JUNIT_PATH"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("junit-results")
        self.resultsDir = URL(fileURLWithPath: path, isDirectory: true)
        self.logger = logger
    }

    public func testStarted(name: String, fullName: String) {
        lock.lock(); defer { lock.unlock() }
        testName = name
        suite = fullName.split(separator: ".").first.map(String.init) ?? fullName
        startMillis = Self.now()
        try? FileManager.default.createDirectory(at: resultsDir, withIntermediateDirectories: true)
    }

    public func stepStarted(_ name: String) {}
    public func stepFinished(status: KassStepStatus, message: String?) {}
    public func attach(name: String, type: String, data: Data) {}

    public func testFinished(status: KassStepStatus, message: String?) {
        lock.lock(); defer { lock.unlock() }
        let seconds = String(format: "%.3f", Double(Self.now() - startMillis) / 1000.0)
        let failed = status == .failed
        let failureXML = failed
            ? "\n    <failure message=\"\(Self.escape(message ?? "test failed"))\"/>\n  "
            : ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuite name="\(Self.escape(suite))" tests="1" failures="\(failed ? 1 : 0)" time="\(seconds)">
          <testcase classname="\(Self.escape(suite))" name="\(Self.escape(testName))" time="\(seconds)">\(failureXML)</testcase>
        </testsuite>
        """
        let file = resultsDir.appendingPathComponent("\(suite).\(testName).\(UUID().uuidString).xml")
        do {
            try Data(xml.utf8).write(to: file)
        } catch {
            logger.log("❌ JUnit: could not write \(file.lastPathComponent): \(error)")
        }
    }

    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
