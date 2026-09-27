import SwiftUI
import FirebaseAuth
import FirebaseFirestore

/// User-facing monitoring/reporting mechanism (Anthropic minors program).
/// Writes a create-only document to the top-level `concernReports` collection;
/// only the Admin SDK reads these. Presented as a sheet from Settings.
struct ReportConcernView: View {
    @Environment(\.dismiss) private var dismiss

    private let categories = [
        "Safety concern",
        "Inappropriate AI response",
        "Privacy concern",
        "Something else"
    ]

    @State private var category = "Safety concern"
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var showError = false
    @State private var errorMessage = ""

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.xl) {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Category")
                                .font(AppFonts.smallSemiBold)
                            Picker("Category", selection: $category) {
                                ForEach(categories, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColors.accent)
                            .accessibilityIdentifier("reportConcern.categoryPicker")
                        }

                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("What happened?")
                                .font(AppFonts.smallSemiBold)
                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text("Describe what happened…")
                                        .font(AppFonts.body)
                                        .foregroundColor(AppColors.mutedText)
                                        .padding(.top, AppSpacing.sm)
                                        .padding(.leading, AppSpacing.xs)
                                }
                                TextEditor(text: $message)
                                    .frame(minHeight: 120)
                                    .scrollContentBackground(.hidden)
                                    .accessibilityIdentifier("reportConcern.messageEditor")
                            }
                            .padding(AppSpacing.sm)
                            .background(AppColors.cardBackground)
                            .cornerRadius(AppCorners.medium)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppCorners.medium)
                                    .stroke(AppColors.cardBorder, lineWidth: 1)
                            )
                        }

                        Button(action: submit) {
                            Text("Submit")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.lg)
                                .background(canSubmit ? AppColors.accent : AppColors.accent.opacity(0.4))
                                .foregroundColor(AppColors.ctaText)
                                .font(AppFonts.cardTitle)
                                .cornerRadius(AppCorners.large)
                        }
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("reportConcern.submitButton")
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .navigationTitle("Report a Concern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .alert("Thank you", isPresented: $showConfirmation) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your report was submitted. If this is an emergency, call 911. If you're in crisis, call or text 988.")
        }
        // A safety/privacy report silently failing is worse than most bugs — show
        // the real failure and let the user retry (the draft is preserved). (P2-03)
        .alert("Couldn't submit", isPresented: $showError) {
            Button("Retry") { submit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .trackScreen("ReportConcern")
    }

    // MARK: - Actions

    private func submit() {
        guard let uid = Auth.auth().currentUser?.uid else {
            errorMessage = "You need to be signed in to submit a report."
            showError = true
            return
        }
        isSubmitting = true
        // addDocument (not a stable id): concernReports is create-only in rules, so
        // an idempotent overwrite isn't permitted. A retry after a transient error
        // that actually succeeded may create a duplicate — harmless for a report,
        // and far better than silently losing a safety/privacy complaint.
        Firestore.firestore().collection("concernReports").addDocument(data: [
            "userId": uid,
            "category": category,
            "message": message.trimmingCharacters(in: .whitespacesAndNewlines),
            "createdAt": FieldValue.serverTimestamp(),
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        ]) { error in
            isSubmitting = false
            if let error {
                errorMessage = "Your report couldn't be sent (\(error.localizedDescription)). Please try again."
                showError = true
            } else {
                showConfirmation = true
            }
        }
    }
}

#Preview {
    ReportConcernView()
}
