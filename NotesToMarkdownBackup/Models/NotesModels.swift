import Foundation

struct NotesLibrary: Equatable, Sendable {
    var accounts: [NotesAccount]

    var allFolders: [NotesFolder] {
        accounts.flatMap { $0.allFolders }
    }

    func notesCount(in selectedFolderIDs: Set<String>) -> Int {
        accounts.reduce(0) { partial, account in
            partial + account.notesCount(in: selectedFolderIDs)
        }
    }
}

struct NotesAccount: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var rootFolders: [NotesFolder]

    var allFolders: [NotesFolder] {
        rootFolders.flatMap { $0.flattened() }
    }

    func notesCount(in selectedFolderIDs: Set<String>) -> Int {
        allFolders
            .filter { selectedFolderIDs.contains($0.id) }
            .reduce(0) { $0 + $1.noteCount }
    }
}

struct NotesFolder: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var pathComponents: [String]
    var children: [NotesFolder]
    var noteCount: Int

    func flattened() -> [NotesFolder] {
        [self] + children.flatMap { $0.flattened() }
    }
}

struct NotesNoteStub: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var createdAt: Date?
    var modifiedAt: Date?
}

struct NotesNoteContent: Equatable, Sendable {
    var noteID: String
    var title: String
    var createdAt: Date?
    var modifiedAt: Date?

    /// Plain text fallback if rich content is unavailable.
    var plainText: String

    /// If available, an `.rtfd` package URL inside a temp workspace.
    var rtfdPackageURL: URL?

    /// If available, HTML string (may contain richer formatting).
    var html: String?
}

struct AttachmentRef: Equatable, Sendable {
    var originalFilename: String?
    var exportedFilename: String
    var relativePath: String
    var uti: String?
}

