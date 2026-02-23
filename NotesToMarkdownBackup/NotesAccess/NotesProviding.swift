import Foundation

protocol NotesProviding: Sendable {
    func fetchLibrary() async throws -> NotesLibrary

    func listNoteStubs(folderID: String) async throws -> [NotesNoteStub]

    /// Fetches note content, attempting richer formats first.
    /// - Parameter tempWorkspace: A per-export temp folder for intermediate artifacts (e.g. `.rtfd` packages).
    func fetchNoteContent(noteID: String, tempWorkspace: URL) async throws -> NotesNoteContent

    /// Exports attachments/images for a note into the provided directory.
    /// - Important: `destinationDirectory` must be inside the sandbox container (e.g. the exporter staging folder).
    func exportAttachments(
        noteID: String,
        destinationDirectory: URL,
        noteSlug: String
    ) async -> AttachmentExportResult
}

