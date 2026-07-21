import SwiftUI
import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

@MainActor
class NotesViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var newNoteContent: String = ""
    @Published var loadError: String?
    @Published var isLoading: Bool = false

    private let db = Firestore.firestore()

    init() {
        fetchNotes()
    }

    func fetchNotes() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        db.collection("users").document(uid).collection("notes")
            .order(by: "dateCreated", descending: true)
            .getDocuments { [weak self] snapshot, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isLoading = false
                    if let error = error {
                        AppLogger.data.error("Error fetching notes: \(error.localizedDescription)")
                        self.loadError = "Unable to load your notes. Pull down to retry."
                        return
                    }
                    self.loadError = nil
                    self.notes = snapshot?.documents.compactMap { document -> Note? in
                        let data = document.data()
                        guard let idString = data["id"] as? String,
                              let id = UUID(uuidString: idString),
                              let content = data["content"] as? String else {
                            return nil
                        }
                        let dateCreated = (data["dateCreated"] as? Timestamp)?.dateValue() ?? Date()
                        return Note(id: id, content: content, dateCreated: dateCreated)
                    } ?? []
                }
            }
    }

    func addNote() {
        guard !newNoteContent.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newNote = Note(content: newNoteContent)
        notes.insert(newNote, at: 0) // Add to top since sorted by newest first
        newNoteContent = ""

        // Persist to Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let noteData: [String: Any] = [
            "id": newNote.id.uuidString,
            "content": newNote.content,
            "dateCreated": Timestamp(date: newNote.dateCreated)
        ]
        db.collection("users").document(uid).collection("notes")
            .document(newNote.id.uuidString)
            .setData(noteData) { error in
                if let error = error {
                    AppLogger.data.error("Error saving note: \(error.localizedDescription)")
                }
            }
    }

    func deleteNote(_ note: Note) {
        // Remove locally first for instant UI feedback
        notes.removeAll { $0.id == note.id }

        // Remove from Firestore
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("notes")
            .document(note.id.uuidString)
            .delete { [weak self] error in
                if let error = error {
                    AppLogger.data.error("Error deleting note: \(error.localizedDescription)")
                    // Re-fetch to restore consistent state
                    DispatchQueue.main.async {
                        self?.fetchNotes()
                    }
                }
            }
    }
}
