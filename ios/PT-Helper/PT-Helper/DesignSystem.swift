import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let popToRoot = Notification.Name("popToRoot")
    static let deepLink = Notification.Name("deepLink")
}

// MARK: - Design Tokens

enum AppColors {
    // MARK: Semantic Colors
    static let accent = Color(red: 0.369, green: 0.549, blue: 0.353)               // #5E8C5A
    static let success = Color(red: 0.369, green: 0.549, blue: 0.353)              // #5E8C5A
    static let warning = Color(red: 0.722, green: 0.588, blue: 0.239)             // #B8963D
    static let danger = Color(red: 0.722, green: 0.361, blue: 0.361)              // #B85C5C
    static let info = Color(red: 0.369, green: 0.549, blue: 0.353)                // #5E8C5A

    // MARK: Text Colors
    static let primaryText = Color(red: 0.118, green: 0.169, blue: 0.102)         // #1E2B1A
    static let secondaryText = Color(red: 0.333, green: 0.420, blue: 0.290)       // #556B4A
    static let mutedText = Color(red: 0.541, green: 0.604, blue: 0.494)           // #8A9A7E

    // MARK: Brand Gradients (Sage-toned)
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.369, green: 0.549, blue: 0.353), Color(red: 0.227, green: 0.369, blue: 0.212)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let warmGradient = LinearGradient(
        colors: [Color(red: 0.722, green: 0.588, blue: 0.239), Color(red: 0.612, green: 0.498, blue: 0.180)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let coolGradient = LinearGradient(
        colors: [Color(red: 0.369, green: 0.549, blue: 0.353), Color(red: 0.659, green: 0.800, blue: 0.647)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let healingGradient = LinearGradient(
        colors: [Color(red: 0.369, green: 0.549, blue: 0.353), Color(red: 0.459, green: 0.639, blue: 0.443)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: Surface Colors
    static let cardBackground = Color(red: 0.980, green: 0.988, blue: 0.973)      // #FAFCF8
    static let pageBackground = Color(red: 0.937, green: 0.949, blue: 0.925)      // #EFF2EC
    static let elevatedSurface = Color(red: 0.886, green: 0.910, blue: 0.855)     // #E2E8DA
    static let inputBackground = Color(red: 0.980, green: 0.988, blue: 0.973)     // #FAFCF8
    static let subtleBorder = Color(red: 0.294, green: 0.392, blue: 0.255).opacity(0.12)

    // MARK: CTA Colors
    static let ctaBackground = Color(red: 0.227, green: 0.369, blue: 0.212)       // #3A5E36
    static let ctaText = Color(red: 0.949, green: 0.961, blue: 0.933)             // #F2F5EE

    // MARK: Accent Variants
    static let accentLight = Color(red: 0.659, green: 0.800, blue: 0.647)         // #A8CCA5
    static let accentTint = Color(red: 0.369, green: 0.549, blue: 0.353).opacity(0.10)

    // MARK: Chip Colors
    static let chipSelectedBg = Color(red: 0.831, green: 0.898, blue: 0.824)      // #D4E5D2
    static let chipSelectedBorder = Color(red: 0.545, green: 0.722, blue: 0.533)  // #8BB888
    static let chipSelectedText = Color(red: 0.176, green: 0.290, blue: 0.165)    // #2D4A2A

    // MARK: Card Styling
    static let cardBorder = Color(red: 0.294, green: 0.392, blue: 0.255).opacity(0.10)
    static let cardShadowColor = Color(red: 0.176, green: 0.235, blue: 0.137).opacity(0.05)
    static let inputFocusBorder = Color(red: 0.369, green: 0.549, blue: 0.353)    // #5E8C5A

    // MARK: Background Gradient
    static let bgGradient = LinearGradient(
        colors: [
            Color(red: 0.949, green: 0.961, blue: 0.933),  // #F2F5EE
            Color(red: 0.910, green: 0.929, blue: 0.878),  // #E8EDE0
            Color(red: 0.867, green: 0.898, blue: 0.831)   // #DDE5D4
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Dashboard Aliases (backward compat → Sage & Stone)
    static let dashBackground = pageBackground
    static let dashSurface = cardBackground
    static let dashAccent = accent
    static let dashSecondaryAccent = accentLight
    static let dashBorder = cardBorder
    static let dashTextPrimary = primaryText
    static let dashTextSecondary = secondaryText
    static let dashSuccess = success
    static let dashWarning = warning
    static let dashDanger = danger
    static let dashAccentGradient = primaryGradient
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
    static let small: CGFloat = 14
    static let medium: CGFloat = 16
    static let card: CGFloat = 20
    static let large: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 28
    static let pill: CGFloat = 100
}

// MARK: - Typography Presets

enum AppFonts {
    // Semantic text styles — scale with Dynamic Type
    static let heroTitle = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .serif).weight(.bold)
    static let cardTitle = Font.system(.body, design: .serif).weight(.semibold)
    static let statNumber = Font.system(.title, design: .rounded).weight(.bold)
    static let badge = Font.caption2.weight(.semibold)

    // MARK: Dashboard Data Typography (SF Mono) — scale with Dynamic Type
    static let dataLarge = Font.system(.title, design: .monospaced).weight(.bold)
    static let dataMedium = Font.system(.body, design: .monospaced).weight(.semibold)
    static let dataSmall = Font.system(.footnote, design: .monospaced).weight(.medium)
    static let dashLabel = Font.system(.caption2).weight(.semibold)
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
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.cardShadowColor, radius: shadowRadius, y: shadowY)
            .shadow(color: AppColors.cardShadowColor.opacity(0.5), radius: secondShadowRadius, y: secondShadowY)
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

    private var secondShadowRadius: CGFloat {
        switch elevation {
        case .flat: return 0
        case .subtle: return 2
        case .raised: return 4
        case .hero: return 6
        }
    }

    private var secondShadowY: CGFloat {
        switch elevation {
        case .flat: return 0
        case .subtle: return 1
        case .raised: return 2
        case .hero: return 3
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
            .foregroundColor(AppColors.ctaText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isDisabled
                    ? AnyShapeStyle(AppColors.mutedText)
                    : AnyShapeStyle(AppColors.ctaBackground)
            )
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundColor(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppColors.accentTint)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundColor(AppColors.danger)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.xl)
            .background(AppColors.danger.opacity(0.1))
            .clipShape(Capsule())
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
                    .background(color.opacity(0.10))
                    .cornerRadius(7)
                Text(title)
                    .font(.system(.subheadline, design: .serif).weight(.semibold))
                    .foregroundColor(AppColors.secondaryText)
                if required {
                    Text("Required")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(AppColors.danger.opacity(0.8))
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
                .foregroundStyle(AppColors.primaryGradient)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
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
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.cardBorder, lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }
}

struct LoadingStateView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.2)
            Text(message)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
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
                    .foregroundColor(gradientColors.first ?? AppColors.accent)
                    .frame(width: 50, height: 50)
                    .background((gradientColors.first ?? AppColors.accent).opacity(0.10))
                    .cornerRadius(AppCorners.card)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
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
                    .foregroundColor(gradientColors.first ?? AppColors.accent)
                    .frame(width: 50, height: 50)
                    .background((gradientColors.first ?? AppColors.accent).opacity(0.10))
                    .cornerRadius(AppCorners.card)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.primaryText)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(AppSpacing.lg)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
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
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundColor(AppColors.secondaryText)
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
                AnalyticsService.shared.logScreenView(screenName)
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
                .foregroundColor(isSelected ? AppColors.chipSelectedText : AppColors.primaryText)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? AppColors.chipSelectedBg : AppColors.cardBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppColors.chipSelectedBorder : AppColors.subtleBorder, lineWidth: 1)
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
