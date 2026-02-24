import SwiftUI

/// Displays an AI-generated exercise image when available, falling back to the
/// existing SF Symbol illustration (`ExerciseIllustrationView`) otherwise.
struct ExerciseImageView: View {
    let exercise: RehabExercise
    var isCompact: Bool = false

    @State private var loadedImage: UIImage?
    @State private var hasCheckedImage = false

    private var imageSize: CGFloat { isCompact ? 50 : 280 }
    private var cornerRadius: CGFloat { isCompact ? 10 : 16 }

    var body: some View {
        Group {
            if let image = loadedImage {
                imageContent(image)
            } else {
                fallbackContent
            }
        }
        .task {
            guard !hasCheckedImage else { return }
            hasCheckedImage = true
            loadedImage = await ExerciseImageService.shared.loadImage(for: exercise)
        }
    }

    // MARK: - Image Content

    @ViewBuilder
    private func imageContent(_ image: UIImage) -> some View {
        if isCompact {
            compactImageView(image)
        } else {
            fullImageView(image)
        }
    }

    private func compactImageView(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: imageSize, height: imageSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(difficultyColor.opacity(0.3), lineWidth: 1.5)
            )
    }

    private func fullImageView(_ image: UIImage) -> some View {
        VStack(spacing: AppSpacing.md) {
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

            // Difficulty badge
            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Fallback (SF Symbol)

    private var fallbackContent: some View {
        ExerciseIllustrationView(
            iconName: ExerciseIconMapper.icon(for: exercise),
            difficulty: exercise.difficulty,
            isCompact: isCompact
        )
    }

    // MARK: - Helpers

    private var difficultyColor: Color {
        switch exercise.difficulty {
        case .beginner: return .green
        case .intermediate: return .blue
        case .advanced: return .purple
        }
    }
}
