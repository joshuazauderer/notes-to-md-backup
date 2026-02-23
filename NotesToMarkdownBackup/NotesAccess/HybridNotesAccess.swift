import Foundation

/// Picks a working Notes backend at runtime.
///
/// - Primary: JXA-based `AppleNotesAccess`
/// - Fallback: in-process AppleScript `AppleScriptNotesAccess` when JXA returns an empty library
///
/// We keep the same backend for the entire run to avoid mixing folder/note IDs.
final class HybridNotesAccess: NotesProviding {
    private enum Backend {
        case jxa
        case appleScript
    }

    private let jxa = AppleNotesAccess()
    private let appleScript = AppleScriptNotesAccess()
    private let lock = NSLock()
    private var chosen: Backend?

    func fetchLibrary() async throws -> NotesLibrary {
        if let chosen = getChosen() {
            switch chosen {
            case .jxa: return try await jxa.fetchLibrary()
            case .appleScript: return try await appleScript.fetchLibrary()
            }
        }

        // Try JXA first.
        do {
            let lib = try await jxa.fetchLibrary()
            if lib.accounts.isEmpty || lib.allFolders.isEmpty {
                // Treat as failure and fallback.
                let fallbackLib = try await appleScript.fetchLibrary()
                setChosen(.appleScript)
                return fallbackLib
            }
            setChosen(.jxa)
            return lib
        } catch {
            // If JXA fails for any reason, try AppleScript.
            let fallbackLib = try await appleScript.fetchLibrary()
            setChosen(.appleScript)
            return fallbackLib
        }
    }

    func listNoteStubs(folderID: String) async throws -> [NotesNoteStub] {
        switch getChosen() ?? .jxa {
        case .jxa:
            return try await jxa.listNoteStubs(folderID: folderID)
        case .appleScript:
            return try await appleScript.listNoteStubs(folderID: folderID)
        }
    }

    func fetchNoteContent(noteID: String, tempWorkspace: URL) async throws -> NotesNoteContent {
        switch getChosen() ?? .jxa {
        case .jxa:
            return try await jxa.fetchNoteContent(noteID: noteID, tempWorkspace: tempWorkspace)
        case .appleScript:
            return try await appleScript.fetchNoteContent(noteID: noteID, tempWorkspace: tempWorkspace)
        }
    }

    func exportAttachments(noteID: String, destinationDirectory: URL, noteSlug: String) async -> AttachmentExportResult {
        switch getChosen() ?? .jxa {
        case .jxa:
            return await jxa.exportAttachments(noteID: noteID, destinationDirectory: destinationDirectory, noteSlug: noteSlug)
        case .appleScript:
            return await appleScript.exportAttachments(noteID: noteID, destinationDirectory: destinationDirectory, noteSlug: noteSlug)
        }
    }

    private func getChosen() -> Backend? {
        lock.lock()
        defer { lock.unlock() }
        return chosen
    }

    private func setChosen(_ b: Backend) {
        lock.lock()
        chosen = b
        lock.unlock()
    }
}

