# Design Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the token layer accessible by construction in one `DesignSystem.swift` PR: AA-passing muted text, named on-dark text tiers, icon glyph fonts, a streak colour, a visibly disabled primary button, and the onboarding palette folded into `AppColors`, all locked in by an alpha-aware contrast test.

**Architecture:** Every change is a token value or a new token in `ios/PT-Helper/COIL/DesignSystem.swift`; views are untouched because `OnboardingColors` survives as forwarding aliases. A new `DesignTokenContrastTests` composites translucent foregrounds over their background before computing WCAG ratios (the existing `ContrastRegressionTests` harness ignores alpha, so it cannot gate the on-dark tiers). TDD: the test file lands first and fails on the current values; each token task turns a failure green.

**Tech Stack:** Swift 5 / SwiftUI + UIKit colour resolution, XCTest, `xcodebuild` against the iPhone 16 (iOS 18.2) simulator. Spec: `docs/superpowers/specs/2026-09-14-design-tokens-design.md`.

---

## Ground rules for every task

- **Warnings are errors** in this project.
- **Worktree:** `.claude/worktrees/ux-design-tokens` on branch `ux/design-tokens`, created from `ux/design-specs` (Task 0). Run everything from there; never `cd` to the main checkout; never `git stash`; never `git add .` — stage the files each task names.
- **Line numbers are anchors as of commit `3509a64`** (`ux/design-specs` head when this plan was written; `DesignSystem.swift` is identical on `main` and on the Foundation branches). Grep for the quoted code before editing (CLAUDE.md R1).
- **Build:**
```bash
SIM=8B908AF6-D437-40DC-9593-2DDC315B0480
xcodebuild build -project ios/PT-Helper/COIL.xcodeproj -scheme COIL \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath /tmp/coil-dd-tokens 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
```
  Expected last line `** BUILD SUCCEEDED **`; an `appintentsmetadataprocessor … Metadata extraction skipped` line is benign.
- **Unit test command** (one class; the default UnitPlan includes `COILTests`):
```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj -scheme COIL \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /tmp/coil-dd-tokens \
  -only-testing:COILTests/<ClassName> 2>&1 | grep -E "Test Case .* (passed|failed)|error:|\*\* TEST|Executed"
```
- If another xcodebuild is using the iPhone 16 simulator, use the iPhone 16 Pro `A1579757-01DC-4BE8-A068-249FD8467C44` with the same `-derivedDataPath`.
- Commit messages: imperative sentence, no prefix, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `ios/PT-Helper/COIL/DesignSystem.swift` | All token changes (T1–T8 of the spec) | 2–6 |
| `ios/PT-Helper/COILTests/DesignTokenContrastTests.swift` (new) | Alpha-aware WCAG floors for the changed pairs | 1 |

Nothing else changes. `git diff --stat ux/design-specs..HEAD -- ios/` must list exactly these two files at the end.

---

### Task 0: Worktree and baseline

- [ ] **Step 1: Create the worktree** (from the main checkout `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`, which has `ux/design-specs` checked out):
```bash
git worktree add .claude/worktrees/ux-design-tokens -b ux/design-tokens ux/design-specs
cd .claude/worktrees/ux-design-tokens
git log --oneline -1
```
Expected: a commit at or after `7fc52bc` on `ux/design-specs`.

- [ ] **Step 2: Baseline build** → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Baseline contrast tests** → `-only-testing:COILTests/ContrastRegressionTests` → 10 `passed`, `** TEST SUCCEEDED **`.

---

### Task 1: Alpha-aware contrast tests (failing)

**Files:**
- Create: `ios/PT-Helper/COILTests/DesignTokenContrastTests.swift`

- [ ] **Step 1: Write the tests** (full file):

