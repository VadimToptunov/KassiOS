import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Manages `simctl io recordVideo` processes, one per simulator `udid`.
///
/// `recordVideo` runs until interrupted (SIGINT), so unlike every other
/// `AgentCommand` this isn't a one-shot `xcrun` invocation the generic
/// ``SimctlRunner`` can wait on — the agent has to hold the process open
/// between the `startRecording` and `stopRecording` requests. This is the
/// only piece of state the otherwise-stateless agent keeps.
final class RecordingManager: @unchecked Sendable {
    private struct Recording {
        let process: Process
        let url: URL
    }

    private let lock = NSLock()
    private var recordings: [String: Recording] = [:]

    /// Starts a fresh recording for `udid`, discarding any recording already in
    /// progress for it (best-effort — the agent posture is stateless-first, so
    /// a stray earlier recording never wedges the next one).
    func start(udid: String) -> AgentResponse {
        interruptAndDiscard(udid: udid)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kassios-rec-\(UUID().uuidString).mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", url.path]

        do {
            try process.run()
        } catch {
            return AgentResponse(ok: false, error: "failed to launch recordVideo: \(error)")
        }

        lock.lock()
        recordings[udid] = Recording(process: process, url: url)
        lock.unlock()
        return AgentResponse(ok: true)
    }

    /// Stops the recording for `udid` (if any), returning its bytes
    /// base64-encoded in `AgentResponse.data`. Best-effort throughout: a
    /// missing recording, or one whose file can't be read back, still returns
    /// `ok: true` with `data: nil` rather than failing the request.
    func stop(udid: String) -> AgentResponse {
        lock.lock()
        let recording = recordings.removeValue(forKey: udid)
        lock.unlock()

        guard let recording = recording else { return AgentResponse(ok: true, data: nil) }

        finalize(recording.process)

        defer { try? FileManager.default.removeItem(at: recording.url) }
        guard let bytes = try? Data(contentsOf: recording.url) else { return AgentResponse(ok: true, data: nil) }
        return AgentResponse(ok: true, data: bytes.base64EncodedString())
    }

    /// Interrupts and drops any in-flight recording for `udid` without
    /// bothering to read its bytes back.
    private func interruptAndDiscard(udid: String) {
        lock.lock()
        let existing = recordings.removeValue(forKey: udid)
        lock.unlock()
        guard let existing = existing else { return }
        finalize(existing.process)
        try? FileManager.default.removeItem(at: existing.url)
    }

    /// SIGINT is how `recordVideo` finalizes the mp4, but the agent's serve loop
    /// is single-threaded — a `recordVideo` that ignores SIGINT (e.g. the
    /// simulator was shut down under it) must never wedge every later command.
    /// Wait a bounded window for a clean finalize, then SIGKILL as a backstop.
    private func finalize(_ process: Process) {
        process.interrupt()
        let deadline = Date().addingTimeInterval(10)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}
