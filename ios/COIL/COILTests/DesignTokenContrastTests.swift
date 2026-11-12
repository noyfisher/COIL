import XCTest
import SwiftUI
@testable import COIL

/// AA floors for the tokens the 2026-09-14 audit found failing.
///
/// Unlike `ContrastRegressionTests`, this harness composites the foreground over
/// the background BEFORE computing luminance, so translucent on-dark tokens
/// (white at 55%) are measured as they render, not as opaque white. Tier-0
/// `CoilPalette` UIColors are used for adaptive tokens so both appearances
/// resolve through their dynamic providers; alpha tokens go through
/// `UIColor(Color)`.
final class DesignTokenContrastTests: XCTestCase {

    private struct RGBA { var r: CGFloat; var g: CGFloat; var b: CGFloat; var a: CGFloat }

    private func resolve(_ color: UIColor, _ style: UIUserInterfaceStyle) -> RGBA {
        var c = RGBA(r: 0, g: 0, b: 0, a: 0)
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            .getRed(&c.r, green: &c.g, blue: &c.b, alpha: &c.a)
        return c
    }

    private func luminance(_ c: RGBA) -> CGFloat {
        func channel(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    /// WCAG ratio of `fg` composited over an opaque `bg`.
    private func contrast(_ fg: UIColor, over bg: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
        let f = resolve(fg, style), b = resolve(bg, style)
        let blended = RGBA(r: f.a * f.r + (1 - f.a) * b.r,
                           g: f.a * f.g + (1 - f.a) * b.g,
                           b: f.a * f.b + (1 - f.a) * b.b,
                           a: 1)
        let l1 = luminance(blended), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private func assertAA(_ fg: UIColor, over bg: UIColor, _ label: String,
                          floor: CGFloat = 4.5,
                          styles: [UIUserInterfaceStyle] = [.light, .dark],
                          file: StaticString = #filePath, line: UInt = #line) {
        for style in styles {
            let value = contrast(fg, over: bg, style)
            XCTAssertGreaterThanOrEqual(
                value, floor,
                String(format: "%@ in %@ mode: %.2f:1 (floor %.1f:1)",
                       label, style == .light ? "light" : "dark", Double(value), Double(floor)),
                file: file, line: line
            )
        }
    }

    // MARK: - Adaptive text on adaptive surfaces

    func testMutedText_onCardAndPage_meetsAA() {
        assertAA(CoilPalette.textMuted, over: CoilPalette.card, "mutedText on card")
        assertAA(CoilPalette.textMuted, over: CoilPalette.page, "mutedText on page")
    }

    func testSecondaryText_onCard_meetsAA() {
        assertAA(CoilPalette.textSecondary, over: CoilPalette.card, "secondaryText on card")
    }

    // MARK: - Translucent white text on the fixed-dark ink

    func testOnDarkTiers_onInk_meetFloors() {
        assertAA(UIColor(AppColors.textOnDarkTertiary), over: CoilPalette.ink, "textOnDarkTertiary on ink")
        assertAA(UIColor(AppColors.textOnDarkSecondary), over: CoilPalette.ink, "textOnDarkSecondary on ink", floor: 7.0)
    }

    func testTabInactive_onNavBackground_meetsAA() {
        assertAA(UIColor(AppColors.tabInactive), over: CoilPalette.ink, "tabInactive on nav bar")
    }

    func testOnDarkLabel_onInk_meetsAA() {
        assertAA(UIColor(AppColors.onDarkLabel), over: CoilPalette.ink, "onDarkLabel on ink")
    }

    // MARK: - Fixed pairs

    /// Light only: the dark CTA (#17A6A2) is 2.99:1 under white text — a pre-existing
    /// gap outside this PR (recorded in the spec's follow-ups), so it is not asserted here.
    func testCTAText_onCTABackground_meetsAAInLight() {
        assertAA(UIColor(AppColors.ctaText), over: CoilPalette.accentDeep, "ctaText on ctaBackground", styles: [.light])
    }

    /// Light only: the dark danger red (#CB4238) is 3.35:1 on the dark card — same follow-up.
    func testDanger_onCard_meetsAAInLight() {
        assertAA(CoilPalette.errorRed, over: CoilPalette.card, "danger on card", styles: [.light])
    }

    func testAccentText_onCard_meetsAAInLight() {
        assertAA(CoilPalette.accentDeep, over: CoilPalette.card, "accentText on card", styles: [.light])
    }

    /// Documents the known trap (see the `accentText` doc comment in DesignSystem):
    /// accent text is NOT readable on the fixed-dark surfaces in light mode. If
    /// this starts passing, the token changed and that comment must be revisited.
    func testAccentText_onDarkSurfaceInLight_staysBelowAA() {
        XCTAssertLessThan(contrast(CoilPalette.accentDeep, over: CoilPalette.ink, .light), 4.5,
                          "accentText on ink in light mode is the documented trap; it must stay < 4.5:1")
    }
}
