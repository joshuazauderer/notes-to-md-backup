import Foundation

// MARK: - JSON contracts (must match JXA output keys exactly)

struct JXAAccountsAndFoldersResponse: Codable, Sendable {
    var accounts: [JXAAccountFolders]
}

struct JXAAccountFolders: Codable, Sendable {
    var id: String
    var name: String
    var folders: [JXAFolderFlat]
}

struct JXAFolderFlat: Codable, Sendable {
    var id: String
    var name: String
    /// e.g. "iCloud/Work/Projects"
    var path: String
}

struct JXANotesInFolderResponse: Codable, Sendable {
    var folderId: String
    var notes: [JXANoteHeader]
}

struct JXANoteHeader: Codable, Sendable {
    var id: String
    var title: String
    var createdAt: String?
    var modifiedAt: String?
}

struct JXANoteDetailResponse: Codable, Sendable {
    var id: String
    var title: String
    var account: String?
    var folderPath: String?
    var createdAt: String?
    var modifiedAt: String?
    var html: String?
    var plain: String?
    var hasAttachments: Bool
}

struct JXAAttachmentExportResponse: Codable, Sendable {
    var noteId: String
    var exports: [JXAAttachmentExportItem]
    var errors: [JXAInlineError]
}

struct JXAAttachmentExportItem: Codable, Sendable {
    var kind: String // "image" | "file"
    var mimeType: String?
    var relativePath: String
    var originalName: String?
}

struct JXAInlineError: Codable, Sendable {
    var message: String
    var code: String?
}

struct JXAFolderNoteCountsResponse: Codable, Sendable {
    var counts: [JXAFolderNoteCount]
}

struct JXAFolderNoteCount: Codable, Sendable {
    var folderId: String
    var noteCount: Int
}

// MARK: - Swift-side normalized wrapper used by exporter/markdown layer

struct AttachmentExportResult: Sendable, Equatable {
    struct Export: Sendable, Equatable {
        var kind: Kind
        var mimeType: String?
        /// Relative path from the note markdown file (e.g. "assets/<noteSlug>/foo.png")
        var relativePath: String
        var originalName: String?

        enum Kind: String, Sendable {
            case image
            case file
        }
    }

    struct Failure: Sendable, Equatable {
        var message: String
        var code: String?
    }

    var noteId: String
    var exports: [Export]
    var errors: [Failure]
}

extension AttachmentExportResult {
    init(_ jxa: JXAAttachmentExportResponse) {
        self.noteId = jxa.noteId
        self.exports = jxa.exports.compactMap { item in
            guard let kind = Export.Kind(rawValue: item.kind) else { return nil }
            return Export(kind: kind, mimeType: item.mimeType, relativePath: item.relativePath, originalName: item.originalName)
        }
        self.errors = jxa.errors.map { Failure(message: $0.message, code: $0.code) }
    }
}

// MARK: - Helpers

enum JXADates {
    static let iso = ISO8601DateFormatter()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return iso.date(from: s)
    }
}

