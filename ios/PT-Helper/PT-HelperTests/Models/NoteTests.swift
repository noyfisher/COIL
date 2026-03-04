import XCTest
@testable import PT_Helper

// MARK: - Note Tests

final class NoteTests: XCTestCase {

    func testNoteCreation() {
        let note = Note(content: "Feeling better today")
        XCTAssertEqual(note.content, "Feeling better today")
        XCTAssertNotNil(note.dateCreated)
    }

    func testNoteUniqueIds() {
        let n1 = Note(content: "A")
        let n2 = Note(content: "B")
        XCTAssertNotEqual(n1.id, n2.id)
    }
}
