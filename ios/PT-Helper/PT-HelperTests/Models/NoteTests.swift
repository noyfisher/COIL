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

    func testNote_codable_roundTrip() throws {
        let note = Note(content: "Test note")
        let data = try JSONEncoder().encode(note)
        let decoded = try JSONDecoder().decode(Note.self, from: data)

        XCTAssertEqual(decoded.id, note.id)
        XCTAssertEqual(decoded.content, "Test note")
    }

    func testNote_fullInit_setsAllFields() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1000)
        let note = Note(id: id, content: "Custom", dateCreated: date)

        XCTAssertEqual(note.id, id)
        XCTAssertEqual(note.content, "Custom")
        XCTAssertEqual(note.dateCreated, date)
    }
}
