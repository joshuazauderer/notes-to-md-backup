import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var libraryState: LibraryLoadState = .idle
    @Published var selectedFolderIDs: Set<String> = []
    @Published var destinationURL: URL?
    @Published var exportState: ExportRunState = .idle
    @Published var appAlert: AppAlert?
    @Published var isTestingNotesConnection: Bool = false
    @Published var diagnosticsLines: [String] = []
    @Published var showPermissionsSheet: Bool = false

    private let destinationDirBookmarkKey = "destinationZipDirBookmark"
    private let destinationLastFilenameKey = "destinationZipLastFilename"
    private var destinationDirAccessURL: URL?
    private let hasSeenPermissionsSheetKey = "hasSeenPermissionsSheet_v1"

    var isBusy: Bool { exportState.isRunning || libraryState.isLoading }

    var canExport: Bool {
        destinationURL != nil && !selectedFolderIDs.isEmpty && !exportState.isRunning && libraryState.library != nil
    }

    private var exportTask: Task<Void, Never>?
    private var notesConnectionTask: Task<Void, Never>?

    private var notesProvider: NotesProviding {
        if UserDefaults.standard.bool(forKey: "useMockNotes") {
            return MockNotesAccess()
        }
        return HybridNotesAccess()
    }

    init() {
        restoreDestinationBookmark()
        if !UserDefaults.standard.bool(forKey: hasSeenPermissionsSheetKey) {
            showPermissionsSheet = true
        }
    }

    func presentPermissionsSheet() {
        showPermissionsSheet = true
    }

    func markPermissionsSheetSeen() {
        UserDefaults.standard.set(true, forKey: hasSeenPermissionsSheetKey)
    }

    func reloadLibrary() {
        exportTask?.cancel()
        selectedFolderIDs.removeAll()
        libraryState = .loading

        Task {
            do {
                diag("reloadLibrary: notesRunning=\(NotesAppLauncher.isNotesRunning())")
                let status = AutomationPermission.requestNotesPermission(askUserIfNeeded: true)
                diag("reloadLibrary: AEDeterminePermissionToAutomateTarget => \(AutomationPermission.describe(status))")
                diag("reloadLibrary: start")
                let library = try await notesProvider.fetchLibrary()
                diag("reloadLibrary: got accounts=\(library.accounts.count) folders=\(library.allFolders.count)")
                libraryState = .loaded(library)
            } catch {
                diag("reloadLibrary: failed error=\(String(describing: error))")
                libraryState = .failed(UserPresentableError(error).message)
            }
        }
    }

    func chooseDestination() {
        let panel = NSSavePanel()
        panel.title = "Save Notes Backup ZIP"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = DefaultFilenames.backupZipName()

        if panel.runModal() == .OK, let url = panel.url {
            destinationURL = url
            destinationDirAccessURL = storeDestinationDirBookmark(url.deletingLastPathComponent())
            UserDefaults.standard.set(url.lastPathComponent, forKey: destinationLastFilenameKey)
        }
    }

    func startExport() {
        guard let library = libraryState.library else { return }
        guard let destinationURL else { return }

        let selectedFolderIDs = self.selectedFolderIDs
        exportState = .running(
            headline: "Preparing export…",
            detail: "",
            progressFraction: 0,
            notesProcessed: 0,
            notesTotal: max(library.notesCount(in: selectedFolderIDs), 1),
            logs: ["Starting export…"],
            lastResultMessage: nil,
            lastResultWasError: false
        )

        exportTask?.cancel()
        exportTask = Task {
            let logger = InMemoryLogger { [weak self] line in
                Task { @MainActor in
                    self?.exportState.appendLog(line)
                }
            }

            do {
                // Security-scope an existing URL. IMPORTANT: don't derive the parent directory URL
                // from a security-scoped URL (that drops the scope). Use the resolved bookmark URL.
                let scopeURL = destinationDirAccessURL ?? destinationURL
                var destScoped = SecurityScopedURL(url: scopeURL)
                try destScoped.startAccessing()
                defer { destScoped.stopAccessing() }

                let exporter = Exporter(
                    notesProvider: notesProvider,
                    markdownConverter: MarkdownConverter(),
                    logger: logger
                )

                try await exporter.exportZip(
                    library: library,
                    selectedFolderIDs: selectedFolderIDs,
                    destinationZipURL: destinationURL
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.exportState.apply(progress)
                    }
                }

                exportState.finish(message: "Export finished: \(destinationURL.lastPathComponent)", isError: false)
                await MainActor.run { [weak self] in
                    self?.appAlert = .exportSucceeded(zipURL: destinationURL)
                }
            } catch is CancellationError {
                exportState.finish(message: "Export cancelled.", isError: false)
            } catch {
                exportState.finish(message: UserPresentableError(error).message, isError: true)
            }
        }
    }

    func cancelExport() {
        exportTask?.cancel()
    }

    func testNotesConnection() {
        notesConnectionTask?.cancel()
        isTestingNotesConnection = true

        notesConnectionTask = Task {
            defer { Task { @MainActor in self.isTestingNotesConnection = false } }

            if UserDefaults.standard.bool(forKey: "useMockNotes") {
                await MainActor.run {
                    appAlert = .info(
                        title: "Notes connection (Mock Mode)",
                        message: "Mock Notes mode is enabled.\n\nAccounts: 2\nFolders: 2"
                    )
                }
                return
            }

            do {
                let status = AutomationPermission.requestNotesPermission(askUserIfNeeded: true)
                diag("testNotesConnection: AEDeterminePermissionToAutomateTarget => \(AutomationPermission.describe(status))")

                diag("testNotesConnection: start (via fetchLibrary)")
                let library = try await notesProvider.fetchLibrary()
                let accountCount = library.accounts.count
                let folderCount = library.allFolders.count
                diag("testNotesConnection: fetchLibrary accounts=\(accountCount) folders=\(folderCount)")

                // Also run the tiny probe as a secondary signal (in-process + process).
                do {
                    let runner = JXAOSAKitRunner()
                    let res = try await runner.runDetailed(JXAScripts.testConnection, timeout: 15)
                    diag("testNotesConnection: tinyProbe exit=\(res.exitCode) stdout=\(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr=\(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                } catch {
                    diag("testNotesConnection: tinyProbe failed error=\(String(describing: error))")
                }
                do {
                    let runner = JXARunner()
                    let res = try await runner.runDetailed(JXAScripts.testConnection, timeout: 15)
                    diag("testNotesConnection: tinyProbe(process) exit=\(res.exitCode) stdout=\(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr=\(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                } catch {
                    diag("testNotesConnection: tinyProbe(process) failed error=\(String(describing: error))")
                }
                do {
                    let runner = JXAOSAKitRunner()
                    let res = try await runner.runDetailed(JXAScripts.diagnosticsProbe, timeout: 15)
                    diag("testNotesConnection: diagProbe(osaKit) exit=\(res.exitCode) stdout=\(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr=\(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                } catch {
                    diag("testNotesConnection: diagProbe(osaKit) failed error=\(String(describing: error))")
                }
                do {
                    let runner = JXARunner()
                    let res = try await runner.runDetailed(JXAScripts.diagnosticsProbe, timeout: 15)
                    diag("testNotesConnection: diagProbe(process) exit=\(res.exitCode) stdout=\(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr=\(res.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                } catch {
                    diag("testNotesConnection: diagProbe(process) failed error=\(String(describing: error))")
                }

                await MainActor.run {
                    appAlert = .info(
                        title: "Notes connection succeeded",
                        message: "Accounts: \(accountCount)\nFolders: \(folderCount)"
                    )
                }
            } catch {
                let msg = UserPresentableError(error).message
                diag("testNotesConnection: failed error=\(String(describing: error))")
                await MainActor.run {
                    appAlert = .info(
                        title: "Notes connection failed",
                        message: msg + "\n\nIf you denied permission, enable it in System Settings → Privacy & Security → Automation."
                    )
                }
            }
        }
    }

    private func restoreDestinationBookmark() {
        guard let data = UserDefaults.standard.data(forKey: destinationDirBookmarkKey) else { return }
        var stale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) {
            let filename = UserDefaults.standard.string(forKey: destinationLastFilenameKey) ?? DefaultFilenames.backupZipName()
            destinationURL = url.appendingPathComponent(filename)
            destinationDirAccessURL = url
            if stale {
                destinationDirAccessURL = storeDestinationDirBookmark(url)
            }
        }
    }

    @discardableResult
    private func storeDestinationDirBookmark(_ directoryURL: URL) -> URL? {
        do {
            let data = try directoryURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: destinationDirBookmarkKey)

            // Return the resolved security-scoped URL for immediate use.
            var stale = false
            return try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            // Best-effort.
            return nil
        }
    }

    func diag(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        diagnosticsLines.append("[\(ts)] \(message)")
        if diagnosticsLines.count > 500 {
            diagnosticsLines.removeFirst(diagnosticsLines.count - 500)
        }
        NSLog("%@", message)
    }
}

struct NotesConnectionCounts: Codable, Sendable {
    var accountCount: Int
    var folderCount: Int
}

enum AppAlert: Identifiable, Equatable {
    case info(id: UUID = UUID(), title: String, message: String)
    case exportSucceeded(id: UUID = UUID(), zipURL: URL)

    var id: UUID {
        switch self {
        case .info(let id, _, _): return id
        case .exportSucceeded(let id, _): return id
        }
    }
}

enum LibraryLoadState: Equatable {
    case idle
    case loading
    case loaded(NotesLibrary)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var library: NotesLibrary? {
        if case .loaded(let lib) = self { return lib }
        return nil
    }
}

struct ExportRunState: Equatable {
    var isRunning: Bool
    var headline: String
    var detail: String
    var progressFraction: Double
    var notesProcessed: Int
    var notesTotal: Int
    var logs: [String]
    var lastResultMessage: String?
    var lastResultWasError: Bool

    static var idle: ExportRunState {
        ExportRunState(
            isRunning: false,
            headline: "Ready",
            detail: "",
            progressFraction: 0,
            notesProcessed: 0,
            notesTotal: 0,
            logs: [],
            lastResultMessage: nil,
            lastResultWasError: false
        )
    }

    static func running(
        headline: String,
        detail: String,
        progressFraction: Double,
        notesProcessed: Int,
        notesTotal: Int,
        logs: [String],
        lastResultMessage: String?,
        lastResultWasError: Bool
    ) -> ExportRunState {
        ExportRunState(
            isRunning: true,
            headline: headline,
            detail: detail,
            progressFraction: progressFraction,
            notesProcessed: notesProcessed,
            notesTotal: notesTotal,
            logs: logs,
            lastResultMessage: lastResultMessage,
            lastResultWasError: lastResultWasError
        )
    }

    mutating func appendLog(_ line: String) {
        logs.append(line)
    }

    mutating func apply(_ progress: ExportProgress) {
        isRunning = true
        headline = progress.headline
        detail = progress.detail
        progressFraction = progress.fraction
        notesProcessed = progress.notesProcessed
        notesTotal = progress.notesTotal
    }

    mutating func finish(message: String, isError: Bool) {
        isRunning = false
        lastResultMessage = message
        lastResultWasError = isError
    }
}

