import Foundation

actor JXARunner {
    struct Result: Sendable {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    private let fileManager = FileManager.default

    /// Runs a JXA script via `osascript -l JavaScript` and returns stdout.
    /// - Important: scripts must print JSON only to stdout.
    func runJSON(_ script: String, timeout: TimeInterval = 30) async throws -> String {
        let result = try await run(script, timeout: timeout)

        if result.exitCode != 0 {
            let err = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if err.contains("Not authorized to send Apple events") || err.contains("(-1743)") {
                throw AppError.notesAutomationDenied
            }
            throw AppError.notesScriptFailed(err.isEmpty ? "osascript failed with status \(result.exitCode)" : err)
        }

        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a JXA script and returns raw stdout/stderr/exit code (for diagnostics).
    func runDetailed(_ script: String, timeout: TimeInterval = 30) async throws -> Result {
        try await run(script, timeout: timeout)
    }

    private func run(_ script: String, timeout: TimeInterval) async throws -> Result {
        try Task.checkCancellation()

        let tempDir = fileManager.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("notes-mdbackup-\(UUID().uuidString).jxa")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startedAt = Date()

        return try await withTaskCancellationHandler {
            // Cancellation handler: terminate process quickly.
            if process.isRunning {
                process.terminate()
                usleep(100_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        } operation: {
            defer { try? fileManager.removeItem(at: scriptURL) }

            try process.run()

            let timeoutTask = Task {
                let ns = UInt64(timeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                if process.isRunning {
                    process.terminate()
                    usleep(150_000)
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                }
            }

            let exitCode: Int32 = try await withCheckedThrowingContinuation { cont in
                process.terminationHandler = { p in
                    cont.resume(returning: p.terminationStatus)
                }
            }

            timeoutTask.cancel()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let out = String(data: outData, encoding: .utf8) ?? ""
            let err = String(data: errData, encoding: .utf8) ?? ""

            // If we hit timeout, surface a clearer message.
            if Date().timeIntervalSince(startedAt) >= timeout, exitCode != 0, err.isEmpty {
                return Result(stdout: out, stderr: "Timed out after \(Int(timeout))s.", exitCode: exitCode)
            }

            try Task.checkCancellation()
            return Result(stdout: out, stderr: err, exitCode: exitCode)
        }
    }
}

