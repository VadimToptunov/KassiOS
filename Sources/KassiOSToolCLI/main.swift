import Foundation
#if canImport(Darwin)
import Darwin
#endif
import KassiOSTool

// kassios: one front end for the host-side tools. `kassios agent start` runs the
// agent in the background; `kassios mutants` and `kassios lint` hand over to the
// tools installed next to it.

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data("kassios: \(message)\n".utf8))
    exit(code)
}

let me = Bundle.main.executablePath ?? CommandLine.arguments[0]
let env = ProcessInfo.processInfo.environment
let files = AgentFiles(home: FileManager.default.homeDirectoryForCurrentUser)

func locate(_ tool: String) -> String {
    if let found = ToolLocator.find(tool, besides: me, path: env["PATH"]) { return found }
    fail("can't find \(tool) next to \(me) or on PATH. Install the tools with "
        + "`brew install vadimtoptunov/tap/kassios`, or build them from a KassiOS checkout.")
}

/// Replaces this process with `tool`, so its exit code and signals pass through.
func exec(_ tool: String, _ arguments: [String], environment: [String: String] = env) -> Never {
    let argv = ([tool] + arguments).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    execve(tool, argv, envp)
    fail("can't run \(tool): \(String(cString: strerror(errno)))")
}

func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

func recordedPid() -> Int32? {
    AgentFiles.readPid(try? String(contentsOf: files.pid, encoding: .utf8))
}

func listens(on port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    return withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
}

func startAgent(port: UInt16, log: String?) -> Never {
    if let pid = recordedPid(), isAlive(pid) {
        print("kassios-agent is already running (pid \(pid))")
        exit(0)
    }
    let agent = locate("kassios-agent")
    let logPath = log ?? files.defaultLog.path
    try? FileManager.default.createDirectory(
        at: URL(fileURLWithPath: logPath).deletingLastPathComponent(), withIntermediateDirectories: true)

    var childEnv = env
    childEnv["KASSIOS_AGENT_PORT"] = String(port)
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, logPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    posix_spawn_file_actions_adddup2(&actions, 1, 2)
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    // Its own session, so closing the terminal or ending the CI step doesn't take it down.
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
    let argv = [strdup(agent), nil]
    let envp = childEnv.map { strdup("\($0.key)=\($0.value)") } + [nil]
    var pid: pid_t = 0
    let status = posix_spawn(&pid, agent, &actions, &attributes, argv, envp)
    guard status == 0 else { fail("can't start \(agent): \(String(cString: strerror(status)))") }
    try? String(pid).write(to: files.pid, atomically: true, encoding: .utf8)

    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        if listens(on: port) {
            print("kassios-agent is running on 127.0.0.1:\(port) (pid \(pid), log \(logPath))")
            exit(0)
        }
        guard isAlive(pid) else { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    let output = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
    fail("kassios-agent didn't start listening on \(port):\n\(output)", code: 1)
}

func stopAgent() -> Never {
    guard let pid = recordedPid(), isAlive(pid) else {
        try? FileManager.default.removeItem(at: files.pid)
        print("kassios-agent isn't running")
        exit(0)
    }
    kill(pid, SIGTERM)
    let deadline = Date().addingTimeInterval(5)
    while isAlive(pid), Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    if isAlive(pid) { kill(pid, SIGKILL) }
    try? FileManager.default.removeItem(at: files.pid)
    try? FileManager.default.removeItem(at: files.discovery)
    print("kassios-agent stopped")
    exit(0)
}

let command: ToolCommand
do {
    command = try ToolCommand.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    fail("\(error)\n\n\(ToolCommand.usage)")
}

switch command {
case .help:
    print(ToolCommand.usage)
case .version:
    print(KassiOSToolVersion.current)
case .agentStart(let port, let log):
    startAgent(port: port, log: log)
case .agentStop:
    stopAgent()
case .agentStatus:
    if let pid = recordedPid(), isAlive(pid) {
        print("kassios-agent is running (pid \(pid))")
    } else {
        print("kassios-agent isn't running")
        exit(1)
    }
case .agentRun(let port):
    var childEnv = env
    childEnv["KASSIOS_AGENT_PORT"] = String(port)
    exec(locate("kassios-agent"), [], environment: childEnv)
case .forward(let tool, let arguments):
    exec(locate(tool), arguments)
}
