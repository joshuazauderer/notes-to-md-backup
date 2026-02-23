import Foundation

enum AppError: Error, Equatable {
    case notesAutomationDenied
    case notesNotRunning
    case notesScriptFailed(String)
    case invalidNotesResponse
    case exportFailed(String)
    case fileWriteFailed(String)
    case zipFailed(String)
}

struct UserPresentableError: Error {
    let underlying: Error
    let message: String

    init(_ error: Error) {
        underlying = error
        message = UserPresentableError.describe(error)
    }

    private static func describe(_ error: Error) -> String {
        if let appError = error as? AppError {
            switch appError {
            case .notesAutomationDenied:
                return "Notes automation permission was denied. Enable it in System Settings → Privacy & Security → Automation."
            case .notesNotRunning:
                return "Notes.app couldn’t be reached. Try opening Notes and retry."
            case .notesScriptFailed(let details):
                return "Notes scripting failed: \(details)"
            case .invalidNotesResponse:
                return "Notes returned an unexpected response."
            case .exportFailed(let details):
                return "Export failed: \(details)"
            case .fileWriteFailed(let details):
                return "Couldn’t write export files: \(details)"
            case .zipFailed(let details):
                return "Couldn’t create ZIP: \(details)"
            }
        }

        if let cancellation = error as? CancellationError {
            return cancellation.localizedDescription
        }

        return (error as NSError).localizedDescription
    }
}

