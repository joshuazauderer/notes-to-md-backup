import XCTest
@testable import NotesToMarkdownBackup

final class HTMLToMarkdownTests: XCTestCase {
    func testConvertsSimpleHTML() {
        let html = #"<p>Hello <strong>world</strong> <a href="https://example.com">link</a><br/>Line2</p>"#
        let md = HTMLToMarkdown.convert(html)
        XCTAssertTrue(md.contains("Hello **world**"))
        XCTAssertTrue(md.contains("[link](https://example.com)"))
        XCTAssertTrue(md.contains("Line2"))
    }
}

