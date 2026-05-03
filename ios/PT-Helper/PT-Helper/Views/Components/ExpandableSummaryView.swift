import SwiftUI

struct ExpandableSummaryView: View {
    enum Presentation {
        case card(icon: String, iconColor: Color, title: String)
        case inline
    }

    let fullText: String
    let presentation: Presentation
    let detailTitle: String
    let detailAnalyticsName: String
    let accessibilityPrefix: String
    var previewFont: Font = .body
    var previewColor: Color = AppColors.primaryText

    var body: some View {
        let result = fullText.sentencePreview()

        if result.preview.isEmpty {
            EmptyView()
        } else {
            switch presentation {
            case .card(let icon, let iconColor, let title):
                CardSection(icon: icon, color: iconColor, title: title) {
                    content(preview: result.preview, isTruncated: result.isTruncated)
                }
            case .inline:
                content(preview: result.preview, isTruncated: result.isTruncated)
            }
        }
    }

    @ViewBuilder
    private func content(preview: String, isTruncated: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(preview)
                .font(previewFont)
                .foregroundColor(previewColor)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isTruncated {
                NavigationLink(destination: FullTextDetailView(
                    navigationTitle: detailTitle,
                    bodyText: fullText,
                    analyticsName: detailAnalyticsName
                )) {
                    HStack(spacing: AppSpacing.xs) {
                        Text("See Full Overview")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(AppColors.accent)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(accessibilityPrefix).seeFullOverviewButton")
                .accessibilityHint("Opens full text on a new screen")
            }
        }
    }
}