```swift
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `-only-testing:COILTests/DesignTokenContrastTests`. Expected: build errors — `type 'AppColors' has no member 'textOnDarkTertiary'` (and `textOnDarkSecondary`, `onDarkLabel`). That is the intended fail-first for Task 2; do NOT stub the tokens here.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COILTests/DesignTokenContrastTests.swift
git commit -m "Add alpha-aware contrast floors for the audited tokens (red)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
(Committing a red test file is deliberate: the branch compiles again after Task 2.)

---

### Task 2: On-dark text tiers and tab-bar inactive colour (spec T2, T3, T7 label tokens)

**Files:**
- Modify: `ios/PT-Helper/COIL/DesignSystem.swift:84-85` (`textOnDark` / `textOnDarkMuted`), `:109` (`tabInactive`)

- [ ] **Step 1: Add the tiers**

Lines 84-85 currently read:
```swift
    static let textOnDark      = Color.white
    static let textOnDarkMuted = Color.white.opacity(0.6)
```
Replace them with:
```swift
    static let textOnDark      = Color.white
    static let textOnDarkMuted = Color.white.opacity(0.6)
    /// On-dark text tiers for the fixed-dark ink surfaces (`darkSurface`,
    /// `navBackground`, `bgGradient`). Measured on ink: 0.70 → 8.97:1, 0.55 → 6.01:1.
    /// Nothing below 0.55 alpha may be used for text on ink (0.45 was 4.45:1, 0.30 was 2.70:1).
    static let textOnDarkSecondary = Color.white.opacity(0.70)
    static let textOnDarkTertiary  = Color.white.opacity(0.55)
    /// Onboarding / hero-card surfaces on the fixed-dark ground (formerly `OnboardingColors`).
    static let onDarkCard       = Color.white.opacity(0.06)
    static let onDarkBorder     = Color.white.opacity(0.10)
    static let onDarkInput      = Color.white.opacity(0.08)
    static let onDarkChip       = Color.white.opacity(0.10)
    static let onDarkChipBorder = Color.white.opacity(0.14)
    // Two tiers on purpose: field captions above helper text (was 0.45 / 0.35, both under AA).
    static let onDarkLabel      = textOnDarkSecondary  // 0.70 → 8.97:1: uppercase field captions
    static let onDarkMuted      = textOnDarkTertiary   // 0.55 → 6.01:1: helper copy, chevrons, units
```

- [ ] **Step 2: Brighten the inactive tab colour**

Line 109 `static let tabInactive = Color.white.opacity(0.45)` becomes:
```swift
    static let tabInactive = Color.white.opacity(0.55)   // 6.0:1 on ink; 0.45 was 4.45:1 at 10pt
```

- [ ] **Step 3: Build and run the new tests**

Build → succeeded. Run `-only-testing:COILTests/DesignTokenContrastTests`. Expected: 9 tests compile and run; `testMutedText_onCardAndPage_meetsAA` **fails** (light 3.59:1 on card, 3.28:1 on page; dark 3.97:1 on card); every other test passes. Paste the failure lines.

- [ ] **Step 4: Commit**
```bash
git add ios/PT-Helper/COIL/DesignSystem.swift
git commit -m "Add on-dark text tiers and surface tokens; brighten the inactive tab colour

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Muted text passes AA in both appearances (spec T1)

**Files:**
- Modify: `ios/PT-Helper/COIL/DesignSystem.swift:51`

- [ ] **Step 1: Change the palette value**

Line 51 `static let textMuted     = dyn(hex(0x7A8A8D), hex(0x6E8285))` becomes:
```swift
    // Darkened for AA at the 11–13pt sizes it labels (meta lines, stat labels):
    // light was #7A8A8D at 3.59:1 on white / 3.28:1 on page, now 5.30:1 / 4.84:1;
    // dark was #6E8285 at 3.97:1 on the dark card, now 4.97:1 (5.71:1 on the page).
    static let textMuted     = dyn(hex(0x5F6E72), hex(0x7E9396))
```

