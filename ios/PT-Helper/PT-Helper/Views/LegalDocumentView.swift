import SwiftUI

/// Reusable sheet view for rendering legal documents (Privacy Policy, Terms of Service).
/// Accepts markdown content as a string and renders it using SwiftUI's AttributedString.
struct LegalDocumentView: View {
    let title: String
    let markdownContent: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let attributedContent = try? AttributedString(
                    markdown: markdownContent,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributedContent)
                        .font(.subheadline)
                        .foregroundColor(AppColors.primaryText)
                        .padding(AppSpacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Fallback: render as plain text
                    Text(markdownContent)
                        .font(.subheadline)
                        .foregroundColor(AppColors.primaryText)
                        .padding(AppSpacing.xl)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(AppColors.pageBackground)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .trackScreen(title)
    }
}
