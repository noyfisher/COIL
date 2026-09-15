# Design Tokens — Design Spec

**Date:** 2026-09-14 · **Workstream:** 2 of 3 (Foundation → Tokens → IA) · **Source:** `docs/archive/ux-audits/ux-audit-2026-09-14.md` (cross-cutting S1, S2, S6, S7, N2, O3, O6, O8)
**Branch:** `ux/design-tokens` (own worktree, rebased on `main` after workstream 1 merges) · **Delivery:** one PR touching `ios/PT-Helper/COIL/DesignSystem.swift` and one new test file only.

## Goal

Make the token layer accessible by construction: the muted text token passes WCAG AA where it is used, on-dark text has named tiers instead of ad-hoc alphas, icon glyph sizes and the streak colour become tokens, disabled primary buttons look disabled, and the onboarding palette folds into `AppColors`. No view file changes in this PR: aliases keep every call site compiling, and the sweep happens in the IA workstream and the later design pass.

## Non-goals

- No view edits, no call-site sweeps, no visual redesign. Views change appearance only where a token they already use changes value.
- No new component variants (`CoilBadge` tones, segmented control) — those belong to the deferred design pass.
- Dark mode values change only where needed to pass AA; the palette hues are untouched.

## Changes (all in `DesignSystem.swift`)

### T1 — `mutedText` passes AA in both appearances

`CoilPalette.textMuted`: light `0x7A8A8D` → `0x5F6E72`; dark `0x6E8285` → `0x7E9396`.

Measured (WCAG 2.x):

| Pair | Before | After |
|---|---|---|
| light on card `#FFFFFF` | 3.59:1 | 5.30:1 |
| light on page `#F3F5F4` | 3.28:1 | 4.84:1 |
| dark on card `#16232A` | 3.97:1 | 4.97:1 |
| dark on page `#0E1518` | 4.56:1 | 5.71:1 |

`AppColors.mutedText` keeps its name; ~40 call sites darken slightly with no code change.

### T2 — On-dark text tiers

Add next to `textOnDark` / `textOnDarkMuted`:

```swift
static let textOnDarkSecondary = Color.white.opacity(0.70)   // 8.97:1 on ink
static let textOnDarkTertiary  = Color.white.opacity(0.55)   // 6.01:1 on ink — the floor for 11pt text on ink
```

`textOnDarkMuted` (0.6) stays for compatibility. Doc comment states the rule: nothing below 0.55 alpha may be used for text on `darkSurface` / `navBackground`.

### T3 — Tab bar inactive colour

`AppColors.tabInactive`: `Color.white.opacity(0.45)` (4.45:1) → `0.55` (6.01:1).

### T4 — Icon glyph fonts

```swift
// SF Symbols follow the system font; these are the only sanctioned glyph sizes.
static let iconXS = Font.system(size: 12, weight: .semibold)
static let iconS  = Font.system(size: 14, weight: .semibold)
static let iconM  = Font.system(size: 16, weight: .semibold)
static let iconL  = Font.system(size: 20, weight: .semibold)
static let iconXL = Font.system(size: 24, weight: .bold)      // the tab bar "+"
```

Added to `AppFonts` under a new `// MARK: Icons` section. No call sites change in this PR.

### T5 — Streak colour

```swift
static let streak     = Color(CoilPalette.pop)
static let streakTint = Color(CoilPalette.pop).opacity(0.12)
```

Added to `AppColors` (Brand section). Replaces direct `Color(CoilPalette.pop)` use in views during the IA workstream.

### T6 — Disabled primary button

`PrimaryButtonStyle`: when `isDisabled`, background `AppColors.ctaBackground.opacity(0.35)` (was solid `mutedText`), label `.opacity(0.7)`, and no shadow. Enabled rendering unchanged.

### T7 — Fold `OnboardingColors` into `AppColors`

Add to `AppColors`:

```swift
// MARK: On-dark surfaces (onboarding / hero)
static let onDarkCard       = Color.white.opacity(0.06)
static let onDarkBorder     = Color.white.opacity(0.10)
static let onDarkInput      = Color.white.opacity(0.08)
static let onDarkChip       = Color.white.opacity(0.10)
static let onDarkChipBorder = Color.white.opacity(0.14)
static let onDarkLabel      = textOnDarkSecondary           // was subLabel 0.45 → 0.70 (field captions)
static let onDarkMuted      = textOnDarkTertiary            // was muted 0.35 → 0.55 (helper copy)
```

`enum OnboardingColors` remains with the same seven static names, each forwarding to the `AppColors` value above, marked `// Deprecated: use AppColors.onDark*` so views compile unchanged. `subLabel` and `muted` therefore get lighter (this is the AA fix for onboarding helper text and "Skip"-class labels) and keep their two-tier hierarchy: captions at 0.70 sit visibly above helper text at 0.55 (the plan audit caught that a single value would have flattened them).

### T8 — `DarkTextField` placeholder

`DarkTextField` uses `TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundColor(AppColors.onDarkMuted))` so placeholders render at 6.01:1 (the 0.55 helper tier) instead of the system placeholder grey. Code review moved this down from the 0.70 caption tier: a placeholder shares the field's font with typed white text, and at 0.70 it sat only 1.9:1 from a typed value (2.9:1 at 0.55) and was identical to the `OnboardingFieldLabel` caption above it.

## Tests — `COILTests/DesignTokenContrastTests.swift`

A pure contrast harness (no UI):

