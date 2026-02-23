import Foundation

protocol Logger: Sendable {
    func info(_ message: String)
    func warn(_ message: String)
    func error(_ message: String)
}

final class InMemoryLogger: Logger {
    typealias Sink = @Sendable (String) -> Void

    private let sink: Sink
    private let lock = NSLock()

    init(sink: @escaping Sink) {
        self.sink = sink
    }

    func info(_ message: String) { emit("INFO", message) }
    func warn(_ message: String) { emit("WARN", message) }
    func error(_ message: String) { emit("ERROR", message) }

    private func emit(_ level: String, _ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        lock.lock()
        defer { lock.unlock() }
        sink("[\(ts)] \(level): \(message)")
    }
}

