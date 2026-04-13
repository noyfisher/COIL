import SwiftUI

/// Displays AI-generated exercise images when available.
/// Supports: single image, start+end pair (side-by-side), on-demand generation with loading state,
/// and SF Symbol fallback.
struct ExerciseImageView: View {
    let exercise: RehabExercise
    var isCompact: Bool = false

    @State private var startImage: UIImage?
    @State private var endImage: UIImage?
    @State private var isGenerating = false
    @State private var generationFailed = false
    @State private var hasCheckedImage = false

    private var imageSize: CGFloat { isCompact ? 50 : 280 }
    private var cornerRadius: CGFloat { isCompact ? 10 : 16 }

    var body: some View {
        Group {
            if let start = startImage {
                if let end = endImage, !isCompact {
                    imagePairContent(start: start, end: end)
                } else {
                    imageContent(start)
                }
            } else if isGenerating {
                generatingContent
            } else {
                fallbackContent
            }
        }
        .task {
            guard !hasCheckedImage else { return }
            hasCheckedImage = true

            // Fetch Firestore aliases on first image load
            await ExerciseImageService.shared.fetchRemoteAliases()

            // Try normal load
            startImage = await ExerciseImageService.shared.loadImage(for: exercise)

            if startImage != nil {
                // Also try loading end image for side-by-side
                endImage = await ExerciseImageService.shared.loadEndImage(for: exercise)
            } else if !isCompact {
                // No image found — trigger on-demand generation (full mode only)
                isGenerating = true
                let generated = await ExerciseImageService.shared.requestImageGeneration(for: exercise)
                if let generated {
                    startImage = generated
                } else {
                    generationFailed = true
                }
                isGenerating = false
            }

            // Log if missing or only fuzzy-matched
            ExerciseImageService.shared.logMissingImageIfNeeded(for: exercise)
        }
    }

    // MARK: - Single Image Content

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

    // MARK: - Side-by-Side Pair Content

    private func imagePairContent(start: UIImage, end: UIImage) -> some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.md) {
                labeledImage(start, label: "Start")
                labeledImage(end, label: "End")
            }

            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
    }

    private func labeledImage(_ image: UIImage, label: String) -> some View {
        VStack(spacing: AppSpacing.xs) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 130, maxHeight: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(difficultyColor.opacity(0.15), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.06), radius: 8, y: 3)

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Generating State

    private var generatingContent: some View {
        VStack(spacing: AppSpacing.md) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppColors.cardBackground)
                .frame(width: imageSize, height: imageSize)
                .overlay(
                    VStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Creating illustration...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                )
                .modifier(ShimmerModifier())

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
        case .intermediate: return AppColors.accent
        case .advanced: return AppColors.accent
        }
    }
}

// ShimmerModifier is defined in DesignSystem.swift
