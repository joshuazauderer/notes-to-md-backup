import Foundation

enum Slugify {
    static func filename(_ input: String, maxLength: Int = 120) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = "Untitled" }

        // Normalize and remove combining marks for safer cross-platform filenames.
        s = s.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)

        // Replace forbidden path characters and control characters.
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.illegalCharacters)
            .union(.controlCharacters)

        s = s.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "_" : Character(scalar)
        }.reduce(into: "") { $0.append($1) }

        // Collapse whitespace/underscores.
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        while s.contains("__") { s = s.replacingOccurrences(of: "__", with: "_") }

        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
        if s.isEmpty { s = "Untitled" }

        if s.count > maxLength {
            let idx = s.index(s.startIndex, offsetBy: maxLength)
            s = String(s[..<idx]).trimmingCharacters(in: CharacterSet(charactersIn: " ._"))
            if s.isEmpty { s = "Untitled" }
        }

        return s
    }
}

struct UniqueFilenameAllocator {
    private var counts: [String: Int] = [:]

    mutating func allocate(baseName: String, ext: String) -> String {
        let cleanBase = Slugify.filename(baseName)
        let key = "\(cleanBase).\(ext)"
        let n = (counts[key] ?? 0) + 1
        counts[key] = n

        if n == 1 {
            return "\(cleanBase).\(ext)"
        }
        return "\(cleanBase) (\(n)).\(ext)"
    }
}

