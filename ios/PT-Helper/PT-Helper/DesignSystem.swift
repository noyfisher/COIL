import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let popToRoot = Notification.Name("popToRoot")
}

// MARK: - Design Tokens

enum AppColors {
    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let info = Color.cyan

    static let primaryGradient = LinearGradient(
        colors: [.blue, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Brand gradients
    static let warmGradient = LinearGradient(
        colors: [Color(red: 1.0, green: 0.42, blue: 0.42), Color(red: 0.93, green: 0.35, blue: 0.14)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let coolGradient = LinearGradient(
        colors: [Color(red: 0.04, green: 0.74, blue: 0.89), Color(red: 0.12, green: 0.56, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let healingGradient = LinearGradient(
        colors: [Color(red: 0.0, green: 0.72, blue: 0.58), Color(red: 0.0, green: 0.81, blue: 0.79)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Surface colors
    static let cardBackground = Color(.systemBackground)
    static let pageBackground = Color(.systemGroupedBackground)
    static let elevatedSurface = Color(.secondarySystemGroupedBackground)
    static let inputBackground = Color(.systemGray6)
    static let subtleBorder = Color(.systemGray5)
}

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 30
    static let xxxl: CGFloat = 40
}

enum AppCorners {
    static let small: CGFloat = 8
    static let medium: CGFloat = 10
    static let card: CGFloat = 14
    static let large: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let pill: CGFloat = 100
}

// MARK: - Typography Presets

enum AppFonts {
    static let heroTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let sectionTitle = Font.title3.weight(.bold)
    static let cardTitle = Font.body.weight(.semibold)
    static let statNumber = Font.system(size: 28, weight: .bold, design: .rounded)
    static let badge = Font.caption2.weight(.semibold)
}

// MARK: - Animation Presets

enum AppAnimations {
    static let springy = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let smooth = Animation.easeInOut(duration: 0.25)
    static let bouncy = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.1)
}

// MARK: - View Modifiers

struct CardStyle: ViewModifier {
    enum Elevation {
        case flat, subtle, raised, hero
    }

    var elevation: Elevation = .subtle

    func body(content: Content) -> some View {
        content
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(cornerRadius)
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var cornerRadius: CGFloat {
        switch elevation {
        case .flat: return AppCorners.card
        case .subtle: return AppCorners.card
        case .raised: return AppCorners.large
        case .hero: return AppCorners.xl
        }
    }

    private var shadowColor: Color {
        switch elevation {
        case .flat: return .clear
        case .subtle: return .black.opacity(0.04)
        case .raised: return .black.opacity(0.08)
        case .hero: return .black.opacity(0.12)
        }
    }

    private var shadowRadius: CGFloat {
        switch elevation {
        case .flat: return 0
        case .subtle: return 8
        case .raised: return 12
        case .hero: return 16
        }
    }

    private var shadowY: CGFloat {
        switch elevation {
        case .flat: return 0
        case .subtle: return 2
        case .raised: return 4
        case .hero: return 6
        }
    }
}

extension View {
    func cardStyle(_ elevation: CardStyle.Elevation = .subtle) -> some View {
        modifier(CardStyle(elevation: elevation))
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isDisabled
                    ? AnyShapeStyle(Color.gray)
                    : AnyShapeStyle(
                        LinearGradient(
                            colors: [.blue, .blue.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .cornerRadius(AppCorners.card)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundColor(.blue)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(AppCorners.card)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(.red)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.xl)
            .background(Color.red.opacity(0.1))
            .cornerRadius(AppCorners.medium)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

// MARK: - Shared Components

struct CardSection<Content: View>: View {
    let icon: String
    let color: Color
    let title: String
    var required: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.15))
                    .cornerRadius(7)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                if required {
                    Text("Required")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            content
        }
        .cardStyle()
    }
}

struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .padding(AppSpacing.md)
            .background(AppColors.inputBackground)
            .cornerRadius(AppCorners.medium)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, AppSpacing.xxl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxl)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.large)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }
}

struct LoadingStateView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QuickActionCard<Destination: View>: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(AppCorners.card)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.large)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
}

/// A variant of QuickActionCard that uses a Button action instead of NavigationLink.
struct QuickActionButton: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 50, height: 50)
                    .background(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(AppCorners.card)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.large)
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
        }
    }
}

/// Section header with icon and title, used for grouping content on the home screen.
struct SectionHeader: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}

// MARK: - Session Logging

struct SessionLoggingModifier: ViewModifier {
    let screenName: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                SessionLogger.shared.logNavigation(.screenAppeared, screen: screenName)
            }
            .onDisappear {
                SessionLogger.shared.logNavigation(.screenDisappeared, screen: screenName)
            }
    }
}

extension View {
    func trackScreen(_ name: String) -> some View {
        modifier(SessionLoggingModifier(screenName: name))
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.4),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.6)
                    .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                    .allowsHitTesting(false)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Celebration Overlay

struct CelebrationOverlay: View {
    let icon: String
    let message: String
    var iconColor: Color = AppColors.success

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(iconColor)
            Text(message)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .padding(AppSpacing.xxl)
        .background(.ultraThinMaterial)
        .cornerRadius(AppCorners.xl)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Chip Button

struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? Color.blue : AppColors.inputBackground)
                .cornerRadius(AppCorners.small)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCorners.small)
                        .stroke(isSelected ? Color.clear : AppColors.subtleBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + rowHeight
        return ArrangementResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }

    private struct ArrangementResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}
