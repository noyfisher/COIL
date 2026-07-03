import SwiftUI

/// Tap-to-select body-area picker for onboarding injury/surgery entry.
///
/// Replaces the free-text "Body area (e.g. Left Knee)" fields with a chip cloud
/// of common regions plus a "Custom…" fallback. Structured selection produces
/// clean, consistent strings (no "l knee" vs "Left Knee" drift for history-
/// relevance filtering / AI prompts) and previews the body-region vocabulary the
/// rest of the app uses. Reuses the shared `FlowLayout` and onboarding chip
/// styling. Full alignment with the canonical `BodyRegion` keys is deferred to
/// the assessment/body-map phase (audit item #19).
struct BodyAreaChipPicker: View {
    @Binding var bodyArea: String
    var accent: Color = AppColors.accent

    @State private var isCustom = false

    /// Common PT regions, side-qualified where laterality matters.
    static let commonAreas = [
        "Neck", "Left Shoulder", "Right Shoulder", "Upper Back", "Lower Back",
        "Left Elbow", "Right Elbow", "Left Wrist", "Right Wrist",
        "Left Hip", "Right Hip", "Left Knee", "Right Knee",
        "Left Ankle", "Right Ankle"
    ]

    private var matchesCommon: Bool {
        Self.commonAreas.contains { $0.caseInsensitiveCompare(bodyArea) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(Self.commonAreas, id: \.self) { area in
                    chip(label: area,
                         selected: !isCustom && bodyArea.caseInsensitiveCompare(area) == .orderedSame) {
                        bodyArea = area
                        isCustom = false
                    }
                }
                chip(label: "Custom…", selected: isCustom) {
                    isCustom = true
                    if matchesCommon { bodyArea = "" }
                }
            }

            if isCustom || (!bodyArea.isEmpty && !matchesCommon) {
                DarkTextField(placeholder: "Body area (e.g. Left Forearm)", text: $bodyArea)
            }
        }
        .onAppear {
            // A pre-filled custom value (e.g. resumed draft) starts in custom mode.
            if !bodyArea.isEmpty && !matchesCommon { isCustom = true }
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppFonts.smallMedium)
                .foregroundColor(.white)
                .padding(.vertical, AppSpacing.xs + 2)
                .padding(.horizontal, AppSpacing.sm + 2)
                .background(selected ? accent : OnboardingColors.chipIdle)
                .cornerRadius(AppCorners.small)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCorners.small)
                        .stroke(selected ? Color.clear : OnboardingColors.chipBorder, lineWidth: 1)
                )
        }
        .accessibilityIdentifier("onboarding.bodyAreaChip")
    }
}
