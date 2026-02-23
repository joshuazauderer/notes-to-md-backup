import Foundation

enum HTMLToMarkdown {
    static func convert(_ html: String) -> String {
        // Pragmatic conversion: handle a small subset we commonly see from Notes, then strip tags.
        var s = html
        s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")

        // Links: <a href="...">text</a>
        s = s.replacingOccurrences(
            of: #"(?is)<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#,
            with: "[$2]($1)",
            options: .regularExpression
        )

        // Bold / italic.
        s = s.replacingOccurrences(of: #"(?is)</?(strong|b)>"#, with: "**", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</?(em|i)>"#, with: "_", options: .regularExpression)

        // Line breaks / paragraphs.
        s = s.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</p>\s*<p[^>]*>"#, with: "\n\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)<p[^>]*>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</p>"#, with: "\n\n", options: .regularExpression)

        // List items.
        s = s.replacingOccurrences(of: #"(?is)<li[^>]*>"#, with: "- ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</li>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?is)</?(ul|ol)[^>]*>"#, with: "\n", options: .regularExpression)

        // Images: <img src="...">
        s = s.replacingOccurrences(
            of: #"(?is)<img\s+[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#,
            with: "![]($1)\n",
            options: .regularExpression
        )

        // Strip remaining tags.
        s = s.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)

        // Decode a few entities.
        s = s.replacingOccurrences(of: "&nbsp;", with: " ")
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;", with: "<")
        s = s.replacingOccurrences(of: "&gt;", with: ">")
        s = s.replacingOccurrences(of: "&quot;", with: "\"")
        s = s.replacingOccurrences(of: "&#39;", with: "'")

        // Normalize spacing.
        s = s.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s + "\n"
    }
}

