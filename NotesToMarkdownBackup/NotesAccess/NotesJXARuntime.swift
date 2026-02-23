import Foundation

actor NotesJXARuntime {
    static let shared = NotesJXARuntime()

    enum RunnerKind: String, Sendable {
        case osaKit
        case process
    }

    private var preferred: RunnerKind?

    func preferredRunner() -> RunnerKind? {
        preferred
    }

    func setPreferredRunner(_ kind: RunnerKind) {
        preferred = kind
    }
}

