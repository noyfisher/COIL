# Profile, Progress and Workout IA — Design Spec

**Date:** 2026-09-14 · **Workstream:** 3 of 3 (Foundation → Tokens → IA) · **Source:** `docs/archive/ux-audits/ux-audit-2026-09-14.md` (Progress #2, #3, #6; Profile #2–#5; Workout #2, #3) · **Mockup:** https://claude.ai/code/artifact/0c43c9f3-97d9-481e-a2c6-39f7950c664c (approved 2026-09-14)
**Branch:** `ux/profile-progress-ia` (own worktree, rebased on `main` after workstreams 1 and 2 merge) · **Delivery:** three PRs — IA-1 Profile, IA-2 Progress, IA-3 Workout.

## Goal

Give the Profile tab a real identity (a masthead that answers "who am I here and how am I doing" followed by grouped settings), remove the duplicate Settings entry point, lighten the Progress tab without removing content, and make the guided workout a focused full-screen flow. Direction: editorial-athletic restraint — one ink surface per screen, Industry-Bold numbers as the visual event, calm white cards for the rest, one orchestrated reveal per screen.

## Constraints

- SwiftUI; every colour, spacing, radius and font is an existing `DesignSystem.swift` token (post-workstream-2 tokens included: `textOnDarkSecondary/Tertiary`, `onDark*`, `streak`, `icon*`). No new tokens; anything the mockup wants that a token cannot express is dropped.
- Industry-Bold + Inter stay (CLAUDE.md design system wins over the frontend-design font advice).
- Light page for all three screens; dark is used only as the Profile masthead surface (`darkSurface`).
- `AccountDeletionOutcome` stays nested in `SettingsView` (`COILTests/AccountDeletionOutcomeTests.swift` references `SettingsView.AccountDeletionOutcome`).
- Existing accessibility identifiers used by UI tests keep their names: `settings.signOutButton`, `settings.deleteAccountButton`, `settings.reminderToggle`, `settings.editProfileButton`, `progress.streakBadge`, `workout.completeSetButton`.

## PR IA-1 — Profile tab

### Structure

| File | Role |
|---|---|
| `Views/ProfileTab.swift` (new) | Tab root: `NavigationStack { ScrollView { VStack(spacing: 0) { ProfileHeroCard; settings groups } } .coilNavBar() }`. Owns `showEditProfile` (`.sheet { OnboardingEditView() }`). Moves out of `MainTabView.swift:201-218`. |
| `Views/Components/ProfileHeroCard.swift` (new) | The masthead. Input: `ProfileSummary` + `onEditHealthInfo`. No data access. |
| `Models/ProfileSummary.swift` (new) | Value type + `ProfileSummaryBuilder` (pure). |
| `Views/SettingsView.swift` | Becomes the grouped-settings body only: three `CoilDividerHeader` groups and their cards. Keeps `AccountDeletionOutcome`, `deleteAccount`, sign-out and consent-withdrawal logic and all confirmation dialogs. Loses the profile card, the standalone `NavigationStack`, `showsDoneButton` and the Done toolbar item (no sheet host remains). |
| `Views/ProgressTab.swift` | Loses the gear toolbar button, `showSettings`, the Settings sheet and the `showProfileEdit` full-screen cover. |
| `Views/MainTabView.swift` | `ProfileTab()` now comes from its own file; nothing else. |

### `ProfileSummary`

```swift
struct ProfileSummary: Equatable {
    var displayName: String            // "First Last" trimmed; "Your profile" when the profile is nil or the name is empty
    var initials: String               // first letters of first + last; first two letters of a single name; "?" when empty
    var detailLine: String?            // "34 · Moderately active" — age omitted when it would be < 1; activity omitted when empty; nil when both are
    var conditionChips: [String]       // current injuries as "\(bodyArea) · \(description prefix ≤ 24 chars)" then medicalConditions; de-duplicated, max 4
    var activePlan: ActivePlan?        // struct { name: String; statusText: String }  statusText: "Week 2 of 6" / "Not started" / "Completed"
    var stats: Stats                   // struct { streak: Int; planWeek: (current: Int, total: Int)?; sessions: Int }
}
enum ProfileSummaryBuilder {
    static func build(profile: UserProfile?, plans: [RehabPlan], streak: StreakData, sessionCount: Int, now: Date = Date()) -> ProfileSummary
}
```

Plan choice reuses `HomeProgramLogic.preferredPlan(from:)` from workstream 1 (prefers `.active`). `planWeek` is nil unless the chosen plan is `.active`.

Tests (`COILTests/ProfileSummaryBuilderTests.swift`): nil profile → placeholder name, "?" initials, nil detail line, no chips; full profile with two current injuries and one condition → three chips in that order; chip cap at 4; active plan 10 days in → "Week 2 of 6" and `planWeek == (2, 6)`; only a not-started plan → statusText "Not started", `planWeek == nil`; sessions passthrough.

### `ProfileHeroCard` (matches the mockup)

- Background `AppColors.darkSurface`, padding `AppSpacing.xl` horizontal, `xl` top, `xxl` bottom, `VStack(spacing: AppSpacing.lg)`; sits directly under the nav bar so the ink is continuous (same construction as `WeekCompletionStrip` on Home).
- Row: 56pt circle filled with `AppColors.primaryGradient`, initials in `AppFonts.sectionTitle` / `ctaText`; name in `AppFonts.heroTitle` / `textOnDark`; detail line in `AppFonts.small` / `textOnDarkMuted`.
- Chips: `FlowLayout(spacing: AppSpacing.sm)` of `Text` in `AppFonts.smallMedium` / `textOnDark`, background `onDarkChip`, 1pt `onDarkChipBorder`, `AppCorners.small`, padding `tight` × `sm`. Informational: `.accessibilityElement(children: .combine)` with label "Conditions: …".
- Stats: `HStack` of three equal columns — value in `AppFonts.statNumber` / `accent`, label in `AppFonts.micro` uppercase kerning 1 / `textOnDarkMuted`: "Day streak", "Plan week" (value "2" with " / 6" in `AppFonts.cardTitle` / `textOnDarkMuted`; "—" when nil), "Sessions". Each column is one accessibility element ("3 day streak").
- Plan row: `CoilBadge(text: "Active")` only when the chosen plan is `.active`; name in `AppFonts.smallSemiBold` / `textOnDark`; statusText in `AppFonts.small` / `textOnDarkMuted`. Hidden when `activePlan == nil`.
- "Edit Health Info": `Button(...).buttonStyle(SecondaryButtonStyle())`, identifier `settings.editProfileButton` (moved here from the actions card).
- Reveal: the hero and each group fade-and-rise once on appear with `AppAnimations.springy`, staggered by `0.05 s` per group via `.animation(_:value:)` on an `@State appeared` flag. Respect `accessibilityReduceMotion` (no offset, opacity only).

### Settings groups (`SettingsView`)

Order and contents:
1. `CoilDividerHeader("Preferences")` → appearance card (unchanged) · notifications card (unchanged, labels from workstream 1).
2. `CoilDividerHeader("Help & Legal")` → help card (Contact Support, Report a Concern, Safety Resources, Rate COIL) · legal card (Privacy Policy, Terms of Service, Consumer Health Data Policy, Withdraw Health Data Consent when consented).
3. `CoilDividerHeader("Account")` → one card: Sign Out (danger text) · Delete Account. The former `actionsCard` and `dangerZoneCard` merge; "Update Health Info" leaves this card (it lives in the hero).
4. Debug card (Export Debug Log, Session Events, Image Diagnostics) wrapped in `#if DEBUG` and placed last, before the version footer.
5. Version footer in `AppFonts.micro` / `mutedText`.

All cards use `.cardStyle()` at zero inner padding (rows carry their own padding) — add a `padding` parameter to `CardStyle` only if `.cardStyle()`'s fixed `AppSpacing.lg` padding cannot be removed by wrapping; otherwise build the group card as `VStack(spacing: 0) { rows }.background(AppColors.cardBackground).cornerRadius(AppCorners.card).overlay(border).shadow(AppColors.cardShadowColor…)` exactly as the existing cards do, with the radius unified to `AppCorners.card`. Row icons use `AppFonts.iconS`; the 52pt divider inset becomes `AppSpacing.huge + AppSpacing.xl`.

Delete `SettingsView.profileCard`, `initials` (moved to the builder), `showsDoneButton`, the inner `NavigationStack`, and `@Environment(\.dismiss)` (nothing presents it any more; `deleteAccount` no longer calls `dismiss()` — sign-out already routes to the auth root).

### Tests and UI tests

- `SettingsUITests.swift:11-19`: replace the gear path (`progress.settingsButton`) with: tap the tab bar "Profile" button (label `Profile`) → wait for `settings.signOutButton`. Other assertions unchanged.
- `ShellNavigationUITests:89` already uses the Profile tab; unchanged.
- New `ProfileSummaryBuilderTests` (above).

### Acceptance

Profile tab: wordmark nav bar, ink masthead with the seeded user ("Test", streak 3, Knee Rehab Plan week 2 of 6, 3 sessions), three labelled groups, no Done button, no "Settings" title; Progress tab has no gear; sign-out and delete flows behave as before; build + UnitPlan + `SettingsUITests` green.

## PR IA-2 — Progress tab

`Views/ProgressTab.swift` and `Views/Components/OutcomePromptView.swift`.

1. **Order** (top → bottom): last analysis · region chips · pain trend · stats row + personal best · **actions row** · Recovery Insights card · **outcome banner** · recent workouts · re-assessment card. Empty/error states unchanged.
2. **Actions row**: `HStack(spacing: AppSpacing.md)` of two `ActionTile`s (private view in `ProgressTab.swift`): `VStack(alignment: .leading, spacing: AppSpacing.sm)` — 40pt icon tile (`accentTint`, `AppCorners.small`, glyph `AppFonts.iconM` / `accent`), title `AppFonts.bodySemiBold` / `primaryText`, subtitle `AppFonts.caption` / `secondaryText` — padded `AppSpacing.lg`, with the same chrome `navLinkRow` uses today (`cardBackground`, `AppCorners.card`, 1pt `cardBorder` stroke, `cardShadowColor` radius 8 / y 2). Each tile is a `NavigationLink`: to `WorkoutSessionView()` ("Log Workout" / "Add a session") and to `NotesView()` ("Recovery Notes" / "Your observations"); subtitles are fixed strings. Identifiers `progress.logWorkoutTile`, `progress.notesTile`. The two `navLinkRow` entries at 128-143 are removed.
3. **Outcome banner**: `OutcomePromptView` gains `var style: Style = .card` with `.banner`. Banner = collapsed one-line row (sparkles glyph `accent`, "How accurate was your analysis?" in `AppFonts.small`, "Rate" in `AppFonts.captionSemiBold` uppercase / `accentText`, close glyph `mutedText`), background `elevatedSurface.opacity(0.6)`, `AppCorners.card`, 1pt `subtleBorder`. Tapping the row (not the close) expands in place with `AppAnimations.smooth` to the existing four options; submitting shows the existing confirmation line then collapses via `onComplete`. Close keeps recording `.notApplicable` (`OutcomeRecorder` semantics unchanged). Identifiers unchanged (`outcomePrompt.*`) plus `outcomePrompt.expand` on the row. `ProgressTab` passes `.banner`.
4. **Recent workouts**: date via `session.date.formatted(date: .abbreviated, time: .omitted)`; trash button unchanged (P3, deferred).
5. **Tokens**: `Color(CoilPalette.pop)` → `AppColors.streak` / `streakTint`; `.font(.system(size:…))` glyphs → `AppFonts.icon*`; `spacing: 3` → `AppSpacing.xs`; `Spacer(minLength: 100)` → `AppSpacing.xxxl * 2` is *not* a token — use `FloatingTabBarMetrics.clearance` for the two bottom spacers and `AppSpacing.xxxl` for the top ones.

Acceptance: same data, new order; the actions sit under the stats; the banner collapses/expands; screenshot in the PR.

## PR IA-3 — Guided workout focus

1. `Views/TabSelection.swift`: `@Published var isTabBarHidden = false`.
2. `Views/MainTabView.swift:66-77`: wrap `FloatingTabBar` in `if !tabSelection.isTabBarHidden { … .transition(.move(edge: .bottom).combined(with: .opacity)) }` inside a container with `.animation(AppAnimations.smooth, value: tabSelection.isTabBarHidden)`.
3. `Views/GuidedWorkoutView.swift`: add `@EnvironmentObject private var tabSelection: TabSelection`; `.onAppear { tabSelection.isTabBarHidden = true }`, `.onDisappear { tabSelection.isTabBarHidden = false }`. Bottom paddings at 332 and 479 change from `FloatingTabBarMetrics.clearance` to `AppSpacing.lg` (the safe area supplies the home-indicator inset). `Views/GuidedWorkoutSummaryView.swift:113` spacer likewise → `AppSpacing.xxl` (the summary shows while the bar is still hidden; it is popped via the nav bar Done/Back, which restores the bar through `onDisappear`).
4. `Views/Components/ExerciseImageView.swift`: `var showsDifficultyBadge: Bool = true`; `fullImageView` omits the `DifficultyBadge` and the `AppSpacing.lg` vertical padding when false; `generatingContent` likewise. `GuidedWorkoutView.swift:177` passes `showsDifficultyBadge: false`.
5. Tokens in the file: `HStack(spacing: 32)` → `AppSpacing.huge`; `.system(size: 16/14…)` → `AppFonts.iconM/iconS`; the 6pt progress segments become `Capsule()` shapes (same look as `cornerRadius: 3`, no raw number); `Color(CoilPalette.pop)` → `AppColors.streak`.
6. Verify the `MainTabView` `ZStack` still lays out `TabView` full-height when the bar is absent (no content jump on hide: the tab content already ignores the bar).

Tests: `GuidedWorkoutUITests` gains `testWorkoutHidesTabBar`: after `workout.completeSetButton` exists, assert `app.buttons["Home"]` does **not** exist; after End → Discard, assert it exists again. Unit: `TabSelectionTests.testTabBarHiddenDefaultsFalse` (trivial, documents the flag).

Acceptance: no tab bar during exercise, rest and summary; bottom bar sits on the safe area; the Beginner badge no longer clips (screenshot); build + UnitPlan + `GuidedWorkoutUITests` green.

## Verification (workstream)

- Each PR: `xcodebuild build` + UnitPlan; the touched UI test class run locally; FullPlan before merge.
- Screenshots of Profile (top + scrolled), Progress (top + scrolled), Workout (exercise + rest) attached to each PR and compared against the mockup.
- Token audit: `grep -n "\.font(\.system(size" ios/PT-Helper/COIL/Views/ProfileTab.swift ios/PT-Helper/COIL/Views/SettingsView.swift ios/PT-Helper/COIL/Views/ProgressTab.swift ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` returns nothing; likewise for `Color.white.opacity`, `Color(CoilPalette`, `cornerRadius: [0-9]`.

## Deferred (design pass, not this workstream)

Unifying page chrome on Rehab Plan / Achievements, one primary CTA style, `CoilSegmentedControl`, `ChipButton` on the Progress filter, `.cardStyle()` everywhere, the always-visible trash icons.

## Follow-ups raised during IA-1 implementation (2026-09-16)

- `HomeProgramLogic` (pure logic) lives in `Views/HomeTab.swift` and is now consumed from `Models/ProfileSummary.swift`; move it to `Models/`. `isActive(_:)` is duplicated there and in `ProfileSummaryBuilder`; a computed `RehabPlan.PlanStatus.isActive` would replace both. `preferredPlan`'s "rehab over wellness" preference has no test.
- `OnboardingEditView` → `OnboardingViewModel.loadProfile` performs a live `Firestore.getDocument()` under `--uitesting` whenever a persisted Auth session exists; `SettingsUITests.testEditHealthInfo_opensTheEditor` is the first UI test on that path. Short-circuit under `TestDataSeeder.isUITesting` from the seeded `UserProfileService.shared.profile`. The same root cause leaves the editor's name and weight fields empty for the seeded profile, and its pinned Continue button overlaps the weight field (both pre-existing).
- In dark mode the masthead (`darkSurface`) is nearly indistinguishable from the dark page; decide between `darkSurfaceElevated` or a visible edge. The masthead scrolls with the content, so a rubber-band pull shows the light page above it (accepted). `ProfileHeroCard` uses `textOnDarkMuted` per this spec while `DesignSystem.swift` asks new code for `textOnDarkSecondary/Tertiary` — decide before IA-2 repeats it.
- `SettingsView`: `@ViewBuilder` on the single-expression card properties is vestigial; `import FirebaseFirestore` is unused; the DEBUG card has no `CoilDividerHeader`. `SettingsUITests.testSettings_AllOptions_Displayed` now duplicates `ShellNavigationUITests.testProfileTab_ShowsSettings`; `testGearSheet_showsDoneAndDismisses` was deleted (its intent lives in `testProfileTab_hasNoDoneButton`).
- The workstream token-audit grep lists `ProgressTab.swift` with the IA-1 files; its sweep is IA-2 §5's job, so read the grep per PR. `docs/archive/ux-audits/ux-audit-2026-04-05.md` #16 (deep link "profile" landing on a tab with no profile view) is resolved by IA-1.

## Follow-ups raised during IA-2 implementation (2026-09-16)

- On iPhone 16 Pro at the Progress tab's default scroll offset the actions row straddles the floating tab bar, so only its top strip is tappable at rest; content is meant to pass under the bar, but the design pass may prefer the row above the fold or a translucent scrim on the bar. XCUI reports a partially covered element as hittable and then taps the covered part; `ProgressTabUITests.scrollClearOfTabBar` scrolls until the element sits above the lifted "+" button.
- Identifier convention: an identifier on a `NavigationLink` whose label is a `.combine`d element is queried via `app.descendants(matching: .any)[…]`, never `app.buttons[…]` — IA-3 must follow this for any similar shape.
- The empty/error branches now use 40pt spacers where there were 100pt, followed by the actions row; their vertical rhythm changed and deserves a look in the design pass.
- `OutcomePromptView`'s `.card` style has no production caller left (preview only); retire it or reuse it deliberately rather than let it drift untested.
- The personal-best pill's tint is `streakTint` (0.12) where it was the palette orange at 0.08 — intended by the Tokens spec, confirmed visually.
- Pre-existing, seen in the IA-2 screenshots: the pain-trend chart clips its last x-axis label against the trailing gutter; region chips only appear when sessions carry per-region pain (the seed has none); pushed screens such as Recovery Notes still render on the dark `bgGradient` under a light tab (the audit's chrome split).

## Follow-ups raised during IA-3 implementation (2026-09-16)

- The tab bar's `.move(edge: .bottom)` transition in `MainTabView` is not gated on `accessibilityReduceMotion`; `RevealOnAppear` (ProfileTab) drops the translation under Reduce Motion and keeps opacity. Design pass: apply the same gate (or an `AppAnimations` helper) to the bar transition and the other bare `AppAnimations.smooth` call sites.
- `showsDifficultyBadge` had to be threaded into `ExerciseIllustrationView` as well (single caller: `ExerciseImageView.fallbackContent`), because the SF-Symbol fallback rendered its own pill and `AppSpacing.lg` padding unconditionally; the workout under `--uitesting` shows exactly that fallback. Turning the badge off also drops the image container's vertical `lg` padding; checked in the IA-3 screenshots, nothing crowds the 200pt frame.
- Pre-existing, not introduced here: `GuidedWorkoutView.onAppear` re-runs its analytics log and checkpoint check whenever the pushed view re-appears (a programmatic tab switch via deep link or the pop-to-root notification, then back), so `.workoutStarted` can log twice and the workout's own just-saved checkpoint can re-surface "Resume Workout?". The IA-3 bar toggle is idempotent, and with the bar hidden the user can no longer switch tabs by hand. Fix in a functional PR: gate the analytics/checkpoint block behind a one-time `@State` flag. Unverified on the simulator.
- `AppFonts.iconM` is semibold where the replaced literal was medium, so the Form/Swap/Skip glyphs are slightly heavier (the Tokens ladder, accepted).
- `GuidedWorkoutSummaryView.swift` keeps raw values outside this plan's sweep: `Color(CoilPalette.pop)` five times, `.system(size: 16, weight: .semibold)`, `.system(size: 22, …, design: .rounded)`, and the `size: 50` hero glyph. Design pass: `AppColors.streak`/`streakTint`, `AppFonts.iconM`, and a display token for the 22pt rounded number.
- The floating tab bar's buttons carry only `accessibilityLabel` ("Home" …), no `screenName.elementName` identifiers, so UI tests query them by label (`UITestBase.tapTab`, `ShellNavigationUITests`, `testWorkout_hidesTabBarUntilDiscarded`). Add `tabBar.home` etc. in a test-infra PR.
- `testWorkout_hidesTabBarUntilDiscarded` repeats the navigate → End → Discard flow of `testDiscardWorkout_DismissesWithoutSaving` (~15 s); the bar assertions could fold into that test.
