import Foundation
import PackagePlugin

@main
struct KassiOSLintCommand: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) throws {
        let tool = try context.tool(named: "kassios-lint")
        // Default to the package root when the caller passes only flags (e.g.
        // `swift package kassios-lint --strict`) and no path to lint.
        let hasPath = arguments.contains { !$0.hasPrefix("-") }
        let toolArguments = hasPath ? arguments : arguments + [context.package.directoryURL.path()]

        let process = Process()
        process.executableURL = tool.url
        process.arguments = toolArguments
        process.currentDirectoryURL = context.package.directoryURL
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            Diagnostics.error("kassios-lint reported issues")
        }
    }
}