- `func contrast(_ fg: UIColor, over bg: UIColor, style: UIUserInterfaceStyle) -> Double` resolves both colours with `UITraitCollection(userInterfaceStyle:)`, alpha-blends `fg` over `bg` (so `Color.white.opacity(x)` tokens are handled), and returns the WCAG ratio.
- Assertions, each in `.light` and `.dark`:
  - `mutedText` over `cardBackground` ≥ 4.5; over `pageBackground` ≥ 4.5
  - `secondaryText` over `cardBackground` ≥ 4.5
  - `textOnDarkTertiary` over `darkSurface` ≥ 4.5; `textOnDarkSecondary` over `darkSurface` ≥ 7.0
  - `tabInactive` over `navBackground` ≥ 4.5
  - light only: `ctaText` over `ctaBackground` ≥ 4.5 (dark `#17A6A2` under white measures 2.99:1 — follow-up below)
  - light only: `danger` over `cardBackground` ≥ 4.5 (dark `#CB4238` on the dark card measures 3.35:1 — follow-up below)
  - light only: `accentText` over `cardBackground` ≥ 4.5
- One negative control that documents the known trap: `accentText` over `darkSurface` in `.light` is asserted **< 4.5** with a message pointing at the `accentText` doc comment, so a future "fix" that silently changes the trap is noticed.

The file goes in the UnitPlan (auto-discovered).

## Verification

- `xcodebuild build` + UnitPlan green (the new test file included).
- Simulator screenshots of Home, Onboarding step 1, Settings and Progress before/after, attached to the PR: expected differences are slightly darker meta text, lighter onboarding helper text, brighter inactive tab labels, and a visibly dimmed disabled Continue button.
- `git diff --stat` shows exactly two files.

## Follow-ups (not this PR)

- **Dark-mode pairs found by the plan audit:** white on the dark CTA (`accentDeep` dark `#17A6A2`) is 2.99:1 and the dark danger red (`#CB4238`) on the dark card is 3.35:1. Both predate this PR and are gated light-only in `DesignTokenContrastTests`; fixing them means darkening `accentDeep`'s dark variant (or switching the CTA on-colour to `textOnAccent` in dark) and lightening `errorRed`'s dark variant — a separate token PR with its own screenshots.
- Sweep views to `AppFonts.icon*`, `AppColors.streak`, `AppColors.onDark*`, `textOnDarkSecondary/Tertiary` (IA workstream for the screens it touches; design pass for the rest), then delete the `OnboardingColors` aliases.
- Consider `AppFonts.nano` (10pt Inter) only if the design pass keeps a 10pt "weeks" label; otherwise `MyPlanTab.swift:194` moves to `micro`.

### Raised in code review during implementation (decide before the sweep)

- **Icon tokens and Dynamic Type.** `AppFonts.icon*` are fixed `Font.system(size:)` fonts and do not scale with Dynamic Type, unlike every other `AppFonts` token. They codify the app's existing fixed-size glyphs, and the comment scopes them to standalone chrome glyphs (symbols inline with text take the text's token). Alternatives are text-style glyph fonts (`.caption`/`.footnote`/`.callout`/`.title3`) or `@ScaledMetric` at the call site. The ladder also skips 18pt (8 glyph sites, more than 20pt's 3), has nothing below 12pt (9 sites at 10–11pt), and about a third of glyph sites use `.regular` weight, which the `.semibold` tokens would thicken.
- **Disabled primary button on light grounds.** The 35% capsule with a 70% label measures 6.7:1 label-vs-capsule on ink but 1.5:1 on the light page (`PainDetailView`, the one light-ground caller of four). A ground-unaware `ButtonStyle` cannot do better with a white label; the design pass should add an `onDark:` parameter or an opaque neutral disabled fill for light call sites. The `isDisabled` flip also snaps (only `isPressed` is animated).
- **`mutedText` light on fixed-dark grounds** dropped from 4.84:1 to 3.28:1 on ink (2.61:1 on `inkElevated`). No call site paints it there today, but the token now belongs to the same trap class as `accentText` and its doc comment should say so. `Models/BodyMapConstants.swift:151` `paletteMuted` is a hand-copied `0x7A8A8D` that has drifted from the new value.
- **Retire `textOnDarkMuted` (0.6)** into the Secondary/Tertiary ladder (8 call sites), and consolidate the alpha-blind `ContrastRegressionTests` harness with `DesignTokenContrastTests`.
- **Streak / `pop`.** `AppColors.streak`/`streakTint` have no consumers yet; 14 direct `Color(CoilPalette.pop)` uses across 6 views at three tint alphas (0.08 / 0.10 / 0.12), some not streak-related (wellness motivation, Progress), need their own token or the sweep.
- **Onboarding tiers are lopsided.** `OnboardingColors.subLabel` (0.70) has one consumer (`OnboardingFieldLabel`) and `muted` (0.55) fourteen; the sweep decides which copy earns the caption tier. `DarkTextField`, `OnboardingFieldLabel` and `DarkChipButton` inside `DesignSystem.swift` can move to `AppColors.onDark*` without touching a view.

### Found by the screenshot QA

- **Two of the four disabled-CTA callers are on light grounds**, not one: `NotesView` puts its button on a white card (measured 1.66:1 label-vs-capsule) alongside `PainDetailView` (1.5:1). The ground-aware variant above should cover both.
- **Settings version footer** (`SettingsView.swift:66`) is a hardcoded `Color.white.opacity(0.5)` on ink, under the 0.55 floor this PR documents; it did not change and belongs in the sweep.
- **Appearance = System did not follow the simulator's dark appearance** during QA (SpringBoard dark, COIL light) while the app's explicit Dark setting worked. Possibly a simulator quirk; check on a device before treating it as a bug.
- The real onboarding step 1 is behind the health-data consent gate (no launch flag bypasses it), so the "after" captures use the identical form reached via Settings → Update Health Info.
