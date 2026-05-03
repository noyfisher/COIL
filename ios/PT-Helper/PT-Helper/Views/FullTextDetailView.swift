import SwiftUI

struct FullTextDetailView: View {
    let navigationTitle: String
    let bodyText: String
    let analyticsName: String

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            ScrollView {
                Text(bodyText)
                    .font(.body)
                    .foregroundColor(AppColors.primaryText)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.xl)
            }
            .accessibilityIdentifier("fullTextDetail.scrollView")
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(analyticsName)
    }
}