- [ ] **Step 2: Run the tests** → `-only-testing:COILTests/DesignTokenContrastTests` → 9 `passed`, `** TEST SUCCEEDED **`. Also run `-only-testing:COILTests/ContrastRegressionTests` → 10 `passed` (nothing there depends on mutedText, but it is the sibling gate).

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COIL/DesignSystem.swift
git commit -m "Darken mutedText so meta text meets AA in both appearances

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Icon glyph fonts and streak colour (spec T4, T5)

**Files:**
- Modify: `ios/PT-Helper/COIL/DesignSystem.swift:78` (after `static let info …` in the Brand section), `:326` (after `static let dashLabel …` at the end of `AppFonts`)

- [ ] **Step 1: Add the streak colour**

After line 78 (`static let info    = Color(CoilPalette.infoBlue)   // decoupled from brand`) insert:
```swift
    /// Streak / achievement accent (Tier-0 `pop`). Views must use this rather than
    /// reaching into `CoilPalette` directly.
    static let streak     = Color(CoilPalette.pop)
    static let streakTint = Color(CoilPalette.pop).opacity(0.12)
```

- [ ] **Step 2: Add the icon fonts**

After line 326 (`static let dashLabel  = Font.system(.caption2).weight(.semibold)`), still inside `enum AppFonts`, insert:
```swift

    // MARK: Icons — SF Symbol glyph sizes (symbols follow the system font; these are the
    // only sanctioned sizes, replacing ad-hoc `.font(.system(size: N, weight:))` calls)
    static let iconXS = Font.system(size: 12, weight: .semibold)
    static let iconS  = Font.system(size: 14, weight: .semibold)
    static let iconM  = Font.system(size: 16, weight: .semibold)
    static let iconL  = Font.system(size: 20, weight: .semibold)
    static let iconXL = Font.system(size: 24, weight: .bold)      // the tab bar "+"
```

- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **` (unused static lets do not warn). Run `-only-testing:COILTests/DesignTokenContrastTests` → 9 `passed` (unchanged; guards nothing regressed).

- [ ] **Step 4: Commit**
```bash
git add ios/PT-Helper/COIL/DesignSystem.swift
git commit -m "Add icon glyph font tokens and a streak colour token

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Disabled primary button looks disabled (spec T6)

**Files:**
- Modify: `ios/PT-Helper/COIL/DesignSystem.swift:405-419` (`PrimaryButtonStyle.makeBody`)

- [ ] **Step 1: Replace the body**

`makeBody` currently:
```swift
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
```
becomes:
```swift
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Font.custom("Industry-Bold", size: 15))
            .textCase(.uppercase)
            .kerning(1.2)
            .foregroundColor(.white)
            // Disabled = the same capsule at 35% with a dimmed label and no lift; the old
            // solid mutedText fill read as an enabled grey button on the dark onboarding page.
            .opacity(isDisabled ? 0.7 : 1.0)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, AppSpacing.xl)
            .background(isDisabled ? AnyShapeStyle(AppColors.ctaBackground.opacity(0.35))
                                   : AnyShapeStyle(AppColors.ctaBackground))
            .clipShape(Capsule())
            .shadow(color: isDisabled ? .clear : AppColors.ctaBackground.opacity(0.30), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(AppAnimations.press, value: configuration.isPressed)
    }
```

- [ ] **Step 2: Build** → succeeded. (Visual check happens in Task 7.)

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COIL/DesignSystem.swift
git commit -m "Render disabled primary buttons as a dimmed capsule instead of a solid grey

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Fold `OnboardingColors` into `AppColors`; readable placeholders (spec T7, T8)

**Files:**
- Modify: `ios/PT-Helper/COIL/DesignSystem.swift:878-886` (`enum OnboardingColors`), `:894` (`TextField(placeholder, text: $text)` in `DarkTextField`)

- [ ] **Step 1: Turn `OnboardingColors` into forwarding aliases**

