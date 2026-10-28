import Foundation

/// The version of the `kassios` tools. The release script checks it against the tag.
public enum KassiOSToolVersion {
    public static let current = "1.10.0"
}

/// What `kassios <args>` asked for.
public enum ToolCommand: Equatable, Sendable {
    /// Start the agent in the background and wait until it listens.
    case agentStart(port: UInt16, log: String?)
    case agentStop
    case agentStatus
    /// Run the agent in the foreground, as `kassios-agent` does.
    case agentRun(port: UInt16)
    /// Hand the arguments to a sibling tool (`kassios-mutants`, `kassios-lint`).
    case forward(tool: String, arguments: [String])
    case version
    case help

    public static let defaultPort: UInt16 = 8437

    public static let usage = """
    usage: kassios <command> [options]

      agent start [--port n] [--log file]   start kassios-agent in the background
      agent stop                            stop it
      agent status                          is it running?
      agent run [--port n]                  run it in the foreground
      mutants mutants.json [options]        run kassios-mutants (see kassios mutants --help)
      lint [paths] [--strict]               run kassios-lint on screen objects
      version                               print the tools' version
    """

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknown(String)
        case badPort(String)
        case missingValue(String)

        public var description: String {
            switch self {
            case .unknown(let command): return "unknown command '\(command)'"
            case .badPort(let value): return "--port takes a number from 1 to 65535, got '\(value)'"
            case .missingValue(let option): return "\(option) needs a value"
            }
        }
    }

    public static func parse(_ arguments: [String]) throws -> ToolCommand {
        guard let first = arguments.first else { return .help }
        let rest = Array(arguments.dropFirst())
        switch first {
        case "help", "-h", "--help": return .help
        case "version", "--version": return .version
        case "mutants": return .forward(tool: "kassios-mutants", arguments: rest)
        case "lint": return .forward(tool: "kassios-lint", arguments: rest)
        case "agent": return try parseAgent(rest)
        default: throw ParseError.unknown(first)
        }
    }

    static func parseAgent(_ arguments: [String]) throws -> ToolCommand {
        let sub = arguments.first ?? "run"
        let options = Array(arguments.dropFirst())
        switch sub {
        case "start":
            return .agentStart(port: try port(in: options), log: try value(of: "--log", in: options))
        case "stop": return .agentStop
        case "status": return .agentStatus
        case "run": return .agentRun(port: try port(in: options))
        default: throw ParseError.unknown("agent \(sub)")
        }
    }

    static func port(in options: [String]) throws -> UInt16 {
        guard let text = try value(of: "--port", in: options) else { return defaultPort }
        guard let port = UInt16(text), port > 0 else { throw ParseError.badPort(text) }
        return port
    }

    static func value(of option: String, in options: [String]) throws -> String? {
        guard let index = options.firstIndex(of: option) else { return nil }
        guard index + 1 < options.count else { throw ParseError.missingValue(option) }
        return options[index + 1]
    }
}

/// Finds the sibling executables the `kassios` front end runs.
public enum ToolLocator {
    /// `name` next to `executable` (symlinks resolved, as Homebrew installs them),
    /// then on `path`. Nil if neither has it.
    public static func find(
        _ name: String,
        besides executable: String,
        path: String?,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
        let beside = resolved.deletingLastPathComponent().appendingPathComponent(name).path
        if isExecutable(beside) { return beside }
        for directory in (path ?? "").split(separator: ":") {
            let candidate = String(directory) + "/" + name
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}

/// Where the background agent keeps its pid, and the discovery file it writes.
public struct AgentFiles: Sendable {
    public let pid: URL
    public let discovery: URL
    public let defaultLog: URL

    public init(home: URL) {
        pid = home.appendingPathComponent(".kassios-agent.pid")
        discovery = home.appendingPathComponent(".kassios-agent.json")
        defaultLog = home.appendingPathComponent("Library/Logs/kassios-agent.log")
    }

    /// The pid recorded by `agent start`, if the file holds one.
    public static func readPid(_ text: String?) -> Int32? {
        text.flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }.flatMap { $0 > 0 ? $0 : nil }
    }
}
