import SwiftUI

// MARK: - Notifications

extension Notification.Name {
    static let popToRoot = Notification.Name("popToRoot")
    static let deepLink = Notification.Name("deepLink")
}

// MARK: - Design Tokens (MVVC Rebrand)
// Colors from mvvc-design-system.js. Add Industry-Bold.otf and Inter-* font files
// to the Xcode project and register them in Info.plist under UIAppFonts to activate
// the custom typography. SwiftUI falls back to system sans-serif until then.

enum AppColors {
    // MARK: Brand
    static let accent       = Color(red: 0.800, green: 0,     blue: 0)     // #CC0000 — MVVC red
    static let success      = Color(red: 0.176, green: 0.478, blue: 0.227) // #2D7A3A
    static let warning      = Color(red: 0.722, green: 0.478, blue: 0)     // #B87A00
    static let danger       = Color(red: 0.800, green: 0,     blue: 0)     // #CC0000 — same as brand red
    static let info         = Color(red: 0.800, green: 0,     blue: 0)     // #CC0000

    // MARK: Text (light surfaces)
    static let primaryText    = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111
    static let secondaryText  = Color(red: 0.333, green: 0.333, blue: 0.333) // #555555
    static let mutedText      = Color(red: 0.533, green: 0.533, blue: 0.533) // #888888

    // MARK: Text (dark surfaces)
    static let textOnDark      = Color.white
    static let textOnDarkMuted = Color.white.opacity(0.6)

    // MARK: Surfaces
    static let cardBackground = Color.white                                         // #FFFFFF
    static let pageBackground = Color(red: 0.949, green: 0.945, blue: 0.937)       // #F2F1EF
    static let elevatedSurface = Color(red: 0.961, green: 0.957, blue: 0.949)      // #F5F4F2
    static let inputBackground = Color(red: 0.973, green: 0.969, blue: 0.965)      // #F8F7F6
    static let subtleBorder    = Color.black.opacity(0.08)

    // MARK: Dark surfaces (nav bar, hero cards, workout screen)
    static let darkSurface        = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111
    static let darkSurfaceElevated = Color(red: 0.102, green: 0.102, blue: 0.102) // #1A1A1A
    static let navBackground      = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111
    static let navBorder          = Color.white.opacity(0.08)

    // MARK: Tab bar
    static let tabActive   = Color(red: 0.800, green: 0, blue: 0)   // #CC0000
    static let tabInactive = Color.white.opacity(0.45)

    // MARK: CTA
    static let ctaBackground = Color(red: 0.800, green: 0, blue: 0) // #CC0000
    static let ctaText       = Color.white

    // MARK: Accent variants
    static let accentLight = Color(red: 0.910, green: 0,     blue: 0.051) // #E8000D
    static let accentDark  = Color(red: 0.639, green: 0,     blue: 0)     // #A30000
    static let accentTint  = Color(red: 0.800, green: 0,     blue: 0).opacity(0.10)

    // MARK: Chip
    static let chipSelectedBg     = Color(red: 0.800, green: 0, blue: 0) // #CC0000
    static let chipSelectedBorder = Color(red: 0.800, green: 0, blue: 0)
    static let chipSelectedText   = Color.white

    // MARK: Card styling
    static let cardBorder      = Color.black.opacity(0.08)
    static let cardShadowColor = Color.black.opacity(0.06)
    static let inputFocusBorder = Color(red: 0.800, green: 0, blue: 0)

