import SwiftUI

// MARK: - Exercise Illustration View

/// A polished exercise icon display with gradient background and difficulty badge.
/// Supports full-size (detail view) and compact (card) modes.
struct ExerciseIllustrationView: View {
    let iconName: String
    let difficulty: RehabExercise.Difficulty
    var isCompact: Bool = false

    private var iconSize: CGFloat { isCompact ? 28 : 60 }
    private var circleSize: CGFloat { isCompact ? 50 : 140 }

    private var gradientColors: [Color] {
        switch difficulty {
        case .beginner:
            return [AppColors.success.opacity(0.7), AppColors.success]
        case .intermediate:
            return [AppColors.accent.opacity(0.7), AppColors.accent]
        case .advanced:
            return [AppColors.accent.opacity(0.7), AppColors.accent]
        }
    }

    private var difficultyLabel: String {
        switch difficulty {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    private var difficultyColor: Color {
        switch difficulty {
        case .beginner: return AppColors.success
        case .intermediate: return AppColors.accent
        case .advanced: return AppColors.accent
        }
    }

    var body: some View {
        if isCompact {
            compactView
        } else {
            fullView
        }
    }

    // MARK: - Full View (Exercise Detail)

    private var fullView: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                gradientColors[0].opacity(0.15),
                                gradientColors[1].opacity(0.05),
                                .clear
                            ],
                            center: .center,
                            startRadius: circleSize * 0.4,
                            endRadius: circleSize * 0.8
                        )
                    )
                    .frame(width: circleSize * 1.4, height: circleSize * 1.4)

                // Main gradient circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                gradientColors[0].opacity(0.15),
                                gradientColors[1].opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: gradientColors.map { $0.opacity(0.3) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )

                // SF Symbol icon
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .symbolEffect(.bounce)
            }

            // Difficulty badge
            Text(difficultyLabel)
                .font(.caption.weight(.semibold))
                .foregroundColor(difficultyColor)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(difficultyColor.opacity(0.12))
                .cornerRadius(AppCorners.small)
        }
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Compact View (Exercise Card)

    private var compactView: some View {
        ZStack {
            // Gradient circle background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            gradientColors[0].opacity(0.15),
                            gradientColors[1].opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Circle()
                        .stroke(
                            gradientColors[1].opacity(0.2),
                            lineWidth: 1.5
                        )
                )

            // SF Symbol icon
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

// MARK: - Exercise Position Guide

/// Shows structured start → movement → return instructions as a numbered step sequence.
/// Only renders when at least one position field is present.
struct ExercisePositionGuideView: View {
    let startPosition: String?
    let movement: String?
    let endPosition: String?

    var body: some View {
        if startPosition != nil || movement != nil || endPosition != nil {
            VStack(alignment: .leading, spacing: 16) {
                if let start = startPosition {
                    positionStep(number: 1, label: "Starting Position", text: start, color: AppColors.success)
                }
                if let move = movement {
                    positionStep(number: 2, label: "Movement", text: move, color: AppColors.accent)
                }
                if let end = endPosition {
                    positionStep(number: 3, label: "Return", text: end, color: AppColors.accent)
                }
            }
        }
    }

    private func positionStep(number: Int, label: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color)
                Text(text)
                    .font(.subheadline)
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(label): \(text)")
    }
}

// MARK: - Difficulty Badge (standalone)

/// A small colored pill showing exercise difficulty level.
struct DifficultyBadge: View {
    let difficulty: RehabExercise.Difficulty

    private var label: String {
        switch difficulty {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        }
    }

    private var color: Color {
        switch difficulty {
        case .beginner: return AppColors.success
        case .intermediate: return AppColors.warning
        case .advanced: return AppColors.danger
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .cornerRadius(6)
    }
}