Lines 878-886 currently define seven `Color.white.opacity(…)` constants. Replace the whole enum with:
```swift
/// Deprecated: use `AppColors.onDark*`. Kept as forwarding aliases so the 53 call
/// sites in the onboarding views compile until they are swept in a later PR.
enum OnboardingColors {
    static let cardBg     = AppColors.onDarkCard
    static let cardBorder = AppColors.onDarkBorder
    static let inputBg    = AppColors.onDarkInput
    static let chipIdle   = AppColors.onDarkChip
    static let chipBorder = AppColors.onDarkChipBorder
    static let subLabel   = AppColors.onDarkLabel      // 0.45 → 0.70: field captions now 8.97:1
    static let muted      = AppColors.onDarkMuted      // 0.35 → 0.55: helper text now 6.0:1
}
```

- [ ] **Step 2: Give `DarkTextField` a readable prompt**

Line 894 `TextField(placeholder, text: $text)` becomes:
```swift
        TextField(placeholder, text: $text,
                  prompt: Text(placeholder).foregroundColor(AppColors.onDarkMuted))
```
(the modifier chain below it is unchanged).

- [ ] **Step 3: Build, then run both contrast classes**

Build → succeeded. Run `-only-testing:COILTests/DesignTokenContrastTests -only-testing:COILTests/ContrastRegressionTests` → 19 `passed`.

- [ ] **Step 4: Commit**
```bash
git add ios/PT-Helper/COIL/DesignSystem.swift
git commit -m "Fold OnboardingColors into AppColors and make dark text-field prompts readable

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Verification and PR

- [ ] **Step 1: Full unit run** → `xcodebuild test … -derivedDataPath /tmp/coil-dd-tokens` (UnitPlan default) → `** TEST SUCCEEDED **`, 0 failures (baseline 1311 + 9 new = 1320; if the Foundation PRs have merged first the baseline is 1341).

- [ ] **Step 2: Diff gate**
```bash
git diff --stat ux/design-specs..HEAD -- ios/
```
Expected: exactly `ios/PT-Helper/COIL/DesignSystem.swift` and `ios/PT-Helper/COILTests/DesignTokenContrastTests.swift`.

- [ ] **Step 3: Before/after screenshots** on the simulator, launched with `--uitesting --skip-onboarding --seed-mock-data` (and once with `--uitesting` alone for onboarding): Home (week-strip day names brighter; "3 exercises" meta darker), Onboarding step 1 (field captions at 0.70 clearly above helper copy at 0.55; placeholders visible at 0.55; Continue visibly dimmed while disabled; the Skip control keeps its own alpha and must not change), Settings/Profile (row meta; the version footer is a hardcoded white 0.5 and does not change), Progress (stat labels, "Personal best" line, and the pain-chart dashed grid lines which use `mutedText.opacity(0.3)`), and Achievements (locked rows: the `mutedText`-tinted circle fill and lock icon get slightly darker — they must still read as locked, not as enabled). `mutedText` also tints dots in `RecoveryInsightsCardView` and `ReAssessmentComparisonView`; those are reachable only with live data, so they are checked by reading the code, not screenshots. Expected differences are exactly those; anything else is a regression. Save to `/tmp/coil-tokens-qa/`.

- [ ] **Step 4: Push and open the PR**
```bash
git push -u origin ux/design-tokens
gh pr create --base ux/design-specs --title "Design tokens: AA-passing muted text, on-dark tiers, icon fonts, streak colour" --body "$(cat <<'EOF'
Implements docs/superpowers/specs/2026-09-14-design-tokens-design.md. DesignSystem.swift + one test file; no view changes (OnboardingColors kept as forwarding aliases for the 53 call sites).

