import SwiftUI

/// Reusable view for entering per-region pain levels.
/// Users can add body regions and rate pain 0-10 for each.
struct RegionPainInputView: View {
    @Binding var regionPainLevels: [String: Double]
    var suggestedRegions: [String] = []

    @State private var showRegionPicker = false

    /// All available body regions, sourced from the SAME canonical `BodyZone`
    /// definitions the 3D body map uses, so post-workout region pain lines up with
    /// what the body map / analysis records (audit #19). Previously this list had
    /// drifted (e.g. "core" vs "abdomen", "left_upper_thigh" vs "left_thigh",
    /// "left_lower_leg" vs "left_calf_shin") and omitted glutes/hamstrings, leaving
    /// gaps in progress charts and recovery insights.
    static let allRegions: [String] = BodyZone.allCases.flatMap { $0.regionZoneKeys }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 28, height: 28)
                    .background(AppColors.accentTint)
                    .cornerRadius(AppCorners.small)

                Text("Pain by Region")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button(action: { showRegionPicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.accentText)
                }
            }

            if regionPainLevels.isEmpty {
                Text("Tap \"Add\" to track pain for specific body regions")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, AppSpacing.sm)
            } else {
                ForEach(sortedRegionKeys, id: \.self) { region in
                    regionRow(for: region)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        .sheet(isPresented: $showRegionPicker) {
            regionPickerSheet
        }
    }

    // MARK: - Region Row

    private func regionRow(for region: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(Self.displayName(for: region))
                    .font(.caption.weight(.medium))

                Spacer()

                Text(String(format: "%.0f", regionPainLevels[region] ?? 0))
                    .font(.caption.weight(.bold))
                    .foregroundColor(painColor(for: regionPainLevels[region] ?? 0))

                Button(action: { regionPainLevels.removeValue(forKey: region) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            Slider(
                value: Binding(
                    get: { regionPainLevels[region] ?? 0 },
                    set: { regionPainLevels[region] = $0 }
                ),
                in: 0...10,
                step: 1
            )
            .tint(painColor(for: regionPainLevels[region] ?? 0))
        }
    }

    // MARK: - Region Picker Sheet

    private var regionPickerSheet: some View {
        NavigationStack {
            List {
                if !suggestedRegions.isEmpty {
                    Section("Suggested (from your plan)") {
                        ForEach(suggestedRegions.filter { regionPainLevels[$0] == nil }, id: \.self) { region in
                            regionPickerRow(region)
                        }
                    }
                }

                Section("All Regions") {
                    ForEach(Self.allRegions.filter { regionPainLevels[$0] == nil }, id: \.self) { region in
                        regionPickerRow(region)
                    }
                }
            }
            .navigationTitle("Add Region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showRegionPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func regionPickerRow(_ region: String) -> some View {
        Button(action: {
            regionPainLevels[region] = 0
            showRegionPicker = false
        }) {
            HStack {
                Text(Self.displayName(for: region))
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundColor(AppColors.accent)
            }
        }
    }

    // MARK: - Helpers

    private var sortedRegionKeys: [String] {
        regionPainLevels.keys.sorted()
    }

    private func painColor(for level: Double) -> Color {
        switch Int(level) {
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    /// Converts zone keys like "left_knee" to "Left Knee"
    static func displayName(for zoneKey: String) -> String {
        zoneKey.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
