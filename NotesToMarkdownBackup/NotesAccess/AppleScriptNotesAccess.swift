import Foundation

/// In-process AppleScript Notes access fallback.
///
/// This is used when JXA enumeration returns an empty library in some sandboxed/debug setups.
struct AppleScriptNotesAccess: NotesProviding {
    private let executor = NotesScriptExecutor()

    func fetchLibrary() async throws -> NotesLibrary {
        try await NotesAppLauncher.ensureRunning(timeout: 30.0)

        let json = try await executor.runAppleScript(AppleScriptTemplates.listAccountsAndFoldersJSON)
        guard let data = json.data(using: .utf8) else { throw AppError.invalidNotesResponse }
        let decoded = try JSONDecoder().decode(AppleScriptAccountsAndFoldersResponse.self, from: data)

        // Build NotesLibrary tree from flat folders per account.
        let accounts: [NotesAccount] = decoded.accounts.map { acct in
            let folderItems = acct.folders.map { f in
                FolderItem(id: f.id, name: f.name, pathComponents: f.pathComponents, noteCount: f.noteCount)
            }
            let roots = NotesFolderTreeBuilder.buildTree(folders: folderItems)
            return NotesAccount(id: acct.id, name: acct.name, rootFolders: roots)
        }
        return NotesLibrary(accounts: accounts)
    }

    func listNoteStubs(folderID: String) async throws -> [NotesNoteStub] {
        try await NotesAppLauncher.ensureRunning(timeout: 30.0)

        let script = String(format: AppleScriptTemplates.listNotesInFolderJSONTemplate, folderID.appleScriptQuoted)
        let json = try await executor.runAppleScript(script)
        guard let data = json.data(using: .utf8) else { throw AppError.invalidNotesResponse }
        let decoded = try JSONDecoder().decode(AppleScriptNotesInFolderResponse.self, from: data)

        return decoded.notes.map {
            NotesNoteStub(
                id: $0.id,
                title: $0.title.isEmpty ? "Untitled" : $0.title,
                createdAt: JXADates.parse($0.createdAt),
                modifiedAt: JXADates.parse($0.modifiedAt)
            )
        }
    }

    func fetchNoteContent(noteID: String, tempWorkspace: URL) async throws -> NotesNoteContent {
        try await NotesAppLauncher.ensureRunning(timeout: 30.0)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: tempWorkspace, withIntermediateDirectories: true)

        let noteTemp = tempWorkspace.appendingPathComponent("as-note-\(StableHash.shortHex(noteID, length: 12))", isDirectory: true)
        try? fileManager.removeItem(at: noteTemp)
        try fileManager.createDirectory(at: noteTemp, withIntermediateDirectories: true)

        let plainURL = noteTemp.appendingPathComponent("plain.txt")
        let htmlURL = noteTemp.appendingPathComponent("body.html")
        let rtfdURL = noteTemp.appendingPathComponent("body.rtfd")

        let script = AppleScriptTemplates.fetchNoteToFiles(
            noteID: noteID,
            plainPath: plainURL.path,
            htmlPath: htmlURL.path,
            rtfdPath: rtfdURL.path
        )

        let title = try await executor.runAppleScript(script).trimmingCharacters(in: .whitespacesAndNewlines)

        let plainText = (try? String(contentsOf: plainURL, encoding: .utf8)) ?? ""
        let html = (try? String(contentsOf: htmlURL, encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }

        let rtfdPackageURL: URL? = fileManager.fileExists(atPath: rtfdURL.path) ? rtfdURL : nil

        return NotesNoteContent(
            noteID: noteID,
            title: title.isEmpty ? "Untitled" : title,
            createdAt: nil,
            modifiedAt: nil,
            plainText: plainText,
            rtfdPackageURL: rtfdPackageURL,
            html: html
        )
    }

    func exportAttachments(noteID: String, destinationDirectory: URL, noteSlug: String) async -> AttachmentExportResult {
        // For AppleScript fallback we rely on RTFD extraction in MarkdownConverter (rtfdPackageURL).
        AttachmentExportResult(noteId: noteID, exports: [], errors: [])
    }
}

// MARK: - AppleScript JSON payloads