    // MARK: Gradients
    static let primaryGradient = LinearGradient(
        colors: [Color(red: 0.800, green: 0, blue: 0), Color(red: 0.639, green: 0, blue: 0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let warmGradient = LinearGradient(
        colors: [Color(red: 0.722, green: 0.478, blue: 0), Color(red: 0.612, green: 0.380, blue: 0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let coolGradient = LinearGradient(
        colors: [Color(red: 0.800, green: 0, blue: 0), Color(red: 0.910, green: 0, blue: 0.051)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let healingGradient = LinearGradient(
        colors: [Color(red: 0.800, green: 0, blue: 0), Color(red: 0.639, green: 0, blue: 0)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    // Login / launch screen background
    static let bgGradient = LinearGradient(
        colors: [
            Color(red: 0.067, green: 0.067, blue: 0.067),
            Color(red: 0.102, green: 0.102, blue: 0.102)
        ],
        startPoint: .top, endPoint: .bottom
    )

    // MARK: Dashboard aliases (backward-compat — existing Dashboard views keep compiling)
    static let dashBackground       = pageBackground
    static let dashSurface          = cardBackground
    static let dashAccent           = accent
    static let dashSecondaryAccent  = accentLight
    static let dashBorder           = cardBorder
    static let dashTextPrimary      = primaryText
    static let dashTextSecondary    = secondaryText
    static let dashSuccess          = success
    static let dashWarning          = warning
    static let dashDanger           = danger
    static let dashAccentGradient   = primaryGradient
}

// MARK: - Spacing

enum AppSpacing {
    static let nano: CGFloat = 2
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 20
    static let xxl:  CGFloat = 28
    static let xxxl: CGFloat = 40

    // Aliases for commonly needed in-between values
    static let tight:       CGFloat = 6
    static let comfortable: CGFloat = 10
    static let wide:        CGFloat = 24
    static let huge:        CGFloat = 32
}

// MARK: - Corner Radii

enum AppCorners {
    static let small:  CGFloat = 8    // chips, small buttons
    static let medium: CGFloat = 12   // inputs, smaller cards
    static let card:   CGFloat = 16   // standard cards
    static let large:  CGFloat = 20   // large cards
    static let xl:     CGFloat = 24   // hero cards
    static let xxl:    CGFloat = 28
    static let pill:   CGFloat = 100  // capsule buttons
}

// MARK: - Typography
// Industry Bold for headings; Inter (Regular/Medium/SemiBold) for body.
// Custom font files must be added to Xcode and registered in Info.plist under UIAppFonts.

enum AppFonts {
    // MARK: Headings — Industry Bold
    static let display      = Font.custom("Industry-Bold", size: 36) // large stat/hero number
    static let heroTitle    = Font.custom("Industry-Bold", size: 28)
    static let title        = Font.custom("Industry-Bold", size: 24)
    static let sectionTitle = Font.custom("Industry-Bold", size: 20)
    static let cardTitle    = Font.custom("Industry-Bold", size: 14)
    static let statNumber   = Font.custom("Industry-Bold", size: 28)
    static let badge        = Font.custom("Industry-Bold", size: 10)
    static let fieldLabel   = Font.custom("Industry-Bold", size: 11) // uppercase field labels

    // MARK: Body — Inter
    static let body         = Font.custom("Inter-Regular",  size: 14)
    static let bodyMedium   = Font.custom("Inter-Medium",   size: 14)
    static let bodySemiBold = Font.custom("Inter-SemiBold", size: 14)

    // MARK: Small — Inter 13pt
    static let small         = Font.custom("Inter-Regular",  size: 13)
    static let smallMedium   = Font.custom("Inter-Medium",   size: 13)
    static let smallSemiBold = Font.custom("Inter-SemiBold", size: 13)

    // MARK: Caption — Inter 12pt
    static let caption         = Font.custom("Inter-Regular",  size: 12)
    static let captionMedium   = Font.custom("Inter-Medium",   size: 12)
    static let captionSemiBold = Font.custom("Inter-SemiBold", size: 12)

    // MARK: Micro — Inter 11pt
    static let micro       = Font.custom("Inter-Regular",  size: 11)
    static let microMedium = Font.custom("Inter-Medium",   size: 11)

    // MARK: Dashboard data (monospaced for number alignment)
    static let dataLarge  = Font.system(.title,    design: .monospaced).weight(.bold)
    static let dataMedium = Font.system(.body,     design: .monospaced).weight(.semibold)
    static let dataSmall  = Font.system(.footnote, design: .monospaced).weight(.medium)
    static let dashLabel  = Font.system(.caption2).weight(.semibold)
}

// MARK: - Animation Presets

enum AppAnimations {
    static let springy = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let smooth  = Animation.easeInOut(duration: 0.25)
    static let bouncy  = Animation.spring(response: 0.4, dampingFraction: 0.6, blendDuration: 0.1)
    static let press   = Animation.spring(response: 0.12)
}

// MARK: - Card Style

struct CardStyle: ViewModifier {
    enum Elevation { case flat, subtle, raised, hero }
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
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }

    private var shadowColor: Color {
        elevation == .hero ? Color.black.opacity(0.18) : AppColors.cardShadowColor
    }
    private var shadowRadius: CGFloat {
        switch elevation {
        case .flat: return 0; case .subtle: return 8
        case .raised: return 12; case .hero: return 20
        }
    }
    private var shadowY: CGFloat {
        switch elevation {
        case .flat: return 0; case .subtle: return 2
        case .raised: return 4; case .hero: return 6
        }
    }
}

extension View {
    func cardStyle(_ elevation: CardStyle.Elevation = .subtle) -> some View {
        modifier(CardStyle(elevation: elevation))
    }
}

// MARK: - MVVC Nav Bar Modifier
// Apply to the root content view inside each NavigationStack.

struct MVVCNavBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(AppColors.navBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("MVVCLogoStacked")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 56)
                        .clipped(antialiased: false)
                        .fixedSize()
                }
            }
    }
}

extension View {
    func mvvcNavBar() -> some View { modifier(MVVCNavBarModifier()) }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Industry-Bold", size: 15))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, AppSpacing.xl)
            .background(isDisabled ? AnyShapeStyle(AppColors.mutedText) : AnyShapeStyle(AppColors.ctaBackground))
            .clipShape(Capsule())
            .shadow(color: AppColors.ctaBackground.opacity(0.30), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Industry-Bold", size: 14))
            .textCase(.uppercase)
            .kerning(1.0)
            .foregroundColor(AppColors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(.clear)
            .overlay(Capsule().stroke(AppColors.accent, lineWidth: 1.5))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFonts.bodyMedium)
            .foregroundColor(AppColors.danger)
            .padding(.vertical, AppSpacing.md)
            .padding(.horizontal, AppSpacing.xl)
            .background(AppColors.danger.opacity(0.1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
}

// MARK: - MVVC Shared Components

/// Red gradient rule with uppercase Barlow Condensed title — use for all content section breaks.
struct MVVCDividerHeader: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            Text(title)
                .font(AppFonts.sectionTitle)
                .textCase(.uppercase)
                .kerning(1.0)
                .foregroundColor(AppColors.primaryText)

            LinearGradient(
                colors: [AppColors.accent, AppColors.accent.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 2)
        }
    }
}

/// Small red pill badge — "ACTIVE", "ON FIRE", count indicators, etc.
struct MVVCRedBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AppFonts.badge)
            .textCase(.uppercase)
            .kerning(1.0)
            .foregroundColor(AppColors.ctaText)
            .padding(.horizontal, AppSpacing.comfortable)
            .padding(.vertical, AppSpacing.nano + 1)
            .background(AppColors.accent)
            .clipShape(Capsule())
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
                    .font(AppFonts.bodySemiBold)
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12))
                    .cornerRadius(AppCorners.small - 1)
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.secondaryText)
                if required {
                    Text("Required")
                        .font(AppFonts.captionMedium)
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
            .font(AppFonts.body)
            .foregroundColor(AppColors.primaryText)
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
                .foregroundColor(AppColors.accent)

            VStack(spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Text(subtitle)
                    .font(AppFonts.small)
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
        .cardStyle()
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
                .font(AppFonts.small)
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
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(gradientColors.first ?? AppColors.accent)
                    .frame(width: 40, height: 40)
                    .background((gradientColors.first ?? AppColors.accent).opacity(0.12))
                    .cornerRadius(AppCorners.small)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text(title)
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                    Text(subtitle)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md + 2)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let gradientColors: [Color]
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(AppFonts.bodyMedium)
                    .foregroundColor(gradientColors.first ?? AppColors.accent)
                    .frame(width: 40, height: 40)
                    .background((gradientColors.first ?? AppColors.accent).opacity(0.12))
                    .cornerRadius(AppCorners.small)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text(title)
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                    Text(subtitle)
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md + 2)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        }
    }
}

