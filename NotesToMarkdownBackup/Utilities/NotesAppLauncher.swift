import AppKit
import Foundation

enum NotesAppLauncher {
    static let notesBundleID = "com.apple.Notes"

    static func isNotesRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleID).isEmpty
    }

    @MainActor
    static func launchNotesIfNeeded() async throws {
        if isNotesRunning() { return }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: notesBundleID) else {
            throw AppError.notesNotRunning
        }
        let config = NSWorkspace.OpenConfiguration()
        // Empirically, Notes sometimes won't accept Apple Events until it has fully launched
        // (and occasionally until it's been activated once) on newer macOS versions.
        config.activates = true
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: ())
                }
            }
        }
    }

    @MainActor
    static func ensureRunning(timeout: TimeInterval = 20.0) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        // Try launching and wait for process.
        if !isNotesRunning() {
            try await launchNotesIfNeeded()
        }

        // Wait for process to exist.
        while Date() < deadline {
            try Task.checkCancellation()
            if isNotesRunning() { break }
            try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        }

        if !isNotesRunning() {
            throw AppError.notesNotRunning
        }

        // Wait for Notes to finish launching.
        while Date() < deadline {
            try Task.checkCancellation()
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: notesBundleID).first,
               app.isFinishedLaunching {
                // Some systems behave better if Notes is activated at least once.
                if !app.isActive {
                    _ = app.activate(options: [.activateIgnoringOtherApps])
                }
                break
            }
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        // Notes can be "running" but not yet ready to accept Apple Events.
        // Probe until it responds to a trivial AppleScript.
        var lastProbe: (number: Int, message: String)? = nil
        while Date() < deadline {
            try Task.checkCancellation()
            let probe = appleEventsProbe()
            if probe.ok { return }
            if let err = probe.error, err.number == -1743 {
                throw AppError.notesAutomationDenied
            }
            lastProbe = probe.error
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        if let lastProbe {
            throw AppError.notesScriptFailed("Notes is running but not responding to Apple Events yet: \(lastProbe.message) (\(lastProbe.number)).")
        }
        throw AppError.notesNotRunning
    }

    private static func appleEventsProbe() -> (ok: Bool, error: (number: Int, message: String)?) {
        var errorDict: NSDictionary?
        // Use application id to avoid name-resolution timing issues during launch.
        let script = NSAppleScript(source: "tell application id \"com.apple.Notes\" to get count of accounts")
        _ = script?.executeAndReturnError(&errorDict)
        if let errorDict {
            let number = (errorDict[NSAppleScript.errorNumber] as? Int) ?? 0
            let message = (errorDict[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            // -600 means not ready/running; keep waiting.
            if number == -600 {
                return (false, (number, message))
            }
            // -1743 means permission denied; caller should surface Automation guidance.
            if number == -1743 {
                return (false, (number, message))
            }
            // Any other error means Notes is reachable (permission may still be denied).
            return (true, (number, message))
        }
        return (true, nil)
    }
}

