import Foundation

struct AppleNotesAccess: NotesProviding {
    // JXA-only extraction layer. Scripts must print JSON only to stdout.
    //
    // In some sandbox/debug setups, in-process OSAKit JavaScript can yield empty enumerations.
    // We keep a process fallback to restore "known-good" behavior when it works.
    private let osaKitRunner = JXAOSAKitRunner()
    private let processRunner = JXARunner()

    func fetchLibrary() async throws -> NotesLibrary {
        let json = try await runPreferredJSON(JXAScripts.listAccountsAndFolders, timeout: 60, treatEmptyAsFailure: true)
        let data = Data(json.utf8)
        let decoded = try JSONDecoder.notes.decode(JXAAccountsAndFoldersResponse.self, from: data)

        // Populate note counts (UI displays counts per folder). This is done as a separate JXA call
        // so the accounts/folders JSON shape stays stable and the work can be retried independently.
        let countsJSON = try await runPreferredJSON(JXAScripts.listFolderNoteCounts, timeout: 120, treatEmptyAsFailure: false)
        let countsData = Data(countsJSON.utf8)
        let countsDecoded = try JSONDecoder.notes.decode(JXAFolderNoteCountsResponse.self, from: countsData)
        let countsMap = Dictionary(uniqueKeysWithValues: countsDecoded.counts.map { ($0.folderId, $0.noteCount) })

        return decoded.toLibraryModel(noteCountsByFolderID: countsMap)
    }

    func listNoteStubs(folderID: String) async throws -> [NotesNoteStub] {
        let script = String(format: JXAScripts.listNotesInFolderTemplate, folderID.jsQuoted)
        let json = try await runPreferredJSON(script, timeout: 60, treatEmptyAsFailure: false)
        let data = Data(json.utf8)
        let decoded = try JSONDecoder.notes.decode(JXANotesInFolderResponse.self, from: data)
        return decoded.notes.map { header in
            NotesNoteStub(
                id: header.id,
                title: header.title.isEmpty ? "Untitled" : header.title,
                createdAt: JXADates.parse(header.createdAt),
                modifiedAt: JXADates.parse(header.modifiedAt)
            )
        }
    }

    func fetchNoteContent(noteID: String, tempWorkspace: URL) async throws -> NotesNoteContent {
        _ = tempWorkspace // retained for protocol compatibility; JXA returns content directly
        let script = String(format: JXAScripts.getNoteDetailTemplate, noteID.jsQuoted)
        let json = try await runPreferredJSON(script, timeout: 60, treatEmptyAsFailure: false)
        let data = Data(json.utf8)
        let decoded = try JSONDecoder.notes.decode(JXANoteDetailResponse.self, from: data)

        let title = decoded.title.isEmpty ? "Untitled" : decoded.title
        let plain = decoded.plain ?? ""
        let html = decoded.html.flatMap { $0.isEmpty ? nil : $0 }

        // If Notes returns neither html nor plain, treat as failure so exporter can record it.
        if (html == nil) && plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AppError.notesScriptFailed("Note returned empty content.")
        }

        return NotesNoteContent(
            noteID: decoded.id,
            title: title,
            createdAt: JXADates.parse(decoded.createdAt),
            modifiedAt: JXADates.parse(decoded.modifiedAt),
            plainText: plain,
            rtfdPackageURL: nil,
            html: html
        )
    }

    func exportAttachments(noteID: String, destinationDirectory: URL, noteSlug: String) async -> AttachmentExportResult {
        let script = String(
            format: JXAScripts.exportAttachmentsTemplate,
            noteID.jsQuoted,
            destinationDirectory.path.jsQuoted,
            noteSlug.jsQuoted
        )

        do {
            let json = try await runPreferredJSON(script, timeout: 60, treatEmptyAsFailure: false)
            let data = Data(json.utf8)
            let decoded = try JSONDecoder.notes.decode(JXAAttachmentExportResponse.self, from: data)
            return AttachmentExportResult(decoded)
        } catch is CancellationError {
            return AttachmentExportResult(noteId: noteID, exports: [], errors: [])
        } catch {
            return AttachmentExportResult(
                noteId: noteID,
                exports: [],
                errors: [.init(message: UserPresentableError(error).message, code: "swift_error")]
            )
        }
    }
}

private extension AppleNotesAccess {
    func runPreferredJSON(_ script: String, timeout: TimeInterval, treatEmptyAsFailure: Bool) async throws -> String {
        // Many Notes scripting calls fail with "Application isn't running" unless Notes is started.
        // Ensure it is running before we begin scripting.
        try await NotesAppLauncher.ensureRunning(timeout: 30.0)

        let preferred = await NotesJXARuntime.shared.preferredRunner()
        if let preferred {
            switch preferred {
            case .osaKit:
                return try await runOSAKitFirst(script, timeout: timeout, treatEmptyAsFailure: treatEmptyAsFailure)
            case .process:
                return try await runProcessFirst(script, timeout: timeout, treatEmptyAsFailure: treatEmptyAsFailure)
            }
        }
        // Default: try OSAKit first, then process.
        return try await runOSAKitFirst(script, timeout: timeout, treatEmptyAsFailure: treatEmptyAsFailure)
    }

