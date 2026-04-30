import SwiftUI

/// Detail-view variant of `ExerciseImageView`: shows the start and end pose
/// illustrations as two pages of a swipeable `TabView`. Replaces the auto
/// cross-fade with manual swipe-to-toggle so the user can dwell on either
/// pose. Falls through to `ExerciseImageView` (with its auto-fade behavior
/// + on-demand generation + fallback icon) when no end image is available.
struct ExerciseImagePagerView: View {
    let exercise: RehabExercise

    @State private var startImage: UIImage?
    @State private var endImage: UIImage?
    @State private var page: Int = 0
    @State private var didLoadEnd = false

    private let imageSize: CGFloat = 280
    private let cornerRadius: CGFloat = 16

    var body: some View {
        Group {
            if let start = startImage, let end = endImage {
                pager(start: start, end: end)
            } else {
                // No end image (or images not yet loaded) — fall back to the
                // existing single-image behavior. ExerciseImageView handles
                // loading state, on-demand generation, and SF-symbol fallback.
                ExerciseImageView(exercise: exercise)
            }
        }
        .task(id: exercise.id) {
            // Reset on exercise change so a recycled view doesn't show prior poses.
            startImage = nil
            endImage = nil
            page = 0
            didLoadEnd = false

            await ExerciseImageService.shared.fetchRemoteAliases()
            startImage = await ExerciseImageService.shared.loadImage(for: exercise)
            if startImage != nil {
                endImage = await ExerciseImageService.shared.loadEndImage(for: exercise)
            }
            didLoadEnd = true
        }
    }

    private func pager(start: UIImage, end: UIImage) -> some View {
        VStack(spacing: AppSpacing.md) {
            TabView(selection: $page) {
                pageImage(start, label: "Start").tag(0)
                pageImage(end, label: "End").tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: imageSize + 32) // image + room for index dots

            HStack(spacing: AppSpacing.xs) {
                Text(page == 0 ? "Start position" : "End position")
                    .font(.caption.weight(.medium))
                    .foregroundColor(AppColors.secondaryText)
                Image(systemName: "hand.draw")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                Text("swipe")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
            }

            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            page == 0
                ? "Start position for \(exercise.name)"
                : "End position for \(exercise.name)"
        )
        .accessibilityHint("Swipe horizontally to switch between start and end positions.")
    }

    @ViewBuilder
    private func pageImage(_ image: UIImage, label: String) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: imageSize, maxHeight: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(difficultyColor.opacity(0.15), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .accessibilityLabel("\(label) position")
    }

    private var difficultyColor: Color {
        switch exercise.difficulty {
        case .beginner: return .green
        case .intermediate: return AppColors.accent
        case .advanced: return AppColors.accent
        }
    }
}
