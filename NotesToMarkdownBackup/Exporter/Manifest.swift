import Foundation

struct ExportManifest: Codable, Sendable {
    var exportedAt: String
    var appVersion: String
    var selectedFolders: [SelectedFolder]
    var counts: Counts
    var failures: [Failure]
    var limitations: [String]

    struct SelectedFolder: Codable, Sendable {
        var account: String
        var folderPath: String
        var folderID: String
    }

    struct Counts: Codable, Sendable {
        var accounts: Int
        var folders: Int
        var notesAttempted: Int
        var notesExported: Int
        var attachmentsExported: Int
    }

    struct Failure: Codable, Sendable {
        var account: String
        var folderPath: String
        var noteTitle: String
        var noteID: String
        var error: String
    }
}