struct SectionHeader: View {
    let icon: String
    let color: Color
    let title: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(AppFonts.bodySemiBold)
            Text(title)
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.secondaryText)
            Spacer()
        }
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
                .font(AppFonts.smallSemiBold)
                .foregroundColor(isSelected ? AppColors.ctaText : AppColors.primaryText)
                .padding(.horizontal, AppSpacing.md + 2)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(isSelected ? AppColors.chipSelectedBg : Color.clear)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? AppColors.chipSelectedBorder : Color.black.opacity(0.15), lineWidth: 1.5)
                )
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
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
        let subviewSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [[Int]] = []
        var rowContentWidths: [CGFloat] = []
        var currentRow: [Int] = []
        var currentRowWidth: CGFloat = 0

        for (index, size) in subviewSizes.enumerated() {
            let itemWidth = size.width
            let spaceNeeded = currentRow.isEmpty ? itemWidth : currentRowWidth + spacing + itemWidth
            if spaceNeeded > maxWidth && !currentRow.isEmpty {
                rows.append(currentRow)
                rowContentWidths.append(currentRowWidth)
                currentRow = []; currentRowWidth = 0
            }
            currentRow.append(index)
            currentRowWidth = currentRow.count == 1 ? itemWidth : currentRowWidth + spacing + itemWidth
        }
        if !currentRow.isEmpty { rows.append(currentRow); rowContentWidths.append(currentRowWidth) }

        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var currentY: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let rowWidth = rowContentWidths[rowIndex]
            let startX: CGFloat = alignment == .center ? max(0, (maxWidth - rowWidth) / 2) : 0
            let rowHeight = row.map { subviewSizes[$0].height }.max() ?? 0
            var x = startX
            for itemIndex in row {
                positions[itemIndex] = CGPoint(x: x, y: currentY)
                x += subviewSizes[itemIndex].width + spacing
            }
            currentY += rowHeight + spacing
        }
        let totalHeight = max(0, currentY - spacing)
        return ArrangementResult(size: CGSize(width: maxWidth, height: totalHeight), positions: positions, sizes: subviewSizes)
    }

    private struct ArrangementResult {
        let size: CGSize; let positions: [CGPoint]; let sizes: [CGSize]
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
    func trackScreen(_ name: String) -> some View { modifier(SessionLoggingModifier(screenName: name)) }
}

