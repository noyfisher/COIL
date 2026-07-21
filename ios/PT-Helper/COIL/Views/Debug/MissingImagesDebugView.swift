#if DEBUG
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

/// Developer-only diagnostic view: surfaces the top entries in the
/// `missingExerciseImages` Firestore collection so we can see, in real time,
/// which AI-generated exercise names didn't have catalog images and what we
/// substituted them to. Compiled OUT of release builds.
///
/// Reachable from Settings → Developer Tools → Image Diagnostics (DEBUG only).
struct MissingImagesDebugView: View {
    @State private var entries: [Entry] = []
    @State private var isLoading = false
    @State private var loadError: String?

    struct Entry: Identifiable {
        let id: String
        let exerciseName: String
        let normalizedKey: String
        let count: Int
        let matchType: String
        let matchedTo: String?
        let substitutedTo: String?
        let source: String
        let lastSeen: Date?
        let targetArea: String?
        let exerciseCategory: String?
    }

    var body: some View {
        List {
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading…").padding(.leading, 8)
                    }
                } else if let err = loadError {
                    Text(err).foregroundColor(.red)
                } else if entries.isEmpty {
                    Text("No entries — either no missing images logged, or the Firestore rule for `missingExerciseImages` reads is denying.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.exerciseName).font(.headline)
                                Spacer()
                                Text("×\(entry.count)").font(.subheadline.monospacedDigit())
                            }
                            Text(entry.normalizedKey)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                badge(label: "match", value: entry.matchType, color: entry.matchType == "none" ? .red : .orange)
                                badge(label: "src", value: entry.source, color: entry.source == "validation" ? .blue : .gray)
                                if let area = entry.targetArea {
                                    badge(label: "area", value: area, color: .gray)
                                }
                            }
                            if let matched = entry.matchedTo {
                                Text("matched → \(matched)").font(.caption2.monospaced())
                            }
                            if let sub = entry.substitutedTo {
                                Text("substituted → \(sub)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                Text("Top \(entries.count) (count desc)")
            } footer: {
                Text("Source: Firestore `missingExerciseImages` collection. Refreshes on appear; pull to retry.")
                    .font(.caption2)
            }
        }
        .navigationTitle("Image Diagnostics")
        .refreshable { await loadAsync() }
        .task { await loadAsync() }
    }

    @ViewBuilder
    private func badge(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2.monospaced()).foregroundColor(.secondary)
            Text(value).font(.caption2).fontWeight(.medium).foregroundColor(color)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.12))
        .cornerRadius(4)
    }

    @MainActor
    private func loadAsync() async {
        guard Auth.auth().currentUser != nil else {
            loadError = "Sign-in required to read Firestore"
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("missingExerciseImages")
                .order(by: "count", descending: true)
                .limit(to: 50)
                .getDocuments()
            entries = snapshot.documents.compactMap { doc in
                let data = doc.data()
                guard let exerciseName = data["exerciseName"] as? String,
                      let normalizedKey = data["normalizedKey"] as? String else { return nil }
                let lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
                return Entry(
                    id: doc.documentID,
                    exerciseName: exerciseName,
                    normalizedKey: normalizedKey,
                    count: data["count"] as? Int ?? 0,
                    matchType: data["matchType"] as? String ?? "?",
                    matchedTo: data["matchedTo"] as? String,
                    substitutedTo: data["substitutedTo"] as? String,
                    source: data["source"] as? String ?? "?",
                    lastSeen: lastSeen,
                    targetArea: data["targetArea"] as? String,
                    exerciseCategory: data["exerciseCategory"] as? String
                )
            }
        } catch {
            loadError = "Read failed: \(error.localizedDescription)\n\nIf this says PERMISSION_DENIED, add an authenticated-read rule for `missingExerciseImages` in firestore.rules."
        }
    }
}
#endif