- mutedText: light #7A8A8D → #5F6E72 (3.59 → 5.30:1 on white), dark #6E8285 → #7E9396 (3.97 → 4.97:1 on the dark card)
- textOnDarkSecondary (0.70, 8.97:1) and textOnDarkTertiary (0.55, 6.01:1); onDark* surface tokens; tabInactive 0.45 → 0.55
- AppFonts.iconXS/S/M/L/XL; AppColors.streak / streakTint
- PrimaryButtonStyle disabled: 35% capsule, 70% label, no shadow (was a solid grey that read as enabled)
- DarkTextField prompt uses onDarkMuted, the 0.55 helper tier (placeholders were the system grey on ink; review found 0.70 read too close to typed text)
- DesignTokenContrastTests: alpha-aware WCAG floors for the changed pairs plus the documented accentText-on-ink trap

Verification: UnitPlan green; before/after screenshots of Home, Onboarding step 1, Profile, Progress attached.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** T1 → Task 3; T2, T3, T7 (tokens) → Task 2; T4, T5 → Task 4; T6 → Task 5; T7 (aliases), T8 → Task 6; Tests section → Task 1 (the `textOnDarkSecondary ≥ 7.0` and negative-control cases included); Verification → Task 7.
- **Ordering:** Task 1's test file references `textOnDarkTertiary`, `textOnDarkSecondary`, `onDarkLabel` and `tabInactive`; Task 2 defines all four, so the branch compiles from Task 2 on. `onDarkLabel` is defined in Task 2 (not Task 6) precisely so the test compiles before the alias fold.
- **Type consistency:** `CoilPalette.textMuted/textSecondary/card/page/ink/accentDeep/errorRed` are `UIColor`; `AppColors.*` are `Color` and go through `UIColor(_:)` in the tests; `assertAA(_:over:_:floor:styles:)` signature used identically in every test.
- **Known judgement calls:** the existing `ContrastRegressionTests` harness ignores alpha (it measures `textOnDarkMuted` as opaque white); this plan leaves it as is and adds the alpha-aware file rather than rewriting a passing suite — noted for the design pass.

---

## Audit Results

### Structural Review
1–5, 7 PASS (anchors verified line-for-line; `import SwiftUI` suffices as in the sibling test; 53 `OnboardingColors.` call sites confirmed; Foundation branches don't touch `DesignSystem.swift`). Hand-checked maths: #5F6E72 on white = 5.30:1; white@0.55 on ink = 6.01:1.
6. TESTABILITY — FAIL: `testDanger_onCard_meetsAA` (dark #CB4238 on #16232A = 3.35:1) and `testCTAText_onCTABackground_meetsAA` (white on dark #17A6A2 = 2.99:1) would fail permanently in dark mode since no task touches those values; `ContrastRegressionTests` has 10 tests, not 9.
OVERALL: NEEDS REVISION

### Adversarial Review
1. FATAL FLAW — `textMuted` also tints non-text uses (Achievements lock fill/icon, chart grid lines, dots) that Task 7's screenshot list didn't visit.
2. HIDDEN ASSUMPTION — mapping `subLabel` and `muted` to the same 0.55 value flattens a deliberate two-tier hierarchy in the onboarding form.
3. SIMPLER ALTERNATIVE — none found.
4. WHAT BREAKS — nothing functional; cosmetic drift on Achievements and the chart. `.disabled()` never dims a custom ButtonStyle, so Task 5 is the single dimming source (no double-dim).
5. FIRST HOUR TEST — the "9 passed" baseline count is wrong (10).
VERDICT: MINOR CONCERNS

### Revisions applied (2026-09-15)
- The two fixed-pair tests are scoped to `.light` with the dark values recorded as follow-ups in the spec (renamed `…meetsAAInLight`).
- `onDarkLabel = textOnDarkSecondary` (0.70) and `onDarkMuted = textOnDarkTertiary` (0.55) keep two tiers; the spec's T7 table updated.
- Baseline counts corrected to 10 / 19; Task 7's screenshot list gained Achievements and the Progress chart; the code-only check for the dot tints is stated.

**Overall after revisions: MINOR CONCERNS** (re-audited once).