    func runOSAKitFirst(_ script: String, timeout: TimeInterval, treatEmptyAsFailure: Bool) async throws -> String {
        do {
            let json = try await runWithRetry { try await osaKitRunner.runJSON(script, timeout: timeout) }
            if treatEmptyAsFailure, looksLikeEmptyLibraryJSON(json) {
                throw AppError.notesScriptFailed("Notes returned empty library via OSAKit.")
            }
            await NotesJXARuntime.shared.setPreferredRunner(.osaKit)
            return json
        } catch {
            // Fallback to process runner.
            let json = try await runWithRetry { try await processRunner.runJSON(script, timeout: timeout) }
            await NotesJXARuntime.shared.setPreferredRunner(.process)
            return json
        }
    }

    func runProcessFirst(_ script: String, timeout: TimeInterval, treatEmptyAsFailure: Bool) async throws -> String {
        do {
            let json = try await runWithRetry { try await processRunner.runJSON(script, timeout: timeout) }
            if treatEmptyAsFailure, looksLikeEmptyLibraryJSON(json) {
                throw AppError.notesScriptFailed("Notes returned empty library via process.")
            }
            await NotesJXARuntime.shared.setPreferredRunner(.process)
            return json
        } catch {
            let json = try await runWithRetry { try await osaKitRunner.runJSON(script, timeout: timeout) }
            await NotesJXARuntime.shared.setPreferredRunner(.osaKit)
            return json
        }
    }

    func looksLikeEmptyLibraryJSON(_ json: String) -> Bool {
        // Very small heuristic for the one call where emptiness is unexpected and harmful.
        // We only use it for listAccountsAndFolders.
        return json.contains("\"accounts\"") && json.contains("[]")
    }
}

private extension JSONDecoder {
    static var notes: JSONDecoder {
        JSONDecoder()
    }
}

private extension JXAAccountsAndFoldersResponse {
    func toLibraryModel(noteCountsByFolderID: [String: Int]) -> NotesLibrary {
        let accounts = accounts.map { acct -> NotesAccount in
            let folders = acct.folders.map { $0.toFolderItem(accountName: acct.name, noteCountsByFolderID: noteCountsByFolderID) }
            let roots = NotesFolderTreeBuilder.buildTree(folders: folders, noteCountsByFolderID: noteCountsByFolderID)
            return NotesAccount(id: acct.id, name: acct.name, rootFolders: roots)
        }
        return NotesLibrary(accounts: accounts)
    }
}

private struct FolderItem: Sendable {
    var id: String
    var name: String
    var pathComponents: [String]
    var noteCount: Int
}

private extension JXAFolderFlat {
    func toFolderItem(accountName: String, noteCountsByFolderID: [String: Int]) -> FolderItem {
        // path looks like "Account/Foo/Bar" (account name may contain '/'; treat as best-effort).
        // We prefer to trust `name` + `path` suffix after the first "/".
        let comps = path.split(separator: "/").map(String.init)
        let folderComps: [String]
        if comps.first == accountName, comps.count >= 2 {
            folderComps = Array(comps.dropFirst())
        } else if comps.count >= 2 {
            folderComps = Array(comps.dropFirst())
        } else {
            folderComps = [name]
        }
        let count = noteCountsByFolderID[id] ?? 0
        return FolderItem(id: id, name: name, pathComponents: folderComps, noteCount: count)
    }
}

private enum NotesFolderTreeBuilder {
    static func buildTree(folders: [FolderItem], noteCountsByFolderID: [String: Int]) -> [NotesFolder] {
        // Create nodes for each folder id, then attach by parent path.
        // Notes’ JXA doesn’t give explicit parent pointers reliably, so we derive it from pathComponents.
        struct Key: Hashable { var path: [String] }

        var nodesByKey: [Key: NotesFolder] = [:]
        var idByKey: [Key: String] = [:]

        for f in folders {
            let key = Key(path: f.pathComponents)
            idByKey[key] = f.id
            nodesByKey[key] = NotesFolder(
                id: f.id,
                name: f.name,
                pathComponents: f.pathComponents,
                children: [],
                noteCount: noteCountsByFolderID[f.id] ?? f.noteCount
            )
        }

        // Attach children
        let sortedKeys = nodesByKey.keys.sorted { $0.path.count < $1.path.count }
        var childrenByParent: [Key: [Key]] = [:]
        for key in sortedKeys {
            guard key.path.count >= 2 else { continue }
            let parentKey = Key(path: Array(key.path.dropLast()))
            childrenByParent[parentKey, default: []].append(key)
        }

        func buildNode(_ key: Key) -> NotesFolder? {
            guard var node = nodesByKey[key] else { return nil }
            let childKeys = (childrenByParent[key] ?? []).sorted { $0.path.last ?? "" < $1.path.last ?? "" }
            node.children = childKeys.compactMap(buildNode)
            return node
        }

        // Roots: pathComponents with count == 1
        let rootKeys = sortedKeys.filter { $0.path.count == 1 }
        return rootKeys.compactMap(buildNode)
    }
}

private func runWithRetry<T>(
    maxAttempts: Int = 3,
    baseDelayMs: UInt64 = 250,
    _ op: @escaping () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            return try await op()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
            if attempt == maxAttempts { break }
            // Backoff: 250ms, 500ms, 1000ms...
            let delay = baseDelayMs * UInt64(1 << (attempt - 1))
            try await Task.sleep(nanoseconds: delay * 1_000_000)
        }
    }
    throw lastError ?? AppError.notesScriptFailed("Unknown scripting error.")
}
