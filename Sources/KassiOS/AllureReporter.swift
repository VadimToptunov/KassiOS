import Foundation

/// Writes [Allure 2](https://allurereport.org) result files — one
/// `<uuid>-result.json` per test, plus `<uuid>-attachment.*` for screenshots —
/// into a results directory. Point `allure generate` at that directory.
///
/// The directory is taken from `ALLURE_RESULTS_PATH` (set it in the UI test
/// target's scheme) or falls back to `<temp>/allure-results`. The absolute path
/// is logged at `testStarted` so it can be found and copied off the simulator.
///
/// `@unchecked Sendable`: `KassReporter` requires `Sendable`, and every mutable
/// stored property below is only ever touched while holding `lock` (an
/// `NSLock`), so concurrent access is serialized by the lock, not the compiler.
public final class AllureReporter: KassReporter, @unchecked Sendable {

    private let resultsDir: URL
    private let logger: KassLogger
    private let fileManager = FileManager.default
    private let lock = NSLock()

    private var root: StepNode?
    private var stack: [StepNode] = []
    private var testName = ""
    private var testFullName = ""
    private var extraLabels: [AllureLabel] = []
    private var links: [AllureLink] = []

    public init(resultsPath: String? = nil, logger: KassLogger = ConsoleKassLogger()) {
        let path = resultsPath
            ?? ProcessInfo.processInfo.environment["ALLURE_RESULTS_PATH"]
            ?? (NSTemporaryDirectory() as NSString).appendingPathComponent("allure-results")
        self.resultsDir = URL(fileURLWithPath: path, isDirectory: true)
        self.logger = logger
    }

    // MARK: - KassReporter

    public func testStarted(name: String, fullName: String) {
        lock.lock(); defer { lock.unlock() }
        testName = name
        testFullName = fullName
        extraLabels = []
        links = []
        let node = StepNode(name: name, start: Self.now())
        root = node
        stack = [node]
        try? fileManager.createDirectory(at: resultsDir, withIntermediateDirectories: true)
        logger.log("📊 Allure results → \(resultsDir.path)")
    }

    public func addLabel(_ name: String, value: String) {
        lock.lock(); defer { lock.unlock() }
        extraLabels.append(AllureLabel(name: name, value: value))
    }

    public func addLink(name: String, url: String, type: String) {
        lock.lock(); defer { lock.unlock() }
        links.append(AllureLink(name: name, url: url, type: type))
    }

    public func stepStarted(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        let node = StepNode(name: name, start: Self.now())
        stack.last?.steps.append(node)
        stack.append(node)
    }

    public func stepFinished(status: KassStepStatus, message: String?) {
        lock.lock(); defer { lock.unlock() }
        guard stack.count > 1, let node = stack.popLast() else { return }
        node.close(status: status, message: message, at: Self.now())
    }

    public func attach(name: String, type: String, data: Data) {
        lock.lock(); defer { lock.unlock() }
        let source = "\(UUID().uuidString)-attachment.\(Self.fileExtension(for: type))"
        do {
            try data.write(to: resultsDir.appendingPathComponent(source))
            stack.last?.attachments.append(AllureAttachment(name: name, source: source, type: type))
        } catch {
            logger.log("❌ Allure: could not write attachment '\(name)': \(error)")
        }
    }

    public func testFinished(status: KassStepStatus, message: String?) {
        lock.lock(); defer { lock.unlock() }
        guard let root = root else { return }
        let stop = Self.now()
        root.closeOpen(status: status, message: message, at: stop)

        let result = AllureResult(
            uuid: UUID().uuidString,
            historyId: testFullName,
            name: testName,
            fullName: testFullName,
            status: status.allure,
            statusDetails: message.map { AllureStatusDetails(message: $0, trace: nil) },
            stage: "finished",
            start: root.start,
            stop: stop,
            steps: root.steps.map { $0.asAllure },
            attachments: root.attachments,
            labels: [
                AllureLabel(name: "framework", value: "KassiOS"),
                AllureLabel(name: "language", value: "swift"),
                AllureLabel(name: "suite", value: Self.suite(from: testFullName))
            ] + extraLabels,
            links: links
        )
        write(result)
        self.root = nil
        self.stack = []
    }

    // MARK: - Helpers

    private func write(_ result: AllureResult) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(result)
            try data.write(to: resultsDir.appendingPathComponent("\(result.uuid)-result.json"))
        } catch {
            logger.log("❌ Allure: could not write result for '\(result.name)': \(error)")
        }
    }

    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private static func suite(from fullName: String) -> String {
        fullName.split(separator: ".").first.map(String.init) ?? fullName
    }

    private static func fileExtension(for type: String) -> String {
        switch type {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "text/plain": return "txt"
        case "application/json": return "json"
        default: return "dat"
        }
    }
}

// MARK: - Mutable tree, mapped to Codable on write

private final class StepNode {
    let name: String
    let start: Int64
    var stop: Int64 = 0
    var status: String = KassStepStatus.passed.allure
    var message: String?
    var steps: [StepNode] = []
    var attachments: [AllureAttachment] = []

    init(name: String, start: Int64) {
        self.name = name
        self.start = start
    }

    var isOpen: Bool { stop == 0 }

    func close(status: KassStepStatus, message: String?, at time: Int64) {
        stop = time
        self.status = status.allure
        self.message = message
    }

    /// Marks this node and any still-open descendants as finished. A hard
    /// failure can unwind past `stepFinished`, leaving steps open; those are
    /// attributed the test's terminal status.
    func closeOpen(status: KassStepStatus, message: String?, at time: Int64) {
        for child in steps { child.closeOpen(status: status, message: message, at: time) }
        if isOpen { close(status: status, message: message, at: time) }
    }

    var asAllure: AllureStep {
        AllureStep(
            name: name,
            status: status,
            statusDetails: message.map { AllureStatusDetails(message: $0, trace: nil) },
            stage: "finished",
            start: start,
            stop: stop,
            steps: steps.map { $0.asAllure },
            attachments: attachments
        )
    }
}

private extension KassStepStatus {
    var allure: String {
        switch self {
        case .passed: return "passed"
        case .failed: return "failed"
        }
    }
}

// MARK: - Allure 2 JSON model

private struct AllureResult: Codable {
    var uuid: String
    var historyId: String
    var name: String
    var fullName: String
    var status: String
    var statusDetails: AllureStatusDetails?
    var stage: String
    var start: Int64
    var stop: Int64
    var steps: [AllureStep]
    var attachments: [AllureAttachment]
    var labels: [AllureLabel]
    var links: [AllureLink]
}

private struct AllureLink: Codable {
    var name: String
    var url: String
    var type: String
}

private struct AllureStep: Codable {
    var name: String
    var status: String
    var statusDetails: AllureStatusDetails?
    var stage: String
    var start: Int64
    var stop: Int64
    var steps: [AllureStep]
    var attachments: [AllureAttachment]
}

private struct AllureStatusDetails: Codable {
    var message: String?
    var trace: String?
}

private struct AllureAttachment: Codable {
    var name: String
    var source: String
    var type: String
}

private struct AllureLabel: Codable {
    var name: String
    var value: String
}