// MARK: - Shimmer

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, .white.opacity(0.4), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width * 0.3 + phase * geometry.size.width * 1.6)
                        .allowsHitTesting(false)
                }
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(ShimmerModifier()) }
}

// MARK: - Onboarding Dark Surface

enum OnboardingColors {
    static let cardBg     = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.10)
    static let inputBg    = Color.white.opacity(0.08)
    static let chipIdle   = Color.white.opacity(0.10)
    static let chipBorder = Color.white.opacity(0.14)
    static let subLabel   = Color.white.opacity(0.45)
    static let muted      = Color.white.opacity(0.35)
}

struct DarkTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .font(AppFonts.body)
            .foregroundColor(.white)
            .padding(AppSpacing.md)
            .background(OnboardingColors.inputBg)
            .cornerRadius(AppCorners.medium)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.medium)
                    .stroke(OnboardingColors.cardBorder, lineWidth: 1)
            )
    }
}

struct OnboardingFieldLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(AppFonts.fieldLabel)
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundColor(OnboardingColors.subLabel)
    }
}

struct DarkChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    var accentColor: Color = AppColors.accent
    var compact: Bool = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(compact ? AppFonts.smallMedium : AppFonts.bodyMedium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? AppSpacing.xs + 2 : AppSpacing.md)
                .padding(.horizontal, compact ? AppSpacing.sm : 0)
                .background(isSelected ? accentColor : OnboardingColors.chipIdle)
                .cornerRadius(compact ? AppCorners.small : AppCorners.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? AppCorners.small : AppCorners.medium)
                        .stroke(isSelected ? Color.clear : OnboardingColors.chipBorder, lineWidth: 1)
                )
        }
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
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.primaryText)
        }
        .padding(AppSpacing.xxl)
        .background(.ultraThinMaterial)
        .cornerRadius(AppCorners.xl)
        .transition(.scale.combined(with: .opacity))
    }
}
