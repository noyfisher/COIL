import SwiftUI

/// Panel overlaid on the 3D body map during zone drill-down.
/// Shows the sub-regions within the active zone as a toggleable checklist.
struct ZoneSelectionPanel: View {
    @ObservedObject var viewModel: BodyMapViewModel
    let zone: BodyZone
    let onRegionToggle: (BodyRegion) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header
            HStack(spacing: AppSpacing.sm) {
                Button(action: onBack) {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Back")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(AppColors.primaryText.opacity(0.8))
                }

                Spacer()

                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: zone.iconName)
                        .font(.system(size: 14))
                    Text(zone.displayName)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(AppColors.primaryText)
            }
            .padding(.bottom, AppSpacing.xs)

            Divider()
                .background(AppColors.elevatedSurface.opacity(0.5))

            // Sub-region list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppSpacing.xs) {
                    ForEach(viewModel.regions(in: zone), id: \.id) { region in
                        Button(action: { onRegionToggle(region) }) {
                            HStack(spacing: AppSpacing.sm) {
                                Circle()
                                    .fill(regionColor(for: region))
                                    .frame(width: 10, height: 10)

                                Text(region.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(AppColors.primaryText)
                                    .lineLimit(1)

                                Spacer()

                                if region.isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color(uiColor: BodyMapConstants.highlightColor))
                                } else {
                                    Image(systemName: "circle")
                                        .font(.system(size: 16))
                                        .foregroundColor(AppColors.primaryText.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                region.isSelected
                                    ? Color(uiColor: BodyMapConstants.highlightColor).opacity(0.15)
                                    : AppColors.elevatedSurface.opacity(0.15)
                            )
                            .cornerRadius(AppCorners.small)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.elevatedSurface)
        .cornerRadius(AppCorners.card)
        .trackScreen("ZoneSelection")
    }

    private func regionColor(for region: BodyRegion) -> Color {
        let baseKey = BodyMapConstants.regionBaseKey(region.zoneKey)
        if let color = BodyMapConstants.regionColors[baseKey] {
            return Color(uiColor: color)
        }
        return .gray
    }
}
