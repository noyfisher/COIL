import SwiftUI

struct NotesView: View {
    @StateObject private var viewModel = NotesViewModel()
    @FocusState private var isEditorFocused: Bool
    @State private var noteToDelete: Note?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ZStack {
            AppColors.bgGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // New note input
                    CardSection(icon: "square.and.pencil", color: AppColors.accent, title: "New Note") {
                        VStack(spacing: AppSpacing.md) {
                            ZStack(alignment: .topLeading) {
                                if viewModel.newNoteContent.isEmpty {
                                    Text("How are you feeling today? Any progress or setbacks...")
                                        .foregroundColor(AppColors.secondaryText.opacity(0.5))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                }
                                TextEditor(text: $viewModel.newNoteContent)
                                    .focused($isEditorFocused)
                                    .frame(minHeight: 100)
                                    .scrollContentBackground(.hidden)
                                    .padding(AppSpacing.xs)
                            }
                            .background(AppColors.inputBackground)
                            .cornerRadius(AppCorners.medium)

                            Button(action: {
                                viewModel.addNote()
                                isEditorFocused = false
                            }) {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Save Note")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(isDisabled: viewModel.newNoteContent.isEmpty))
                            .disabled(viewModel.newNoteContent.isEmpty)
                        }
                    }

                    // Notes list
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, AppSpacing.xl)
                    } else if viewModel.notes.isEmpty {
                        EmptyStateView(
                            icon: "note.text",
                            title: "No Notes Yet",
                            subtitle: "Start tracking your recovery by adding your first note above"
                        )
                    } else {
                        SectionHeader(icon: "clock.arrow.circlepath", color: AppColors.accent, title: "Previous Notes")

                        ForEach(viewModel.notes) { note in
                            noteCard(for: note)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Recovery Notes")
        .navigationBarTitleDisplayMode(.inline)
        .onTapGesture {
            isEditorFocused = false
        }
        .refreshable {
            viewModel.fetchNotes()
        }
        .trackScreen("Notes")
        .alert("Delete Note", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                noteToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let note = noteToDelete {
                    viewModel.deleteNote(note)
                    noteToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this note? This cannot be undone.")
        }
    }

    private func noteCard(for note: Note) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Image(systemName: "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.success)
                .frame(width: 28, height: 28)
                .background(AppColors.success.opacity(0.15))
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(note.content)
                    .font(.body)
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(note.dateCreated, style: .date)
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()

            Button {
                noteToDelete = note
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(AppColors.danger.opacity(0.7))
                    .padding(AppSpacing.sm)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
    }
}