private enum AppleScriptTemplates {
    static let listAccountsAndFoldersJSON: String = """
    on run
      tell application id "com.apple.Notes" to launch
      delay 0.2
      set json to "{\\"accounts\\":["
      tell application id "com.apple.Notes"
        set acctCount to count of accounts
        repeat with ai from 1 to acctCount
          set a to account ai
          set acctName to my esc(name of a)
          set acctId to my esc((name of a) as text)
          set json to json & "{\\"id\\":\\"" & acctId & "\\",\\"name\\":\\"" & acctName & "\\",\\"folders\\":["

          set folderJSONParts to {}
          set allFolders to folders of a
          set fCount to count of allFolders
          repeat with fi from 1 to fCount
            set f to item fi of allFolders
            set isRoot to true
            try
              set _p to folder of f
              set isRoot to false
            end try
            if isRoot then
              my appendFolderJSON(folderJSONParts, f, name of a, {})
            end if
          end repeat

          set json to json & my join(folderJSONParts, ",") & "]}"
          if ai is not acctCount then set json to json & ","
        end repeat
      end tell
      set json to json & "]}"
      return json
    end run

    on appendFolderJSON(parts, f, acctName, parentPathParts)
      tell application id "com.apple.Notes"
        set fname to name of f as text
        set pathParts to parentPathParts & {fname}
        set fid to ""
        try
          set fid to id of f as text
        on error
          set fid to acctName & "|" & my join(pathParts, "/")
        end try

        set noteCount to 0
        try
          set noteCount to (count of notes of f)
        end try

        set pathStr to my esc(acctName & "/" & my join(pathParts, "/"))
        set nameEsc to my esc(fname)
        set idEsc to my esc(fid)

        set pcJSON to my jsonArray(pathParts)
        set obj to "{\\"id\\":\\"" & idEsc & "\\",\\"name\\":\\"" & nameEsc & "\\",\\"path\\":\\"" & pathStr & "\\",\\"pathComponents\\":" & pcJSON & ",\\"noteCount\\":" & noteCount & "}"
        set end of parts to obj

        set children to {}
        try
          set children to folders of f
        end try
        repeat with c in children
          my appendFolderJSON(parts, c, acctName, pathParts)
        end repeat
      end tell
    end appendFolderJSON

    on esc(t)
      set s to t as text
      set s to my repl(s, "\\\\", "\\\\\\\\")
      set s to my repl(s, "\\"" , "\\\\\\"")
      set s to my repl(s, return, "\\\\n")
      set s to my repl(s, linefeed, "\\\\n")
      return s
    end esc

    on repl(t, a, b)
      set AppleScript's text item delimiters to a
      set xs to every text item of t
      set AppleScript's text item delimiters to b
      set t2 to xs as text
      set AppleScript's text item delimiters to ""
      return t2
    end repl

    on join(xs, sep)
      set AppleScript's text item delimiters to sep
      set out to xs as text
      set AppleScript's text item delimiters to ""
      return out
    end join

    on jsonArray(xs)
      set outParts to {}
      repeat with x in xs
        set end of outParts to ("\\"" & my esc(x as text) & "\\"")
      end repeat
      return "[" & my join(outParts, ",") & "]"
    end jsonArray
    """

    static let listNotesInFolderJSONTemplate: String = """
    on run
      tell application id "com.apple.Notes" to launch
      delay 0.2
      set folderId to %@ -- already quoted
      set json to "{\\"folderId\\":\\"" & my esc(folderId) & "\\",\\"notes\\":["
      set parts to {}
      tell application id "com.apple.Notes"
        set f to my findFolderById(folderId)
        if f is missing value then
          set json to "{\\"folderId\\":\\"" & my esc(folderId) & "\\",\\"notes\\":[]}"
          return json
        end if
        set ns to notes of f
        repeat with n in ns
          set nid to ""
          try
            set nid to id of n as text
          on error
            set nid to (name of n as text)
          end try
          set title to name of n as text
          set cISO to ""
          set mISO to ""
          try
            set cISO to my iso(creation date of n)
          end try
          try
            set mISO to my iso(modification date of n)
          end try
          set end of parts to "{\\"id\\":\\"" & my esc(nid) & "\\",\\"title\\":\\"" & my esc(title) & "\\",\\"createdAt\\":\\"" & my esc(cISO) & "\\",\\"modifiedAt\\":\\"" & my esc(mISO) & "\\"}"
        end repeat
      end tell
      set json to json & my join(parts, ",") & "]}"
      return json
    end run

    on findFolderById(folderId)
      tell application id "com.apple.Notes"
        repeat with a in accounts
          set fs to folders of a
          repeat with f in fs
            try
              if (id of f as text) is folderId then return f
            end try
          end repeat
        end repeat
      end tell
      return missing value
    end findFolderById

    on iso(d)
      set df to current date
      set y to year of d as integer
      set mo to month of d as integer
      set da to day of d as integer
      set hh to hours of d as integer
      set mm to minutes of d as integer
      set ss to seconds of d as integer
      return (my pad(y, 4) & "-" & my pad(mo, 2) & "-" & my pad(da, 2) & "T" & my pad(hh, 2) & ":" & my pad(mm, 2) & ":" & my pad(ss, 2) & "Z")
    end iso

    on pad(n, w)
      set s to n as text
      repeat while (count of s) < w
        set s to "0" & s
      end repeat
      return s
    end pad

    on esc(t)
      set s to t as text
      set s to my repl(s, "\\\\", "\\\\\\\\")
      set s to my repl(s, "\\"" , "\\\\\\"")
      set s to my repl(s, return, "\\\\n")
      set s to my repl(s, linefeed, "\\\\n")
      return s
    end esc

    on repl(t, a, b)
      set AppleScript's text item delimiters to a
      set xs to every text item of t
      set AppleScript's text item delimiters to b
      set t2 to xs as text
      set AppleScript's text item delimiters to ""
      return t2
    end repl

    on join(xs, sep)
      set AppleScript's text item delimiters to sep
      set out to xs as text
      set AppleScript's text item delimiters to ""
      return out
    end join
    """

