import Foundation

struct Exporter: Sendable {
    typealias ProgressHandler = @Sendable (ExportProgress) -> Void

    let notesProvider: NotesProviding
    let markdownConverter: MarkdownConverter
    let logger: Logger

    func exportZip(
        library: NotesLibrary,
        selectedFolderIDs: Set<String>,
        destinationZipURL: URL,
        onProgress: ProgressHandler?
    ) async throws {
        let fileManager = FileManager.default

        // Keep the ZIP contents separate from internal workspace/temp artifacts so we never
        // accidentally include them in the archive.
        let containerRoot = fileManager.temporaryDirectory.appendingPathComponent("NotesMarkdownExport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: containerRoot) }
        try fileManager.createDirectory(at: containerRoot, withIntermediateDirectories: true)

        let stagingRoot = containerRoot.appendingPathComponent("Staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        let workspace = containerRoot.appendingPathComponent("_workspace", isDirectory: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)

        // Root README inside the ZIP.
        try ExporterTemplates.exportReadme.write(to: stagingRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let selection = FolderSelection(library: library, selectedFolderIDs: selectedFolderIDs)
        logger.info("Selected \(selection.selectedFolderCount) folder(s) (after de-dup).")

        let totalNotes = try await selection.countNotes(using: notesProvider, logger: logger)
        let runState = ExportRunStateCollector(totalNotes: totalNotes)

        func emit(_ headline: String, _ detail: String) async {
            let snapshot = await runState.snapshot()
            onProgress?(ExportProgress(
                headline: headline,
                detail: detail,
                fraction: snapshot.totalNotes == 0 ? 0 : Double(snapshot.processed) / Double(snapshot.totalNotes),
                notesProcessed: snapshot.processed,
                notesTotal: snapshot.totalNotes
            ))
        }

        await emit("Exporting…", "Preparing…")

        let pathMap = ExportPathMap(library: library)
        for sel in selection.selectedFolders {
            try Task.checkCancellation()
            guard let account = pathMap.account(forFolderID: sel.folder.id) else { continue }

            let accountDir = stagingRoot.appendingPathComponent(pathMap.safeAccountDirName(accountID: account.id, accountName: account.name), isDirectory: true)
            try fileManager.createDirectory(at: accountDir, withIntermediateDirectories: true)

            try await exportFolderSubtree(
                folder: sel.folder,
                accountName: account.name,
                accountDir: accountDir,
                pathMap: pathMap,
                workspace: workspace,
                runState: runState,
                emitProgress: emit
            )
        }

        // Write manifest.
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let selected = selection.selectedFolders.map {
            ExportManifest.SelectedFolder(
                account: pathMap.account(forFolderID: $0.folder.id)?.name ?? "Unknown",
                folderPath: $0.folder.pathComponents.joined(separator: "/"),
                folderID: $0.folder.id
            )
        }

        let finalSnapshot = await runState.snapshot()
        let failures = await runState.failures()

        let manifest = ExportManifest(
            exportedAt: nowISO,
            appVersion: "1.0",
            selectedFolders: selected,
            counts: ExportManifest.Counts(
                accounts: library.accounts.count,
                folders: library.allFolders.count,
                notesAttempted: finalSnapshot.totalNotes,
                notesExported: finalSnapshot.exported,
                attachmentsExported: finalSnapshot.attachmentsExported
            ),
            failures: failures,
            limitations: ExporterTemplates.limitations
        )

        let manifestURL = stagingRoot.appendingPathComponent("manifest.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        // Zip.
        await emit("Creating ZIP…", destinationZipURL.lastPathComponent)
        let tempZip = containerRoot.appendingPathComponent("out.zip")
        try ZipUtil.zipDirectoryContents(sourceDirectory: stagingRoot, to: tempZip)

        // Move to destination.
        if fileManager.fileExists(atPath: destinationZipURL.path) {
            try fileManager.removeItem(at: destinationZipURL)
        }
        try fileManager.copyItem(at: tempZip, to: destinationZipURL)
        await emit("Done", destinationZipURL.lastPathComponent)
        logger.info("ZIP written to \(destinationZipURL.path(percentEncoded: false))")
    }

    private func exportFolderSubtree(
        folder: NotesFolder,
        accountName: String,
        accountDir: URL,
        pathMap: ExportPathMap,
        workspace: URL,
        runState: ExportRunStateCollector,
        emitProgress: (_ headline: String, _ detail: String) async -> Void
    ) async throws {
        let fileManager = FileManager.default

        let folderDir = accountDir.appendingPathComponent(pathMap.safeFolderPath(for: folder), isDirectory: true)
        try fileManager.createDirectory(at: folderDir, withIntermediateDirectories: true)

        let assetsDir = folderDir.appendingPathComponent("assets", isDirectory: true)
        try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

        var noteNameAllocator = UniqueFilenameAllocator()
        let stubs = try await notesProvider.listNoteStubs(folderID: folder.id)

        for stub in stubs {
            try Task.checkCancellation()
            await runState.incrementProcessed()
            await emitProgress("Exporting…", stub.title)

            do {
                logger.info("Exporting note: \(stub.title)")
                var content = try await notesProvider.fetchNoteContent(noteID: stub.id, tempWorkspace: workspace)

                let noteSlug = Slugify.filename(stub.title) + "_" + StableHash.shortHex(stub.id)
                let perNoteAssets = assetsDir.appendingPathComponent(noteSlug, isDirectory: true)
                try fileManager.createDirectory(at: perNoteAssets, withIntermediateDirectories: true)

                // Attachments export (best-effort).
                let attachmentResult = await notesProvider.exportAttachments(
                    noteID: stub.id,
                    destinationDirectory: perNoteAssets,
                    noteSlug: noteSlug
                )
                if !attachmentResult.errors.isEmpty {
                    logger.warn("Attachment export had \(attachmentResult.errors.count) issue(s) for note: \(stub.title)")
                }

                // If we have HTML and exported images, rewrite <img> tags to point at the exported asset paths.
                if var html = content.html {
                    let images = attachmentResult.exports.filter { $0.kind == .image }
                    if !images.isEmpty {
                        html = HTMLImageRewriter.rewriteImgSrcSequentially(html: html, images: images)
                        content = NotesNoteContent(
                            noteID: content.noteID,
                            title: content.title,
                            createdAt: content.createdAt,
                            modifiedAt: content.modifiedAt,
                            plainText: content.plainText,
                            rtfdPackageURL: content.rtfdPackageURL,
                            html: html
                        )
                    }
                }

                let conversion = try markdownConverter.convert(note: content, assetsBaseURL: assetsDir, noteSlug: noteSlug)
                await runState.addExportedAttachments(conversion.attachments.count)

                let filename = noteNameAllocator.allocate(baseName: stub.title, ext: "md")
                let mdURL = folderDir.appendingPathComponent(filename)

                let frontmatter = YAMLFrontmatter.render(
                    title: stub.title,
                    folderPath: folder.pathComponents.joined(separator: "/"),
                    account: accountName,
                    createdAt: stub.createdAt,
                    modifiedAt: stub.modifiedAt
                )

                var md = frontmatter + "\n" + conversion.markdownBody

                // If attachment export produced files, append an "Attachments" section for any that
                // weren't already embedded as images in the converted markdown.
                if !attachmentResult.exports.isEmpty {
                    let needsSectionHeader = attachmentResult.exports.contains { exp in
                        switch exp.kind {
                        case .image:
                            return !md.contains(exp.relativePath)
                        case .file:
                            return true
                        }
                    }
                    if needsSectionHeader {
                        md += "\n\n## Attachments\n\n"
                    }

                    for exp in attachmentResult.exports {
                        switch exp.kind {
                        case .image:
                            if !md.contains(exp.relativePath) {
                                md += "![image](\(exp.relativePath))\n"
                            }
                        case .file:
                            let label = exp.originalName ?? (exp.relativePath as NSString).lastPathComponent
                            md += "- [\(label)](\(exp.relativePath))\n"
                        }
                    }
                }
                try md.write(to: mdURL, atomically: true, encoding: .utf8)
                await runState.incrementExported()
            } catch {
                let msg = UserPresentableError(error).message
                logger.error("Failed note \(stub.title): \(msg)")
                await runState.addFailure(ExportManifest.Failure(
                    account: accountName,
                    folderPath: folder.pathComponents.joined(separator: "/"),
                    noteTitle: stub.title,
                    noteID: stub.id,
                    error: msg
                ))
            }
        }

        for child in folder.children {
            try Task.checkCancellation()
            try await exportFolderSubtree(
                folder: child,
                accountName: accountName,
                accountDir: accountDir,
                pathMap: pathMap,
                workspace: workspace,
                runState: runState,
                emitProgress: emitProgress
            )
        }
    }
}

private actor ExportRunStateCollector {
    struct Snapshot: Sendable {
        var totalNotes: Int
        var processed: Int
        var exported: Int
        var attachmentsExported: Int
    }

    private let total: Int
    private var processedCount: Int = 0
    private var exportedCount: Int = 0
    private var attachmentsCount: Int = 0
    private var failureItems: [ExportManifest.Failure] = []

    init(totalNotes: Int) {
        self.total = totalNotes
    }

    func incrementProcessed() {
        processedCount += 1
    }

    func incrementExported() {
        exportedCount += 1
    }

    func addExportedAttachments(_ n: Int) {
        attachmentsCount += n
    }

    func addFailure(_ f: ExportManifest.Failure) {
        failureItems.append(f)
    }

    func snapshot() -> Snapshot {
        Snapshot(totalNotes: total, processed: processedCount, exported: exportedCount, attachmentsExported: attachmentsCount)
    }

    func failures() -> [ExportManifest.Failure] {
        failureItems
    }
}

private enum HTMLImageRewriter {
    /// Rewrites `<img ...>` tags by replacing their `src="..."` with the exported `relativePath` values in order.
    /// If a tag has no `src`, one is inserted.
    static func rewriteImgSrcSequentially(html: String, images: [AttachmentExportResult.Export]) -> String {
        guard !images.isEmpty else { return html }
        var idx = 0
        return html.replacingOccurrences(
            of: #"(?is)<img\b[^>]*>"#,
            with: { match in
                guard idx < images.count else { return match }
                let replacementSrc = images[idx].relativePath
                idx += 1

                // Replace existing src=... if present.
                if match.range(of: #"(?is)\bsrc\s*=\s*["'][^"']*["']"#, options: .regularExpression) != nil {
                    return match.replacingOccurrences(
                        of: #"(?is)\bsrc\s*=\s*["'][^"']*["']"#,
                        with: #"src="\#(replacementSrc)""#,
                        options: .regularExpression
                    )
                }

                // Otherwise insert src before closing bracket.
                if let insertAt = match.lastIndex(of: ">") {
                    var m = match
                    m.insert(contentsOf: #" src="\#(replacementSrc)""#, at: insertAt)
                    return m
                }
                return match
            }
        )
    }
}

private extension String {
    func replacingOccurrences(of pattern: String, with transform: (String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return self }
        let ns = self as NSString
        let matches = regex.matches(in: self, options: [], range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return self }

        var out = self
        // Replace from end to keep ranges stable.
        for m in matches.reversed() {
            let s = ns.substring(with: m.range)
            let r = transform(s)
            out = (out as NSString).replacingCharacters(in: m.range, with: r)
        }
        return out
    }
}

private enum YAMLFrontmatter {
    static func render(title: String, folderPath: String, account: String, createdAt: Date?, modifiedAt: Date?) -> String {
        let iso = ISO8601DateFormatter()
        let created = createdAt.map(iso.string(from:)) ?? ""
        let modified = modifiedAt.map(iso.string(from:)) ?? ""

        // YAML single-quote escaping: ' -> ''
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }

        return """
        ---
        title: \(q(title))
        folderPath: \(q(folderPath))
        account: \(q(account))
        createdAt: \(q(created))
        modifiedAt: \(q(modified))
        source: "Apple Notes"
        ---
        """
    }
}

private enum ExporterTemplates {
    static let limitations: [String] = [
        "Attachments/images are exported best-effort from a note’s rich text. Some content types may not export fully.",
        "Markdown conversion is pragmatic and may not preserve complex layouts.",
        "Notes scripting performance depends on Notes.app; very large libraries can take time."
    ]

    static let exportReadme: String = """
    ## Notes → Markdown Backup (Export)

    This ZIP was created by **Notes → Markdown Backup**.

    ### Structure

    - `manifest.json`: metadata, counts, and failures
    - `<Account>/...`: folders matching Notes
      - `<Note>.md`: note content with YAML frontmatter
      - `assets/<note-slug>/...`: extracted attachments (best-effort)

    ### Notes & limitations

    - Attachments/images are exported best-effort by extracting file attachments from the note’s rich text.
    - Some Notes content (drawings, scans, certain inline objects) may not export fully.
    - Formatting is not guaranteed to match Notes exactly.

    """
}

private struct FolderSelection: Sendable {
    struct Selected: Sendable {
        var folder: NotesFolder
    }

    var selectedFolders: [Selected]

    var selectedFolderCount: Int { selectedFolders.count }

    init(library: NotesLibrary, selectedFolderIDs: Set<String>) {
        // De-duplicate by removing descendants when an ancestor is selected.
        // We do this per-account by walking each tree.
        var out: [Selected] = []

        for account in library.accounts {
            for root in account.rootFolders {
                FolderSelection.select(root, selectedIDs: selectedFolderIDs, out: &out)
            }
        }

        self.selectedFolders = out
    }

    private static func select(_ folder: NotesFolder, selectedIDs: Set<String>, out: inout [Selected]) {
        if selectedIDs.contains(folder.id) {
            out.append(Selected(folder: folder))
            return // selecting a folder implies its subtree
        }
        for child in folder.children {
            select(child, selectedIDs: selectedIDs, out: &out)
        }
    }

    func countNotes(using provider: NotesProviding, logger: Logger) async throws -> Int {
        var total = 0
        for sel in selectedFolders {
            total += try await countNotes(folder: sel.folder, provider: provider, logger: logger)
        }
        return total
    }

    private func countNotes(folder: NotesFolder, provider: NotesProviding, logger: Logger) async throws -> Int {
        try Task.checkCancellation()
        let stubs = try await provider.listNoteStubs(folderID: folder.id)
        var total = stubs.count
        for child in folder.children {
            total += try await countNotes(folder: child, provider: provider, logger: logger)
        }
        return total
    }
}

private struct ExportPathMap: Sendable {
    private var folderToAccount: [String: NotesAccount] = [:]
    private var accountDirNames: [String: String] = [:] // accountID -> safe
    private var folderSafePath: [String: String] = [:] // folderID -> safe relative path

    init(library: NotesLibrary) {
        var accountAllocator = UniqueDirectoryAllocator()
        for account in library.accounts {
            let safeDir = accountAllocator.allocate(account.name)
            accountDirNames[account.id] = safeDir.isEmpty ? "Account" : safeDir

            var rootAllocator = UniqueDirectoryAllocator()
            for root in account.rootFolders {
                build(folder: root, account: account, parentSafePath: "", allocator: &rootAllocator)
            }
        }
    }

    func account(forFolderID folderID: String) -> NotesAccount? {
        folderToAccount[folderID]
    }

    func safeAccountDirName(accountID: String, accountName: String) -> String {
        accountDirNames[accountID] ?? Slugify.filename(accountName)
    }

    func safeFolderPath(for folder: NotesFolder) -> String {
        folderSafePath[folder.id] ?? folder.pathComponents.map { Slugify.filename($0) }.joined(separator: "/")
    }

    private mutating func build(
        folder: NotesFolder,
        account: NotesAccount,
        parentSafePath: String,
        allocator: inout UniqueDirectoryAllocator
    ) {
        folderToAccount[folder.id] = account
        let safeName = allocator.allocate(folder.name)
        let myPath = parentSafePath.isEmpty ? safeName : parentSafePath + "/" + safeName
        folderSafePath[folder.id] = myPath

        var childAllocator = UniqueDirectoryAllocator()
        for child in folder.children {
            build(folder: child, account: account, parentSafePath: myPath, allocator: &childAllocator)
        }
    }
}

private struct UniqueDirectoryAllocator: Sendable {
    private var counts: [String: Int] = [:]

    mutating func allocate(_ name: String) -> String {
        let clean = Slugify.filename(name)
        let n = (counts[clean] ?? 0) + 1
        counts[clean] = n
        if n == 1 { return clean }
        return "\(clean) (\(n))"
    }
}

