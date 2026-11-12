import XCTest
@testable import COIL

// MARK: - NotesViewModel Tests

@MainActor
final class NotesViewModelTests: XCTestCase {

    func testInitialState() {
        let vm = NotesViewModel()
        XCTAssertTrue(vm.notes.isEmpty)
        XCTAssertEqual(vm.newNoteContent, "")
    }

    func testAddNote_Success() {
        let vm = NotesViewModel()
        vm.newNoteContent = "Feeling better today"
        vm.addNote()

        XCTAssertEqual(vm.notes.count, 1)
        XCTAssertEqual(vm.notes.first?.content, "Feeling better today")
        XCTAssertEqual(vm.newNoteContent, "", "Content should be cleared after adding")
    }

    func testAddNote_EmptyContentIgnored() {
        let vm = NotesViewModel()
        vm.newNoteContent = ""
        vm.addNote()

        XCTAssertTrue(vm.notes.isEmpty, "Empty notes should not be added")
    }

    func testAddMultipleNotes() {
        let vm = NotesViewModel()

        vm.newNoteContent = "Note 1"
        vm.addNote()
        vm.newNoteContent = "Note 2"
        vm.addNote()
        vm.newNoteContent = "Note 3"
        vm.addNote()

        XCTAssertEqual(vm.notes.count, 3)
        // Notes are inserted at front (newest first)
        XCTAssertEqual(vm.notes[0].content, "Note 3")
        XCTAssertEqual(vm.notes[1].content, "Note 2")
        XCTAssertEqual(vm.notes[2].content, "Note 1")
    }

    func testAddNote_ClearsContentAfterAdd() {
        let vm = NotesViewModel()
        vm.newNoteContent = "Test"
        vm.addNote()
        XCTAssertEqual(vm.newNoteContent, "")
    }

    func testAddNote_EachHasUniqueId() {
        let vm = NotesViewModel()
        vm.newNoteContent = "A"
        vm.addNote()
        vm.newNoteContent = "B"
        vm.addNote()

        XCTAssertNotEqual(vm.notes[0].id, vm.notes[1].id)
    }

    func testDeleteNote_removesFromLocalArray() {
        let vm = NotesViewModel()
        vm.newNoteContent = "To delete"
        vm.addNote()
        XCTAssertEqual(vm.notes.count, 1)

        let note = vm.notes[0]
        vm.deleteNote(note)
        XCTAssertTrue(vm.notes.isEmpty, "Note should be removed locally")
    }

    func testDeleteNote_nonexistentNote_noChange() {
        let vm = NotesViewModel()
        vm.newNoteContent = "Keep me"
        vm.addNote()

        let fake = Note(content: "Not in list")
        vm.deleteNote(fake)
        XCTAssertEqual(vm.notes.count, 1, "Deleting a non-existent note should not affect the list")
    }
}
