import Foundation

actor NotesScriptExecutor {
    private let fileManager = FileManager.default

    /// Notes scripting can be fragile under concurrency; keep a small delay between calls.
    private var lastCall: Date = .distantPast
    private let minimumSpacing: TimeInterval = 0.05

    func runJXA(_ source: String) async throws -> String {
        try await rateLimit()

        let tempDir = fileManager.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("notes-mdbackup-\(UUID().uuidString).jxa")
        try source.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: scriptURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", scriptURL.path]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            if err.contains("Not authorized to send Apple events") || err.contains("(-1743)") {
                throw AppError.notesAutomationDenied
            }
            throw AppError.notesScriptFailed(err.isEmpty ? "osascript failed with status \(process.terminationStatus)" : err)
        }

        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func runAppleScript(_ source: String) async throws -> String {
        try await rateLimit()

        func executeOnce() throws -> String {
            var errorDict: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw AppError.notesScriptFailed("Couldn’t compile AppleScript.")
            }

            let result = script.executeAndReturnError(&errorDict)
            if let errorDict {
                let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                let number = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
                if number == -1743 {
                    throw AppError.notesAutomationDenied
                }
                throw AppError.notesScriptFailed("\(message) (\(number))")
            }
            return result.stringValue ?? ""
        }

        var lastError: Error?
        for attempt in 1...10 {
            do {
                return try executeOnce()
            } catch is CancellationError {
                throw CancellationError()
            } catch let AppError.notesScriptFailed(details) {
                lastError = AppError.notesScriptFailed(details)
                if details.contains("(-600)") {
                    // Notes isn't ready yet; wait, ensure it's running, then retry.
                    try await NotesAppLauncher.ensureRunning(timeout: 10.0)
                    let backoffMs = UInt64(min(2000, 150 * attempt))
                    try await Task.sleep(nanoseconds: backoffMs * 1_000_000)
                    continue
                }
                throw AppError.notesScriptFailed(details)
            } catch {
                lastError = error
                throw error
            }
        }
        throw lastError ?? AppError.notesScriptFailed("Notes scripting failed.")
    }

    private func rateLimit() async throws {
        let elapsed = Date().timeIntervalSince(lastCall)
        if elapsed < minimumSpacing {
            try await Task.sleep(nanoseconds: UInt64((minimumSpacing - elapsed) * 1_000_000_000))
        }
        lastCall = Date()
        try Task.checkCancellation()
    }
}

