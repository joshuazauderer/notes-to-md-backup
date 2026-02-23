import Foundation
import OSAKit

/// Executes JXA (JavaScript for Automation) *in-process* using OSAKit.
///
/// Why this exists:
/// - In a sandboxed app, spawning `/usr/bin/osascript` may run under the sandbox profile
///   and can yield empty results (or inconsistent behavior) when automating other apps.
/// - Running JXA in-process makes Apple Events originate from this app binary, which is
///   the expected path for Automation permission prompts and App Sandbox entitlements.
actor JXAOSAKitRunner {
    struct Result: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    func runJSON(_ script: String, timeout: TimeInterval = 30) async throws -> String {
        let result = try await runDetailed(script, timeout: timeout)
        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if err.contains("Not authorized to send Apple events") || err.contains("(-1743)") {
                throw AppError.notesAutomationDenied
            }
            throw AppError.notesScriptFailed(err.isEmpty ? "JXA execution failed." : err)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func runDetailed(_ script: String, timeout: TimeInterval = 30) async throws -> Result {
        try await withThrowingTaskGroup(of: Result.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try Self.executeSync(script)
            }
            group.addTask {
                let ns = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw AppError.notesScriptFailed("Timed out after \(Int(timeout))s.")
            }

            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private static func executeSync(_ source: String) throws -> Result {
        guard let lang = OSALanguage(forName: "JavaScript") else {
            return Result(stdout: "", stderr: "OSAKit JavaScript language unavailable.", exitCode: 1)
        }

        let script = OSAScript(source: source, language: lang)
        var errorInfo: NSDictionary?
        let desc = script.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let msg = (errorInfo["OSAScriptErrorMessage"] as? String)
                ?? (errorInfo["NSLocalizedDescription"] as? String)
                ?? errorInfo.description
            return Result(stdout: "", stderr: msg, exitCode: 1)
        }

        let out = desc?.stringValue ?? ""
        return Result(stdout: out, stderr: "", exitCode: 0)
    }
}

