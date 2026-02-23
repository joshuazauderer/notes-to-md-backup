import Foundation

struct ExportProgress: Equatable, Sendable {
    var headline: String
    var detail: String
    var fraction: Double
    var notesProcessed: Int
    var notesTotal: Int
}

