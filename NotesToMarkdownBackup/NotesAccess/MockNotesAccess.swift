import Foundation

struct MockNotesAccess: NotesProviding {
    func fetchLibrary() async throws -> NotesLibrary {
        let work = NotesFolder(
            id: "mock-folder-work",
            name: "Work",
            pathComponents: ["Work"],
            children: [
                NotesFolder(
                    id: "mock-folder-work-projects",
                    name: "Projects",
                    pathComponents: ["Work", "Projects"],
                    children: [],
                    noteCount: 2
                )
            ],
            noteCount: 1
        )

        let personal = NotesFolder(
            id: "mock-folder-personal",
            name: "Personal",
            pathComponents: ["Personal"],
            children: [],
            noteCount: 3
        )

        return NotesLibrary(
            accounts: [
                NotesAccount(id: "mock-icloud", name: "iCloud", rootFolders: [work]),
                NotesAccount(id: "mock-local", name: "On My Mac", rootFolders: [personal])
            ]
        )
    }

    func listNoteStubs(folderID: String) async throws -> [NotesNoteStub] {
        let now = Date()
        return [
            NotesNoteStub(id: "\(folderID)-note-1", title: "Example note", createdAt: now.addingTimeInterval(-86400), modifiedAt: now),
            NotesNoteStub(id: "\(folderID)-note-2", title: "Second note (with image)", createdAt: now.addingTimeInterval(-172800), modifiedAt: now.addingTimeInterval(-3600))
        ]
    }

    func fetchNoteContent(noteID: String, tempWorkspace: URL) async throws -> NotesNoteContent {
        let sample = """
        This is mock content for \(noteID).

        - It supports lists
        - And links: https://example.com
        """
        return NotesNoteContent(
            noteID: noteID,
            title: "Mock: \(noteID)",
            createdAt: Date().addingTimeInterval(-100000),
            modifiedAt: Date(),
            plainText: sample,
            rtfdPackageURL: nil,
            html: nil
        )
    }

    func exportAttachments(noteID: String, destinationDirectory: URL, noteSlug: String) async -> AttachmentExportResult {
        AttachmentExportResult(noteId: noteID, exports: [], errors: [])
    }
}

