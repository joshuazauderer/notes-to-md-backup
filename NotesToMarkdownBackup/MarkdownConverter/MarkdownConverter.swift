import AppKit
import Foundation

struct MarkdownConversionResult: Equatable, Sendable {
    var markdownBody: String
    var attachments: [AttachmentRef]
}

struct MarkdownConverter: Sendable {
    func convert(note: NotesNoteContent, assetsBaseURL: URL, noteSlug: String) throws -> MarkdownConversionResult {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: assetsBaseURL, withIntermediateDirectories: true)

        let noteAssetsDir = assetsBaseURL.appendingPathComponent(noteSlug, isDirectory: true)
        try fileManager.createDirectory(at: noteAssetsDir, withIntermediateDirectories: true)

        if let rtfdURL = note.rtfdPackageURL {
            if let res = try? convertFromRTFD(rtfdURL: rtfdURL, noteAssetsDir: noteAssetsDir, noteSlug: noteSlug) {
                return res
            }
        }

        if let html = note.html, !html.isEmpty {
            let md = HTMLToMarkdown.convert(html)
            return MarkdownConversionResult(markdownBody: md, attachments: [])
        }

        return MarkdownConversionResult(markdownBody: MarkdownEscaper.normalizePlainText(note.plainText), attachments: [])
    }

    private func convertFromRTFD(rtfdURL: URL, noteAssetsDir: URL, noteSlug: String) throws -> MarkdownConversionResult {
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]
        let attributed = try NSAttributedString(url: rtfdURL, options: opts, documentAttributes: nil)

        var attachments: [AttachmentRef] = []
        var allocator = UniqueFilenameAllocator()

        var out = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length), options: []) { attrs, range, _ in
            if let attachment = attrs[.attachment] as? NSTextAttachment {
                if let exported = exportAttachment(attachment, into: noteAssetsDir, allocator: &allocator, noteSlug: noteSlug) {
                    attachments.append(exported)
                    out += "![attachment](\(exported.relativePath))"
                }
                return
            }

            let raw = attributed.attributedSubstring(from: range).string
            if raw.isEmpty { return }

            // Apply lightweight rich text handling where it's reasonably safe.
            var text = raw
            if let link = attrs[.link] as? URL {
                let label = MarkdownEscaper.escapeInline(raw)
                text = "[\(label)](\(link.absoluteString))"
            } else {
                text = MarkdownEscaper.escapeInline(raw)
                if !raw.contains("\n"), let font = attrs[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    let isBold = traits.contains(.bold)
                    let isItalic = traits.contains(.italic)
                    if isBold { text = "**\(text)**" }
                    if isItalic { text = "_\(text)_" }
                }
            }

            out += text
        }

        out = MarkdownEscaper.normalizeNewlines(out)
        return MarkdownConversionResult(markdownBody: out, attachments: attachments)
    }

    private func exportAttachment(
        _ attachment: NSTextAttachment,
        into noteAssetsDir: URL,
        allocator: inout UniqueFilenameAllocator,
        noteSlug: String
    ) -> AttachmentRef? {
        guard let wrapper = attachment.fileWrapper else { return nil }

        let preferred = wrapper.preferredFilename ?? wrapper.filename ?? "attachment"
        let base = "\(noteSlug)_\(preferred)"

        if wrapper.isRegularFile, let data = wrapper.regularFileContents {
            let ext = (preferred as NSString).pathExtension
            let allocated = allocator.allocate(baseName: (base as NSString).deletingPathExtension, ext: ext.isEmpty ? "bin" : ext)
            let dest = noteAssetsDir.appendingPathComponent(allocated)
            do {
                try data.write(to: dest, options: .atomic)
                return AttachmentRef(
                    originalFilename: preferred,
                    exportedFilename: allocated,
                    relativePath: "assets/\(noteAssetsDir.lastPathComponent)/\(allocated)",
                    uti: nil
                )
            } catch {
                return nil
            }
        }

        // Some attachments are directories (file packages). Export best-effort.
        if wrapper.isDirectory {
            let ext = (preferred as NSString).pathExtension
            let allocated = allocator.allocate(baseName: (base as NSString).deletingPathExtension, ext: ext.isEmpty ? "package" : ext)
            let dest = noteAssetsDir.appendingPathComponent(allocated)
            do {
                try wrapper.write(to: dest, options: .atomic, originalContentsURL: nil)
                return AttachmentRef(
                    originalFilename: preferred,
                    exportedFilename: allocated,
                    relativePath: "assets/\(noteAssetsDir.lastPathComponent)/\(allocated)",
                    uti: nil
                )
            } catch {
                return nil
            }
        }

        return nil
    }
}

enum MarkdownEscaper {
    static func normalizePlainText(_ s: String) -> String {
        normalizeNewlines(s)
    }

    static func normalizeNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    static func escapeInline(_ s: String) -> String {
        // Minimal escaping to avoid accidental emphasis/link syntax.
        var out = s
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "`", with: "\\`")
        out = out.replacingOccurrences(of: "[", with: "\\[")
        out = out.replacingOccurrences(of: "]", with: "\\]")
        return out
    }
}

