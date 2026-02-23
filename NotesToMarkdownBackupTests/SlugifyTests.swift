import XCTest
@testable import NotesToMarkdownBackup

final class SlugifyTests: XCTestCase {
    func testFilenameBasicSanitization() {
        XCTAssertEqual(Slugify.filename(" Hello / World "), "Hello _ World")
        XCTAssertEqual(Slugify.filename(""), "Untitled")
        XCTAssertFalse(Slugify.filename("a:b*c?d").contains(":"))
    }

    func testUniqueFilenameAllocatorDeDupes() {
        var a = UniqueFilenameAllocator()
        XCTAssertEqual(a.allocate(baseName: "Note", ext: "md"), "Note.md")
        XCTAssertEqual(a.allocate(baseName: "Note", ext: "md"), "Note (2).md")
        XCTAssertEqual(a.allocate(baseName: "Note", ext: "md"), "Note (3).md")
    }
}