    static func fetchNoteToFiles(noteID: String, plainPath: String, htmlPath: String, rtfdPath: String) -> String {
        let noteIDQ = noteID.appleScriptQuoted
        let plainQ = plainPath.appleScriptQuoted
        let htmlQ = htmlPath.appleScriptQuoted
        let rtfdQ = rtfdPath.appleScriptQuoted

        return """
        on run
          tell application id "com.apple.Notes" to launch
          delay 0.2
          set noteId to \(noteIDQ)
          set plainPath to \(plainQ)
          set htmlPath to \(htmlQ)
          set rtfdPath to \(rtfdQ)
          tell application id "com.apple.Notes"
            set n to my findNoteById(noteId)
            if n is missing value then return ""
            set t to name of n
            try
              set p to plaintext of n
              my writeUTF8(p, plainPath)
            end try
            try
              set h to body of n as HTML
              my writeUTF8(h, htmlPath)
            end try
            try
              set d to body of n as RTFD
              my writeData(d, rtfdPath)
            end try
          end tell
          return t
        end run

        on findNoteById(noteId)
          tell application id "com.apple.Notes"
            try
              return note id noteId
            on error
              return missing value
            end try
          end tell
        end findNoteById

        on writeUTF8(txt, posixPath)
          set f to open for access (POSIX file posixPath) with write permission
          set eof of f to 0
          write txt to f as «class utf8»
          close access f
        end writeUTF8

        on writeData(d, posixPath)
          set f to open for access (POSIX file posixPath) with write permission
          set eof of f to 0
          write d to f
          close access f
        end writeData
        """
    }
}

private struct AppleScriptAccountsAndFoldersResponse: Codable, Sendable {
    var accounts: [AppleScriptAccount]
}

private struct AppleScriptAccount: Codable, Sendable {
    var id: String
    var name: String
    var folders: [AppleScriptFolderFlat]
}

private struct AppleScriptFolderFlat: Codable, Sendable {
    var id: String
    var name: String
    var path: String
    var pathComponents: [String]
    var noteCount: Int
}

private struct AppleScriptNotesInFolderResponse: Codable, Sendable {
    var folderId: String
    var notes: [AppleScriptNoteHeader]
}

private struct AppleScriptNoteHeader: Codable, Sendable {
    var id: String
    var title: String
    var createdAt: String?
    var modifiedAt: String?
}

private struct FolderItem: Sendable {
    var id: String
    var name: String
    var pathComponents: [String]
    var noteCount: Int
}

private enum NotesFolderTreeBuilder {
    static func buildTree(folders: [FolderItem]) -> [NotesFolder] {
        struct Key: Hashable { var path: [String] }
        var nodes: [Key: NotesFolder] = [:]
        for f in folders {
            nodes[Key(path: f.pathComponents)] = NotesFolder(
                id: f.id,
                name: f.name,
                pathComponents: f.pathComponents,
                children: [],
                noteCount: f.noteCount
            )
        }
        let keys = nodes.keys.sorted { $0.path.count < $1.path.count }
        var childrenByParent: [Key: [Key]] = [:]
        for k in keys where k.path.count >= 2 {
            let parent = Key(path: Array(k.path.dropLast()))
            childrenByParent[parent, default: []].append(k)
        }
        func build(_ k: Key) -> NotesFolder? {
            guard var n = nodes[k] else { return nil }
            let childKeys = (childrenByParent[k] ?? []).sorted { ($0.path.last ?? "") < ($1.path.last ?? "") }
            n.children = childKeys.compactMap(build)
            return n
        }
        return keys.filter { $0.path.count == 1 }.compactMap(build)
    }
}

private extension String {
    var appleScriptQuoted: String {
        "\"" + self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "\\n") + "\""
    }
}

