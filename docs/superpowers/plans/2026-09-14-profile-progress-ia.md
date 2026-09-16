# Profile, Progress and Workout IA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Profile tab a masthead built from a pure `ProfileSummary` followed by grouped settings (and remove the duplicate Settings entry on Progress), reorder the Progress tab around an actions row and a collapsible outcome banner, and hide the floating tab bar during a guided workout — as three stacked PRs.

**Architecture:** IA-1 adds a value type + pure builder (`Models/ProfileSummary.swift`), a presentation-only masthead (`Views/Components/ProfileHeroCard.swift`) and a new `Views/ProfileTab.swift`; `SettingsView` shrinks to the grouped-settings body. IA-2 gives `OutcomePromptView` a `.banner` style and rebuilds `ProgressTabContent.body` around an `ActionTile` row. IA-3 adds `TabSelection.isTabBarHidden`, which `MainTabView` observes to drop the bar and `GuidedWorkoutView` toggles on appear/disappear. Every colour, spacing, radius and font is a `DesignSystem.swift` token; new tokens from the Tokens PR (`textOnDarkSecondary/Tertiary`, `onDark*`, `streak`, `icon*`) are consumed here for the first time.

**Tech Stack:** Swift 5 / SwiftUI, XCTest + XCUITest, `xcodebuild` on the iPhone 16 Pro (iOS 18.2) simulator. Spec: `docs/superpowers/specs/2026-09-14-profile-progress-ia-design.md`.

---

## Deviations from the spec, decided while planning

1. **`ProfileSummaryBuilder.build` has no `now:` parameter.** `RehabPlan.status`/`currentWeek` and `UserProfile.age` read the wall clock themselves, so a `now` the builder could not pass through would be misleading. Tests build fixtures relative to `Date()` exactly as `RehabPlanStatusTests` already does.
2. **`ProfileSummary.ActivePlan` carries `isActive: Bool`, and `planWeek` is a `PlanWeek` struct** (a tuple property cannot synthesise `Equatable`).
3. **The Progress actions row also shows in the empty and error states** ("Log Workout" is how a new user gets out of "No Data Yet"). The state views keep an `AppSpacing.xxxl` spacer above and below; `.floatingTabBarClearance()` on the content stays.
4. **`.trackScreen("Settings")` becomes `.trackScreen("ProfileTab")` on the tab**; the settings body is no longer a screen.
5. **`Export Debug Log` stays available in release builds** (it moves into the Help card, under "Report a Concern") — testers use it to report problems. Only "Session Events" and "Image Diagnostics" are `#if DEBUG`.
6. **`settingsRow` gets an `isDestructive:` flag** replacing the `title == "Sign Out"` string check.
7. **PR bases (user chose "stack now"):** IA-1 → `ux/ia-base` (the integration merge of `ux/design-specs` + `origin/ux/foundation-fixes-f2` + `ux/design-tokens`, commit `d78ceae`, pushed to origin); IA-2 → the IA-1 branch; IA-3 → the IA-2 branch. `ux/ia-base` is a frozen snapshot of three PRs that are still open, and `main` merges by squash, so the IA commits must be replayed with `--onto` (which excludes the snapshot's own commits) rather than a plain rebase:
   ```bash
   # once #75–#77 are on main, in this order (each rebase replays ONLY that branch's own commits):
   git fetch origin
   git rebase --onto origin/main ux/ia-base ux/profile-progress-ia
   git rebase --onto ux/profile-progress-ia <IA-1 head before its rebase> ux/ia-2-progress
   git rebase --onto ux/ia-2-progress <IA-2 head before its rebase> ux/ia-3-workout
   ```
   Record each branch's pre-rebase head with `git rev-parse` first. The repo rule is never force-push, so push each rebased branch under a new name (`ux/ia-1-profile-v2`, …), open the PRs from those against `main`, and close the stacked ones. If #75–#77 change under review before IA lands, fast-forward those branches into `ux/ia-base` (`git merge --ff-only` each) and run the same `--onto` recipe against the new base; the token names this plan hardcodes are exactly the ones the Tokens PR exposes, so a rename there is a find-and-replace here.
8. **`MainTabView` is touched only for the bar wrap, and `GuidedWorkoutSummaryView` only for its spacer**, per the spec's file lists; their remaining raw glyph sizes and `CoilPalette.pop` uses stay for the design pass.
9. **The Progress empty/error-state spacers are `AppSpacing.xxxl` above and below**, not `FloatingTabBarMetrics.clearance` for the bottom pair as the spec's IA-2 §5 says: the actions row now follows the state view (deviation 3), and the content container's `.floatingTabBarClearance()` already clears the bar.

## Ground rules for every task

- **Warnings are errors.**
- **Worktree:** `/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1/.claude/worktrees/ux-profile-progress-ia`, branch `ux/profile-progress-ia` for IA-1 (IA-2 and IA-3 switch to their own branches in Tasks 8 and 12). Run everything from there; never `cd` to the main checkout; never `git stash`; never `git add .` — stage the files each task names.
- **Line numbers are anchors as of commit `d78ceae`** (the integration merge). Grep for the quoted code before editing (CLAUDE.md R1).
- **Simulator:** iPhone 16 Pro, iOS 18.2, `A1579757-01DC-4BE8-A068-249FD8467C44`, `-derivedDataPath /tmp/coil-dd-ia`. If it is busy, use the iPhone 16 `8B908AF6-D437-40DC-9593-2DDC315B0480` with the same derived-data path.
- **Build:**
```bash
SIM=A1579757-01DC-4BE8-A068-249FD8467C44
xcodebuild build -project ios/PT-Helper/COIL.xcodeproj -scheme COIL \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /tmp/coil-dd-ia 2>&1 \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
```
  Expected last line `** BUILD SUCCEEDED **`; an `appintentsmetadataprocessor … Metadata extraction skipped` line is benign.
- **Unit test command** (one class; the default UnitPlan includes `COILTests`):
```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj -scheme COIL \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /tmp/coil-dd-ia \
  -only-testing:COILTests/<ClassName> 2>&1 | grep -E "Test Case .* (passed|failed)|error:|\*\* TEST|Executed"
```
- **UI test command** — UI tests run ONLY under FullPlan (UnitPlan excludes `COILUITests`); FullPlan retries a failing test up to 3 times, so a flake shows as "failed" then "passed":
```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj -scheme COIL -testPlan FullPlan \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /tmp/coil-dd-ia \
  -only-testing:COILUITests/<ClassName> 2>&1 | grep -E "Test Case .* (passed|failed)|error:|\*\* TEST|Executed"
```
  A full UnitPlan takes 8–10 minutes: run it detached (`nohup … > log 2>&1 &`) and poll the log, because the Bash tool caps at 600 s.
- **XCUI queries:** query by accessibility identifier, then assert `.label`/`.value`; never put an identifier on a container that holds buttons (it flattens them — see `GuidedWorkoutView.bottomActionBar`'s note).
- Commit messages: imperative sentence, no prefix, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `ios/PT-Helper/COIL/Models/ProfileSummary.swift` (new) | `ProfileSummary` value type + `ProfileSummaryBuilder` (pure) | 1–2 |
| `ios/PT-Helper/COILTests/ProfileSummaryBuilderTests.swift` (new) | Builder unit tests (14) | 1–2 |
| `ios/PT-Helper/COIL/Views/Components/ProfileHeroCard.swift` (new) | The masthead; input `ProfileSummary` + `onEditHealthInfo` | 3 |
| `ios/PT-Helper/COIL/Views/ProfileTab.swift` (new) | Tab root: hero + settings body, edit sheet, `RevealOnAppear` | 4 |
| `ios/PT-Helper/COIL/Views/MainTabView.swift` | Loses the inline `ProfileTab`; IA-3 wraps the bar | 4, 13 |
| `ios/PT-Helper/COIL/Views/SettingsView.swift` | Grouped-settings body only | 5 |
| `ios/PT-Helper/COIL/Views/ProgressTab.swift` | Loses gear/sheet/cover (IA-1); reorder + `ActionTile` + tokens (IA-2) | 5, 9 |
| `ios/PT-Helper/COILUITests/SettingsUITests.swift` | Profile-tab navigation, hero test | 6 |
| `ios/PT-Helper/COIL/Views/Components/OutcomePromptView.swift` | `.banner` style | 8 |
| `ios/PT-Helper/COILUITests/ProgressTabUITests.swift` | Tiles + banner tests | 10 |
| `ios/PT-Helper/COIL/Views/TabSelection.swift` | `isTabBarHidden` | 12 |
| `ios/PT-Helper/COILTests/TabSelectionTests.swift` (new) | Flag tests (2) | 12 |
| `ios/PT-Helper/COIL/Views/Components/ExerciseImageView.swift` | `showsDifficultyBadge` | 14 |
| `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` | Hide/show, paddings, badge, tokens | 15 |
| `ios/PT-Helper/COIL/Views/GuidedWorkoutSummaryView.swift` | Bottom spacer | 15 |
| `ios/PT-Helper/COILUITests/GuidedWorkoutUITests.swift` | Tab-bar hidden test | 16 |

---

### Task 0: Integration base (done during planning; one step remains)

- [x] Worktree `.claude/worktrees/ux-profile-progress-ia` on `ux/profile-progress-ia` from `origin/ux/design-specs` (`e0e1d09`), merged `origin/ux/foundation-fixes-f2` (`aafd13a`) and `ux/design-tokens` (`d78ceae`); no conflicts (Foundation touches views/models/tests, Tokens touches `DesignSystem.swift` + one test).
- [x] Baseline UnitPlan on the merge: `Executed 1350 tests, with 1 test skipped and 0 failures`, `** TEST SUCCEEDED **`.
- [x] **Push the PR base** (done 2026-09-15 from the worktree, pinned to the SHA — the worktree HEAD is already past it):
```bash
git branch ux/ia-base d78ceae
git push -u origin ux/ia-base
```
Result: `* [new branch] ux/ia-base -> ux/ia-base`, `git rev-parse --short ux/ia-base` = `d78ceae`. The IA-1 PR targets this branch.

> **Toolchain note (2026-09-15):** Xcode auto-updated to 27.0 (27A266a) during planning. Until `sudo xcodebuild -license accept` is run, `/usr/bin/git` and every `xcodebuild`/`xcrun` fail with exit 69; `/opt/homebrew/bin/git` works meanwhile. Before Task 1, re-run the baseline build + `-only-testing:COILTests/RehabPlanStatusTests` under Xcode 27 (the compiler jump may surface new warnings under the warnings-as-errors gate) and confirm `xcrun simctl list runtimes` still lists iOS 18.2.

---

## PR IA-1 — Profile tab

### Task 1: `ProfileSummary` and its builder tests (red)

**Files:**
- Create: `ios/PT-Helper/COILTests/ProfileSummaryBuilderTests.swift`

- [ ] **Step 1: Write the failing tests** (full file):

```swift
import XCTest
@testable import COIL

/// `ProfileSummaryBuilder` is pure: profile + plans + streak + session count in,
/// masthead strings out. Plan and age maths use the model's own clock
/// (`RehabPlan.status`, `UserProfile.age`), so plan fixtures are built relative
/// to `Date()` the way `RehabPlanStatusTests` does.
final class ProfileSummaryBuilderTests: XCTestCase {

    private func build(profile: UserProfile? = TestFixtures.makeProfile(),
                       plans: [RehabPlan] = [],
                       streak: StreakData = StreakData(),
                       sessions: Int = 0) -> ProfileSummary {
        ProfileSummaryBuilder.build(profile: profile, plans: plans,
                                    streak: streak, sessionCount: sessions)
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    // MARK: - Identity

    func testBuild_nilProfile_usesPlaceholders() {
        let summary = build(profile: nil)
        XCTAssertEqual(summary.displayName, "Your profile")
        XCTAssertEqual(summary.initials, "?")
        XCTAssertNil(summary.detailLine)
        XCTAssertEqual(summary.conditionChips, [])
        XCTAssertNil(summary.activePlan)
        XCTAssertNil(summary.stats.planWeek)
    }

    func testBuild_fullProfile_namesInitialsAndDetailLine() {
        let profile = TestFixtures.makeProfile(age: 34, activityLevel: "Moderately Active")
        let summary = build(profile: profile)
        XCTAssertEqual(summary.displayName, "Test User")
        XCTAssertEqual(summary.initials, "TU")
        XCTAssertEqual(summary.detailLine, "34 · Moderately Active")
    }

    func testBuild_blankName_fallsBackToPlaceholder() {
        var profile = TestFixtures.makeProfile()
        profile.firstName = " "
        profile.lastName = ""
        let summary = build(profile: profile)
        XCTAssertEqual(summary.displayName, "Your profile")
        XCTAssertEqual(summary.initials, "?")
    }

    func testBuild_singleName_usesFirstTwoLetters() {
        var profile = TestFixtures.makeProfile()
        profile.firstName = "Alex"
        profile.lastName = ""
        XCTAssertEqual(build(profile: profile).initials, "AL")
    }

    func testBuild_emptyActivityLevel_dropsItFromDetailLine() {
        let profile = TestFixtures.makeProfile(age: 40, activityLevel: "")
        XCTAssertEqual(build(profile: profile).detailLine, "40")
    }

    // MARK: - Condition chips

    func testBuild_chips_currentInjuriesThenConditions_descriptionsTruncated() {
        let injuries = [
            UserProfile.Injury(bodyArea: "Right Knee", description: "Patellar tendinopathy", isCurrent: true),
            UserProfile.Injury(bodyArea: "Left Ankle", description: "Old sprain", isCurrent: false),
            UserProfile.Injury(bodyArea: "Lower Back", description: "Disc irritation from lifting last spring", isCurrent: true),
        ]
        let profile = TestFixtures.makeProfile(medicalConditions: ["Asthma"], injuries: injuries)
        XCTAssertEqual(build(profile: profile).conditionChips, [
            "Right Knee · Patellar tendinopathy",
            "Lower Back · Disc irritation from lif",
            "Asthma",
        ])
    }

    func testBuild_chips_dedupedCaseInsensitivelyAndCappedAtFour() {
        let profile = TestFixtures.makeProfile(
            medicalConditions: ["Asthma", "asthma", "Hypertension", "Diabetes", "Osteoporosis"])
        XCTAssertEqual(build(profile: profile).conditionChips,
                       ["Asthma", "Hypertension", "Diabetes", "Osteoporosis"])
    }

    // MARK: - Plan

    func testBuild_activePlanTenDaysIn_reportsWeekTwoOfSix() {
        let plan = TestFixtures.makePlan(name: "Knee Rehab Plan", totalWeeks: 6, startDate: daysAgo(10))
        let summary = build(plans: [plan])
        XCTAssertEqual(summary.activePlan,
                       ProfileSummary.ActivePlan(name: "Knee Rehab Plan", statusText: "Week 2 of 6", isActive: true))
        XCTAssertEqual(summary.stats.planWeek, ProfileSummary.PlanWeek(current: 2, total: 6))
    }

    func testBuild_onlyNotStartedPlan_hasStatusButNoPlanWeek() {
        let plan = TestFixtures.makePlan(name: "Shoulder Mobility Plan", totalWeeks: 4)
        let summary = build(plans: [plan])
        XCTAssertEqual(summary.activePlan,
                       ProfileSummary.ActivePlan(name: "Shoulder Mobility Plan", statusText: "Not started", isActive: false))
        XCTAssertNil(summary.stats.planWeek)
    }

    func testBuild_prefersActivePlanOverNotStarted() {
        let notStarted = TestFixtures.makePlan(name: "Later", totalWeeks: 4)
        let active = TestFixtures.makePlan(name: "Now", totalWeeks: 4, startDate: daysAgo(3))
        XCTAssertEqual(build(plans: [notStarted, active]).activePlan?.name, "Now")
    }

    // MARK: - Stats passthrough

    func testBuild_streakAndSessions_passThrough() {
        var streak = StreakData()
        streak.currentStreak = 3
        streak.longestStreak = 7
        let summary = build(streak: streak, sessions: 12)
        XCTAssertEqual(summary.stats.streak, 3)
        XCTAssertEqual(summary.stats.sessions, 12)
    }
}
```

> **Added at Task 1 code review (2026-09-15):** three more tests pin rules the builder implements — `testBuild_lastNameOnly_usesLastTwoLetters` (firstName "", lastName "Nguyen" → "NG"), `testBuild_ageBelowOne_dropsAgeFromDetailLine` (age 0, "Sedentary" → "Sedentary"), and `testBuild_completedPlan_reportsCompletedAndNoPlanWeek` (4-week plan started 30 days ago → `ActivePlan(name:, statusText: "Completed", isActive: false)`, `planWeek == nil`). The committed file (14 tests) is the source of truth.

- [ ] **Step 2: Run to verify it fails**

Run: `-only-testing:COILTests/ProfileSummaryBuilderTests`. Expected: build errors `cannot find 'ProfileSummaryBuilder' in scope` / `cannot find type 'ProfileSummary' in scope`. Do not stub anything.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COILTests/ProfileSummaryBuilderTests.swift
git commit -m "Add ProfileSummaryBuilder tests (red)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `ProfileSummary` + `ProfileSummaryBuilder` (green)

**Files:**
- Create: `ios/PT-Helper/COIL/Models/ProfileSummary.swift`

- [ ] **Step 1: Write the model** (full file). `HomeProgramLogic.preferredPlan(from:)` lives in `Views/HomeTab.swift` (same module) and is reused as the spec requires. `MyPlanTab` has a *private* `statusText(for:)`; the builder owns its own three-case copy because a model must not reach into a view's private helper (lifting both into `RehabPlan` is a design-pass follow-up).

```swift
import Foundation

/// What the Profile masthead shows. Built once per render by `ProfileSummaryBuilder`
/// from the profile, the saved plans, the streak and the session count; the card
/// itself does no data access.
struct ProfileSummary: Equatable {

    struct ActivePlan: Equatable {
        var name: String
        /// "Week 2 of 6" / "Not started" / "Completed"
        var statusText: String
        /// True only for `.active` plans — drives the "Active" badge.
        var isActive: Bool
    }

    struct PlanWeek: Equatable {
        var current: Int
        var total: Int
    }

    struct Stats: Equatable {
        var streak: Int
        /// nil unless the chosen plan is `.active`.
        var planWeek: PlanWeek?
        var sessions: Int
    }

    /// "First Last" trimmed; "Your profile" when the profile is nil or the name is blank.
    var displayName: String
    /// First letters of first + last; first two letters of a single name; "?" when blank.
    var initials: String
    /// "34 · Moderately Active" — age omitted below 1, activity omitted when empty, nil when both are.
    var detailLine: String?
    /// Current injuries as "Body area · description (≤ 24 chars)", then medical
    /// conditions; de-duplicated case-insensitively; at most four.
    var conditionChips: [String]
    var activePlan: ActivePlan?
    var stats: Stats
}

enum ProfileSummaryBuilder {

    static let placeholderName = "Your profile"
    static let maxChips = 4
    static let chipDescriptionLimit = 24

    static func build(profile: UserProfile?, plans: [RehabPlan],
                      streak: StreakData, sessionCount: Int) -> ProfileSummary {
        let plan = HomeProgramLogic.preferredPlan(from: plans)
        let activePlan = plan.map { chosen in
            ProfileSummary.ActivePlan(name: chosen.planName,
                                      statusText: statusText(for: chosen),
                                      isActive: isActive(chosen))
        }
        let planWeek: ProfileSummary.PlanWeek? = plan.flatMap { chosen in
            if case .active(let week) = chosen.status {
                return ProfileSummary.PlanWeek(current: week, total: chosen.totalWeeks)
            }
            return nil
        }
        return ProfileSummary(
            displayName: displayName(for: profile),
            initials: initials(for: profile),
            detailLine: detailLine(for: profile),
            conditionChips: conditionChips(for: profile),
            activePlan: activePlan,
            stats: ProfileSummary.Stats(streak: streak.currentStreak,
                                        planWeek: planWeek,
                                        sessions: sessionCount)
        )
    }

    // MARK: - Pieces (internal so tests can target one rule at a time if needed)

    static func displayName(for profile: UserProfile?) -> String {
        guard let profile else { return placeholderName }
        let full = [profile.firstName, profile.lastName]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? placeholderName : full
    }

    static func initials(for profile: UserProfile?) -> String {
        guard let profile else { return "?" }
        let first = profile.firstName.trimmingCharacters(in: .whitespaces)
        let last = profile.lastName.trimmingCharacters(in: .whitespaces)
        switch (first.isEmpty, last.isEmpty) {
        case (false, false): return (String(first.prefix(1)) + String(last.prefix(1))).uppercased()
        case (false, true):  return String(first.prefix(2)).uppercased()
        case (true, false):  return String(last.prefix(2)).uppercased()
        case (true, true):   return "?"
        }
    }

    static func detailLine(for profile: UserProfile?) -> String? {
        guard let profile else { return nil }
        var parts: [String] = []
        if profile.age >= 1 { parts.append("\(profile.age)") }
        let activity = profile.activityLevel.trimmingCharacters(in: .whitespaces)
        if !activity.isEmpty { parts.append(activity) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func conditionChips(for profile: UserProfile?) -> [String] {
        guard let profile else { return [] }
        var chips: [String] = []
        for injury in profile.injuries where injury.isCurrent {
            let area = injury.bodyArea.trimmingCharacters(in: .whitespaces)
            let description = String(
                injury.description.trimmingCharacters(in: .whitespaces).prefix(chipDescriptionLimit))
            let chip = [area, description].filter { !$0.isEmpty }.joined(separator: " · ")
            if !chip.isEmpty { chips.append(chip) }
        }
        chips.append(contentsOf: profile.medicalConditions
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })
        var seen = Set<String>()
        let unique = chips.filter { seen.insert($0.lowercased()).inserted }
        return Array(unique.prefix(maxChips))
    }

    static func statusText(for plan: RehabPlan) -> String {
        switch plan.status {
        case .notStarted:        return "Not started"
        case .completed:         return "Completed"
        case .active(let week):  return "Week \(week) of \(plan.totalWeeks)"
        }
    }

    private static func isActive(_ plan: RehabPlan) -> Bool {
        if case .active = plan.status { return true }
        return false
    }
}
```

- [ ] **Step 2: Run the tests** → `-only-testing:COILTests/ProfileSummaryBuilderTests` → 14 `passed`, `** TEST SUCCEEDED **`. Also run `-only-testing:COILTests/HomeProgramLogicTests` (13 passed) since `preferredPlan` now has a second consumer.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COIL/Models/ProfileSummary.swift
git commit -m "Add ProfileSummary and its pure builder for the Profile masthead

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `ProfileHeroCard`

**Files:**
- Create: `ios/PT-Helper/COIL/Views/Components/ProfileHeroCard.swift`

- [ ] **Step 1: Write the component** (full file). Pure presentation; identifiers sit on leaf elements, never on the card.

```swift
import SwiftUI

/// The Profile masthead: avatar, name, condition chips, three stats and the chosen
/// plan on the fixed-dark ink. It sits directly under the nav bar so the ink is
/// continuous (the same construction as Home's `WeekCompletionStrip`). Everything
/// comes in through `summary`; the card does no data access.
struct ProfileHeroCard: View {
    let summary: ProfileSummary
    var onEditHealthInfo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            identityRow

            if !summary.conditionChips.isEmpty {
                chips
            }

            statsRow

            if let plan = summary.activePlan {
                planRow(plan)
            }

            Button("Edit Health Info", action: onEditHealthInfo)
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("settings.editProfileButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xxl)
        .background(AppColors.darkSurface)
    }

    // MARK: - Rows

    private var identityRow: some View {
        HStack(spacing: AppSpacing.lg) {
            Text(summary.initials)
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.ctaText)
                .frame(width: 56, height: 56)
                .background(Circle().fill(AppColors.primaryGradient))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(summary.displayName)
                    .font(AppFonts.heroTitle)
                    .foregroundColor(AppColors.textOnDark)
                    .accessibilityIdentifier("profile.name")
                if let detail = summary.detailLine {
                    Text(detail)
                        .font(AppFonts.small)
                        .foregroundColor(AppColors.textOnDarkMuted)
                        .accessibilityIdentifier("profile.detailLine")
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        FlowLayout(spacing: AppSpacing.sm) {
            ForEach(summary.conditionChips, id: \.self) { chip in
                Text(chip)
                    .font(AppFonts.smallMedium)
                    .foregroundColor(AppColors.textOnDark)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.tight)
                    .background(AppColors.onDarkChip)
                    .cornerRadius(AppCorners.small)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppCorners.small)
                            .stroke(AppColors.onDarkChipBorder, lineWidth: 1)
                    )
            }
        }
        // Informational: one spoken element rather than four fragments.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conditions: " + summary.conditionChips.joined(separator: ", "))
    }

    private var statsRow: some View {
        HStack(spacing: AppSpacing.md) {
            statColumn(value: "\(summary.stats.streak)", suffix: nil, label: "Day streak",
                       spoken: "\(summary.stats.streak) day streak",
                       identifier: "profile.streakStat")

            if let week = summary.stats.planWeek {
                statColumn(value: "\(week.current)", suffix: " / \(week.total)", label: "Plan week",
                           spoken: "Plan week \(week.current) of \(week.total)",
                           identifier: "profile.planWeekStat")
            } else {
                statColumn(value: "—", suffix: nil, label: "Plan week",
                           spoken: "No active plan week",
                           identifier: "profile.planWeekStat")
            }

            statColumn(value: "\(summary.stats.sessions)", suffix: nil, label: "Sessions",
                       spoken: summary.stats.sessions == 1 ? "1 session" : "\(summary.stats.sessions) sessions",
                       identifier: "profile.sessionsStat")
        }
    }

    private func statColumn(value: String, suffix: String?, label: String,
                            spoken: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(value)
                    .font(AppFonts.statNumber)
                    .foregroundColor(AppColors.accent)
                if let suffix {
                    Text(suffix)
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.textOnDarkMuted)
                }
            }
            Text(label)
                .font(AppFonts.micro)
                .textCase(.uppercase)
                .kerning(1)
                .foregroundColor(AppColors.textOnDarkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier(identifier)
    }

    private func planRow(_ plan: ProfileSummary.ActivePlan) -> some View {
        HStack(spacing: AppSpacing.sm) {
            if plan.isActive {
                CoilBadge(text: "Active")
            }
            VStack(alignment: .leading, spacing: AppSpacing.nano) {
                Text(plan.name)
                    .font(AppFonts.smallSemiBold)
                    .foregroundColor(AppColors.textOnDark)
                Text(plan.statusText)
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.textOnDarkMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.planRow")
    }
}

#if DEBUG
struct ProfileHeroCard_Previews: PreviewProvider {
    static var previews: some View {
        ProfileHeroCard(
            summary: ProfileSummary(
                displayName: "Test User",
                initials: "TU",
                detailLine: "34 · Moderately Active",
                conditionChips: ["Right Knee · Patellar tendinopathy", "Asthma"],
                activePlan: .init(name: "Knee Rehab Plan", statusText: "Week 2 of 6", isActive: true),
                stats: .init(streak: 3, planWeek: .init(current: 2, total: 6), sessions: 12)
            ),
            onEditHealthInfo: {}
        )
        .previewLayout(.sizeThatFits)
    }
}
#endif
```

> **Added at Task 3 code review (2026-09-16):** `statColumn` gained `isPlaceholder: Bool = false` (last parameter) so the "—" plan-week placeholder renders in `textOnDarkMuted`, not the accent used for live values; `identityRow` is `HStack(alignment: .top, …)` so a wrapped name keeps the avatar at the top; the name carries `.accessibilityAddTraits(.isHeader)`; the preview shows a second, empty-state card. The committed file is the source of truth.

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`. (`FlowLayout`, `CoilBadge`, `SecondaryButtonStyle`, `AppColors.onDarkChip/onDarkChipBorder/textOnDarkMuted/darkSurface/primaryGradient` all exist in `DesignSystem.swift`; grep them if the build says otherwise.)

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COIL/Views/Components/ProfileHeroCard.swift
git commit -m "Add the ProfileHeroCard masthead component

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `ProfileTab.swift` (new) and the `MainTabView` cleanup

**Files:**
- Create: `ios/PT-Helper/COIL/Views/ProfileTab.swift`
- Modify: `ios/PT-Helper/COIL/Views/MainTabView.swift:201-218` (delete the inline `ProfileTab`)

The new tab still calls today's `SettingsView(userName:onEditProfile:)` so the build stays green; Task 5 changes that signature and updates this call.

- [ ] **Step 1: Write the tab** (full file):

```swift
import SwiftUI

/// Tab 3: Profile — "Who am I here and how am I doing?" A dark masthead built from
/// `ProfileSummary`, then the grouped settings body. Owns the Edit Health Info sheet.
struct ProfileTab: View {
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @ObservedObject private var profileService = UserProfileService.shared
    @ObservedObject private var streakService = StreakService.shared
    @State private var showEditProfile = false

    private var summary: ProfileSummary {
        ProfileSummaryBuilder.build(profile: profileService.profile,
                                    plans: savedPlansVM.rehabPlans,
                                    streak: streakService.streakData,
                                    sessionCount: workoutViewModel.sessions.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        ProfileHeroCard(summary: summary) { showEditProfile = true }
                            .modifier(RevealOnAppear(index: 0))

                        SettingsView(
                            userName: profileService.profile?.firstName ?? "User",
                            onEditProfile: { showEditProfile = true }
                        )
                        .padding(.top, AppSpacing.lg)
                    }
                    .floatingTabBarClearance()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .coilNavBar()
        }
        .sheet(isPresented: $showEditProfile) {
            OnboardingEditView()
        }
        .trackScreen("ProfileTab")
    }
}

// MARK: - Reveal

/// One fade-and-rise per section on first appearance, staggered by `index`.
/// Under Reduce Motion the offset is dropped and only the opacity animates.
struct RevealOnAppear: ViewModifier {
    let index: Int
    static let staggerSeconds: Double = 0.05

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : AppSpacing.md)
            .animation(AppAnimations.springy.delay(Double(index) * Self.staggerSeconds), value: appeared)
            .onAppear { appeared = true }
    }
}

#if DEBUG
struct ProfileTab_Previews: PreviewProvider {
    static var previews: some View {
        ProfileTab()
            .environmentObject(SavedPlansViewModel())
            .environmentObject(WorkoutViewModel())
    }
}
#endif
```

- [ ] **Step 2: Delete the inline tab from `MainTabView.swift`.** Lines 201–218 currently read:
```swift
// MARK: - Profile Tab

struct ProfileTab: View {
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            SettingsView(
                userName: UserProfileService.shared.profile?.firstName ?? "User",
                onEditProfile: { showEditProfile = true }
            )
        }
        .sheet(isPresented: $showEditProfile) {
            // Real editor (matches the ProgressTab path) — was a placeholder stub.
            OnboardingEditView()
        }
    }
}
```
Delete them entirely (keep the following `// MARK: - Tab Bar` section). Nothing else in the file changes in this task.

- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`. Then a quick simulator look is optional; the real check is Task 7.

- [ ] **Step 4: Commit**
```bash
git add ios/PT-Helper/COIL/Views/ProfileTab.swift ios/PT-Helper/COIL/Views/MainTabView.swift
git commit -m "Give the Profile tab its own file with the ProfileHeroCard masthead

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `SettingsView` becomes the grouped-settings body; Progress loses its gear

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/SettingsView.swift` (whole structure; anchors below)
- Modify: `ios/PT-Helper/COIL/Views/ProfileTab.swift` (the `SettingsView(...)` call)
- Modify: `ios/PT-Helper/COIL/Views/ProgressTab.swift:6-44` and `:170-188`

Blast radius (R1, verified at `d78ceae`): `SettingsView(` is constructed in `ProfileTab.swift` (Task 4) and `ProgressTab.swift:27`; `showsDoneButton` only in `ProgressTab.swift:35`; `progress.settingsButton` only in `ProgressTab.swift:184` and `SettingsUITests.swift:11` (Task 6); `SettingsView.AccountDeletionOutcome` in `COILTests/AccountDeletionOutcomeTests.swift` (kept nested, untouched).

- [ ] **Step 1: Trim the stored properties** (`SettingsView.swift:6-11`). Replace
```swift
struct SettingsView: View {
    let userName: String
    var onEditProfile: () -> Void
    /// True only when a sheet hosts this view; the tab host has nothing to dismiss.
    var showsDoneButton: Bool = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
```
with
```swift
/// The grouped settings body shown under the Profile masthead (Preferences ·
/// Help & Legal · Account, then the DEBUG card and the version footer). It owns
/// every confirmation dialog, the account-deletion flow and the legal sheets;
/// `ProfileTab` owns the scroll view, the nav bar and the Edit Health Info sheet.
struct SettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
```
(the remaining `@StateObject`/`@State`/`@AppStorage` lines stay as they are).

- [ ] **Step 2: Replace `body` down to (not including) `.confirmationDialog("Sign Out"`** (`:33-83`). The old block starts `var body: some View { ZStack { AppColors.bgGradient …` and ends with the `.toolbar { if showsDoneButton … }` modifier. New:
```swift
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            settingsGroup(title: "Preferences", index: 1) {
                appearanceCard
                notificationsCard
            }

            settingsGroup(title: "Help & Legal", index: 2) {
                helpSupportCard
                legalCard
            }

            settingsGroup(title: "Account", index: 3) {
                accountCard
            }

            #if DEBUG
            debugCard
                .modifier(RevealOnAppear(index: 4))
            #endif

            Text(appVersionText)
                .font(AppFonts.micro)
                .foregroundColor(AppColors.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.sm)
                .accessibilityIdentifier("settings.versionFooter")
        }
        .padding(.horizontal, AppSpacing.xl)
```
The chain continues directly with the existing `.confirmationDialog("Sign Out", …)` and everything after it, unchanged, EXCEPT: delete the line `.trackScreen("Settings")` (`:164`; the tab tracks `ProfileTab`).

- [ ] **Step 3: Remove the dismiss from account deletion.** In `deleteAccount()` (`:217-221`) replace
```swift
                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleted)
                    isDeletingAccount = false
                    dismiss()
                }
```
with
```swift
                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleted)
                    isDeletingAccount = false
                    // Nothing to dismiss: the tab hosts this body, and the sign-out
                    // above already routes RootView back to the auth screen.
                }
```

- [ ] **Step 4: Delete `initials` (`:283-289`) and `profileCard` (`:317-344`)**, including their doc comments. Both moved into `ProfileSummaryBuilder`/`ProfileHeroCard`.

- [ ] **Step 5: Add the group/card helpers** right after `appVersionText` (`:311-315`), before the first card:
```swift
    // MARK: - Layout helpers

    /// A titled group: teal divider header above one or more cards.
    private func settingsGroup<Content: View>(title: String, index: Int,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CoilDividerHeader(title: title)
            content()
        }
        .modifier(RevealOnAppear(index: index))
    }

    /// The card chrome every group card shares. Rows carry their own padding, so
    /// the card itself has none (`.cardStyle()` would add `AppSpacing.lg`).
    private func groupCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Inset so the rule starts under the row text, past the 32pt icon tile.
    private var rowDivider: some View {
        Divider().padding(.leading, AppSpacing.huge + AppSpacing.xl)
    }

    private func rowIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(AppFonts.iconS)
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.12))
            .cornerRadius(AppCorners.small)
    }
```

- [ ] **Step 6: Rewrite the cards.** Replace `appearanceCard` (`:346-384`) with:
```swift
    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var appearanceCard: some View {
        groupCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.md) {
                    rowIcon("circle.lefthalf.filled", color: AppColors.accent)
                    Text("Appearance")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }

                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearancePicker")
                .onChange(of: appearanceRaw) { _, newValue in
                    AnalyticsService.shared.log(.settingChanged,
                        parameters: ["key": "appearance", "value": newValue])
                }
            }
            .padding(AppSpacing.lg)
        }
    }
```
Replace `debugFeedbackCard` (`:386-427`) with (note the `#if DEBUG` around the whole property, and "Export Debug Log" is NOT here any more — it moves to the help card below):
```swift
    #if DEBUG
    /// Developer tooling; release builds never show it (deviation 5 keeps
    /// "Export Debug Log" available to testers in the Help card instead).
    @ViewBuilder
    private var debugCard: some View {
        groupCard {
            HStack(spacing: AppSpacing.md) {
                rowIcon("doc.text.magnifyingglass", color: AppColors.accentLight)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text("Session Events")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Text("\(SessionLogger.shared.eventCount) events this session")
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)

            rowDivider

            NavigationLink(destination: MissingImagesDebugView()) {
                HStack(spacing: AppSpacing.md) {
                    rowIcon("photo.badge.exclamationmark", color: AppColors.warning)
                    Text("Image Diagnostics")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFonts.iconXS)
                        .foregroundColor(AppColors.mutedText)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
            .accessibilityIdentifier("settings.imageDiagnosticsButton")
        }
    }
    #endif
```
Replace `helpSupportCard` (`:429-466`) with:
```swift
    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var helpSupportCard: some View {
        groupCard {
            settingsRow(icon: "envelope", color: AppColors.accent, title: "Contact Support") {
                contactSupport()
            }
            .accessibilityIdentifier("settings.contactSupportButton")

            rowDivider

            settingsRow(icon: "flag", color: AppColors.warning, title: "Report a Concern") {
                showReportConcern = true
            }
            .accessibilityIdentifier("settings.reportConcernButton")

            rowDivider

            settingsRow(icon: "ladybug", color: AppColors.accent, title: "Export Debug Log") {
                if let url = SessionLogger.shared.exportAsShareableFile() {
                    shareURL = url
                    showShareSheet = true
                }
            }
            .accessibilityIdentifier("settings.exportDebugLogButton")

            rowDivider

            settingsRow(icon: "shield.checkered", color: AppColors.accent, title: "Safety Resources") {
                showSafetyResources = true
            }
            .accessibilityIdentifier("settings.safetyResourcesButton")

            rowDivider

            settingsRow(icon: "star", color: AppColors.accent, title: "Rate COIL") {
                requestAppReview()
            }
            .accessibilityIdentifier("settings.rateAppButton")
        }
    }
```
Replace `actionsCard` (`:468-520`) AND `dangerZoneCard` (`:522-538`) together with one card:
```swift
    /// Sign Out and Delete Account, formerly the "actions" and "danger zone" cards.
    /// "Update Health Info" now lives in the masthead.
    @ViewBuilder
    private var accountCard: some View {
        groupCard {
            settingsRow(icon: "rectangle.portrait.and.arrow.right", color: AppColors.danger,
                        title: "Sign Out", isDestructive: true) {
                showSignOutConfirmation = true
            }
            .accessibilityIdentifier("settings.signOutButton")

            rowDivider

            settingsRow(icon: "trash", color: AppColors.danger, title: "Delete Account") {
                showDeleteConfirmation = true
            }
            .accessibilityIdentifier("settings.deleteAccountButton")
        }
    }
```
(Only Sign Out gets the danger title, as the spec says; Delete Account keeps its red icon and primary title, exactly as today.)

Replace `notificationsCard` (`:540-705`) with — every toggle, picker, label, identifier and `onChange` handler is byte-identical to today; only the card chrome, icons, dividers and title colours change:
```swift
    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var notificationsCard: some View {
        groupCard {
            HStack(spacing: AppSpacing.md) {
                rowIcon("bell.badge", color: AppColors.warning)

                Text("Reminders")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.primaryText)

                Spacer()

                Toggle("", isOn: $notificationService.isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Reminders")
                    .accessibilityIdentifier("settings.reminderToggle")
                    .onChange(of: notificationService.isEnabled) { _, enabled in
                        AnalyticsService.shared.log(.settingChanged,
                            parameters: ["key": "reminders_enabled",
                                         "value": enabled ? "true" : "false"])
                        if enabled {
                            Task {
                                if !notificationService.isAuthorized {
                                    _ = await notificationService.requestPermission()
                                }
                                await notificationService.resyncReminders()
                            }
                        } else {
                            notificationService.cancelAllReminders()
                        }
                    }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)

            if notificationService.isEnabled {
                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("clock", color: AppColors.accent)

                    Text("Reminder Time")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)

                    Spacer()

                    DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Reminder time")
                        .onChange(of: reminderDate) { _, newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notificationService.updateReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
                            let timeString = String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "reminder_time", "value": timeString])
                        }
                        .onAppear {
                            // Seed the picker from the SAVED time so a glance or an
                            // accidental tap can't silently overwrite it (audit #81).
                            var comps = DateComponents()
                            comps.hour = notificationService.reminderHour
                            comps.minute = notificationService.reminderMinute
                            if let seeded = Calendar.current.date(from: comps) {
                                reminderDate = seeded
                            }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("dumbbell", color: AppColors.success)
                    Text("Workout Reminders")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Toggle("", isOn: $notificationService.workoutRemindersEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Workout reminders")
                        .onChange(of: notificationService.workoutRemindersEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "workout_reminders",
                                             "value": enabled ? "true" : "false"])
                            Task { await notificationService.resyncReminders() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("arrow.triangle.2.circlepath", color: AppColors.accent)
                    Text("Re-Assessment Prompts")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Toggle("", isOn: $notificationService.reassessmentRemindersEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Re-assessment prompts")
                        .onChange(of: notificationService.reassessmentRemindersEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "reassessment_reminders",
                                             "value": enabled ? "true" : "false"])
                            Task { await notificationService.resyncReminders() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("bell.badge.waveform", color: AppColors.warning)
                    Text("Inactivity Nudges")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Toggle("", isOn: $notificationService.inactivityNudgesEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Inactivity nudges")
                        .onChange(of: notificationService.inactivityNudgesEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "inactivity_nudges",
                                             "value": enabled ? "true" : "false"])
                            if !enabled { notificationService.cancelInactivityNudge() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
        }
    }
```
Replace `legalCard` (`:707-747`) with:
```swift
    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var legalCard: some View {
        groupCard {
            settingsRow(icon: "hand.raised", color: AppColors.accent, title: "Privacy Policy") {
                showPrivacyPolicy = true
            }
            .accessibilityIdentifier("settings.privacyPolicyButton")

            rowDivider

            settingsRow(icon: "doc.text", color: AppColors.accent, title: "Terms of Service") {
                showTermsOfService = true
            }
            .accessibilityIdentifier("settings.termsOfServiceButton")

            rowDivider

            settingsRow(icon: "heart.text.square", color: AppColors.accent, title: "Consumer Health Data Policy") {
                showConsumerHealthDataPolicy = true
            }
            .accessibilityIdentifier("settings.consumerHealthDataPolicyButton")

            if consentService.hasHealthDataConsent {
                rowDivider
                settingsRow(icon: "heart.slash", color: AppColors.danger, title: "Withdraw Health Data Consent") {
                    showWithdrawConsentConfirmation = true
                }
                .accessibilityIdentifier("settings.withdrawHealthConsentButton")
            }
        }
    }
```
Replace `settingsRow` (`:749-772`) with:
```swift
    private func settingsRow(icon: String, color: Color, title: String,
                             isDestructive: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                rowIcon(icon, color: color)

                Text(title)
                    .font(AppFonts.body)
                    .foregroundColor(isDestructive ? AppColors.danger : AppColors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFonts.iconXS)
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }
```

- [ ] **Step 7: Update the caller in `ProfileTab.swift`.** Replace
```swift
                        SettingsView(
                            userName: profileService.profile?.firstName ?? "User",
                            onEditProfile: { showEditProfile = true }
                        )
                        .padding(.top, AppSpacing.lg)
```
with
```swift
                        SettingsView()
                            .padding(.top, AppSpacing.lg)
```

- [ ] **Step 8: Remove the gear, sheet and cover from `ProgressTab.swift`.** Lines 6–44 become:
```swift
struct ProgressTab: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var insightsVM: RecoveryInsightsViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel

    var body: some View {
        NavigationStack {
            ProgressTabContent(
                tabSelection: tabSelection,
                workoutViewModel: workoutViewModel,
                insightsVM: insightsVM,
                savedPlansVM: savedPlansVM
            )
            .coilNavBar()
        }
        .trackScreen("ProgressTab")
    }
}
```
In `ProgressTabContent` delete `var onSettingsTapped: () -> Void` (`:55`), and in the toolbar (`:170-188`) replace the `HStack(spacing: AppSpacing.sm) { NavigationLink … Button(action: onSettingsTapped) … }` with just the streak link:
```swift
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: AchievementsView(streakService: streakService)) {
                    StreakToolbarBadge(streakService: streakService)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(streakService.streakData.currentStreak) day streak, view achievements")
                .accessibilityIdentifier("progress.streakBadge")
            }
        }
```

- [ ] **Step 9: Build and grep the leftovers**
Build → `** BUILD SUCCEEDED **`. Then:
```bash
grep -n "showsDoneButton\|onEditProfile\|progress.settingsButton\|userName\|dismiss()" ios/PT-Helper/COIL/Views/SettingsView.swift ios/PT-Helper/COIL/Views/ProgressTab.swift ios/PT-Helper/COIL/Views/ProfileTab.swift
```
Expected: no matches. Run `-only-testing:COILTests/AccountDeletionOutcomeTests` → 5 passed (the nested enum is untouched).

- [ ] **Step 10: Commit**
```bash
git add ios/PT-Helper/COIL/Views/SettingsView.swift ios/PT-Helper/COIL/Views/ProfileTab.swift ios/PT-Helper/COIL/Views/ProgressTab.swift
git commit -m "Regroup Settings under the Profile masthead and drop the Progress gear

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: UI tests for the Profile tab

**Files:**
- Modify: `ios/PT-Helper/COILUITests/SettingsUITests.swift`

- [ ] **Step 1: Replace `navigateToSettings` (`:5-21`)** with:
```swift
    /// Settings now live under the Profile tab's masthead (no sheet, no gear).
    @MainActor
    private func navigateToProfile() {
        tapTab("Profile")
        // The body is in the tree from the start; Sign Out is a reliable "loaded" signal.
        XCTAssertTrue(app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 10),
                      "Profile tab should show the settings body")
    }
```
and rename every `navigateToSettings()` call in the file to `navigateToProfile()`.

- [ ] **Step 2: Delete `testGearSheet_showsDoneAndDismisses` (`:101-110`)** — there is no sheet; `ShellNavigationUITests.testProfileTab_hasNoDoneButton` already pins the absence of Done.

- [ ] **Step 3: Add the masthead tests** at the end of the class:
```swift
    @MainActor
    func testProfileHero_showsSeededSummary() throws {
        navigateToProfile()

        let name = app.staticTexts["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5), "Masthead name should exist")
        XCTAssertEqual(name.label, "Test User")

        // Seeded: streak 3, Knee Rehab Plan started 10 days ago over 6 weeks.
        let streak = app.descendants(matching: .any)["profile.streakStat"]
        XCTAssertTrue(streak.waitForExistence(timeout: 5))
        XCTAssertEqual(streak.label, "3 day streak")

        let planWeek = app.descendants(matching: .any)["profile.planWeekStat"]
        XCTAssertTrue(planWeek.waitForExistence(timeout: 5))
        XCTAssertEqual(planWeek.label, "Plan week 2 of 6")

        XCTAssertTrue(app.descendants(matching: .any)["profile.planRow"].exists,
                      "The active plan row should be shown")
        XCTAssertTrue(app.buttons["settings.editProfileButton"].exists,
                      "Edit Health Info lives in the masthead now")

        captureScreenshot(name: "Profile-Masthead")
    }

    @MainActor
    func testEditHealthInfo_opensTheEditor() throws {
        navigateToProfile()
        let edit = app.buttons["settings.editProfileButton"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(staticText("Update Profile").waitForExistence(timeout: 5),
                      "Edit Health Info should present the profile editor")
    }
```

- [ ] **Step 4: Run the UI classes** (FullPlan command) with `-only-testing:COILUITests/SettingsUITests -only-testing:COILUITests/ShellNavigationUITests`. Expected: 6 + 7 `passed`, `** TEST SUCCEEDED **`. A single "Lost connection to the application" that passes on retry is the known simulator flake.

- [ ] **Step 5: Commit**
```bash
git add ios/PT-Helper/COILUITests/SettingsUITests.swift
git commit -m "Test Settings through the Profile tab and the seeded masthead

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: IA-1 verification and PR

- [ ] **Step 1: Token audit**
```bash
grep -n "\.font(\.system(size\|Color\.white\.opacity\|Color(CoilPalette\|cornerRadius: [0-9]" \
  ios/PT-Helper/COIL/Views/ProfileTab.swift ios/PT-Helper/COIL/Views/SettingsView.swift \
  ios/PT-Helper/COIL/Views/Components/ProfileHeroCard.swift ios/PT-Helper/COIL/Models/ProfileSummary.swift
```
Expected: no matches.

- [ ] **Step 2: Full UnitPlan** (detached, poll the log) → `Executed 1364 tests, with 1 test skipped and 0 failures`, `** TEST SUCCEEDED **` (baseline 1350 + the 14 builder tests).

- [ ] **Step 3: Screenshots.** The test action leaves `/tmp/coil-dd-ia/Build/Products/Debug-iphonesimulator/COIL.app`. Install and launch with launch args via simctl (the MCP launcher drops them):
```bash
xcrun simctl install A1579757-01DC-4BE8-A068-249FD8467C44 /tmp/coil-dd-ia/Build/Products/Debug-iphonesimulator/COIL.app
xcrun simctl launch A1579757-01DC-4BE8-A068-249FD8467C44 com.noyfisher.pthelper --uitesting --skip-onboarding --seed-mock-data
```
Navigate with the iOS Simulator MCP `control` tap/swipe, capture with `xcrun simctl io <udid> screenshot <file>.png` into the session scratchpad `ia-qa/`: Profile top (masthead: "Test User", chips absent for the seeded profile, 3 · 2 / 6 · 3, Active Knee Rehab Plan "Week 2 of 6", Edit Health Info), Profile scrolled (three groups, Account card with Sign Out/Delete, version footer), Progress top (no gear; streak badge only). Compare with the mockup canvas. Anything other than the specified layout is a regression.

- [ ] **Step 4: Push and open the PR**
```bash
git push -u origin ux/profile-progress-ia
gh pr create --base ux/ia-base --head ux/profile-progress-ia \
  --title "IA-1: Profile tab masthead and grouped settings" --body "$(cat <<'EOF'
Implements PR IA-1 of docs/superpowers/specs/2026-09-14-profile-progress-ia-design.md. Stacked on `ux/ia-base` (design-specs + Foundation F2 + Tokens); rebase onto main once #75–#77 merge.

- New `ProfileSummary` + pure `ProfileSummaryBuilder` (10 unit tests) and `ProfileHeroCard` masthead (ink, initials, chips, streak / plan week / sessions, active plan, Edit Health Info)
- `ProfileTab.swift` owns the tab: masthead → Preferences · Help & Legal · Account groups → DEBUG card → version footer; one staggered reveal, Reduce Motion respected
- `SettingsView` is the grouped body only: no profile card, no Done, no `dismiss`, cards unified on `AppCorners.card`, icons on `AppFonts.iconS/XS`
- Progress tab loses the gear, the Settings sheet and the edit cover (single entry point)
- UI tests navigate via the Profile tab; new masthead + editor tests

Verification: UnitPlan 1360/0; SettingsUITests + ShellNavigationUITests green under FullPlan; screenshots of Profile (top, scrolled) and Progress attached in the session.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## PR IA-2 — Progress tab

### Task 8: `OutcomePromptView` banner style

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/Components/OutcomePromptView.swift` (whole file)

- [ ] **Step 0: Branch for IA-2** (from the IA-1 head, same worktree):
```bash
git switch -c ux/ia-2-progress
```

- [ ] **Step 1: Rewrite the file** (full file; the card body is the existing one with its options list extracted into `ratingContent` so both styles share it):

```swift
import SwiftUI

// MARK: - Tier 3 PR D: Outcome Prompt

/// Asks the user how accurate the AI analysis turned out to be. Shows after a plan
/// has been active for ≥ 7 days. One-tap submission via `OutcomeRecorder.shared.record(...)`.
///
/// Two presentations: `.card` (the original inline card, options always visible)
/// and `.banner` (a one-line row that expands in place when tapped — the Progress
/// tab uses this so the prompt stops competing with the content around it).
struct OutcomePromptView: View {
    enum Style { case card, banner }

    let analysisId: UUID
    let planId: UUID?
    let planAgeDays: Int?
    var style: Style = .card

    /// Called after a rating is submitted (or the user dismisses) so the
    /// containing view can re-evaluate `shouldShowPrompt` and hide.
    let onComplete: () -> Void

    @State private var isSubmitting = false
    @State private var submittedFeedback: OutcomeFeedback?
    @State private var isExpanded = false

    var body: some View {
        switch style {
        case .card: cardBody
        case .banner: bannerBody
        }
    }

    // MARK: - Card (unchanged look)

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "sparkles")
                    .foregroundColor(AppColors.accent)
                Text("How's it going?")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
                Spacer()
                dismissButton
            }

            Text("Thinking back to the original analysis — how accurate did it turn out to be?")
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            ratingContent
        }
        .padding(AppSpacing.lg)
        .background(AppColors.elevatedSurface.opacity(0.6))
        .cornerRadius(AppCorners.card)
    }

    // MARK: - Banner (collapsed row, expands in place)

    private var bannerBody: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Button {
                    withAnimation(AppAnimations.smooth) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "sparkles")
                            .font(AppFonts.iconS)
                            .foregroundColor(AppColors.accent)
                        Text("How accurate was your analysis?")
                            .font(AppFonts.small)
                            .foregroundColor(AppColors.primaryText)
                        Spacer(minLength: 0)
                        if !isExpanded && submittedFeedback == nil {
                            Text("Rate")
                                .font(AppFonts.captionSemiBold)
                                .textCase(.uppercase)
                                .foregroundColor(AppColors.accentText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("outcomePrompt.expand")
                .accessibilityLabel("How accurate was your analysis?")
                .accessibilityHint(isExpanded ? "Collapses the rating options" : "Expands the rating options")

                dismissButton
            }

            if isExpanded {
                ratingContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background(AppColors.elevatedSurface.opacity(0.6))
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.subtleBorder, lineWidth: 1)
        )
    }

    // MARK: - Shared pieces

    private var dismissButton: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(AppFonts.iconXS)
                .foregroundColor(AppColors.mutedText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("outcomePrompt.dismiss")
        .accessibilityLabel("Dismiss")
    }

    /// The four rating options, or the confirmation line once one is chosen.
    @ViewBuilder
    private var ratingContent: some View {
        if let chosen = submittedFeedback {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: chosen.icon)
                    .foregroundColor(AppColors.success)
                Text("Thanks — recorded as \(chosen.displayName.lowercased()).")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.top, AppSpacing.xs)
        } else {
            VStack(spacing: AppSpacing.sm) {
                ForEach(OutcomeFeedback.allCases) { feedback in
                    Button(action: { submit(feedback) }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: feedback.icon)
                                .frame(width: 18)
                            Text(feedback.displayName)
                                .font(AppFonts.small)
                            Spacer()
                        }
                        .padding(.vertical, AppSpacing.sm)
                        .padding(.horizontal, AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.medium)
                                .stroke(AppColors.subtleBorder, lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("outcomePrompt.\(feedback.rawValue)")
                }
            }
        }
    }

    // MARK: - Actions

    private func submit(_ feedback: OutcomeFeedback) {
        guard !isSubmitting else { return }
        isSubmitting = true
        OutcomeRecorder.shared.record(
            feedback,
            for: analysisId,
            planId: planId,
            planAgeDays: planAgeDays
        )
        withAnimation(AppAnimations.smooth) {
            submittedFeedback = feedback
        }
        // Auto-dismiss after a short confirmation pause so the parent view
        // can hide the prompt on the next render cycle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onComplete()
        }
    }

    private func dismiss() {
        // Mark "asked" by recording .notApplicable so the prompt doesn't
        // re-fire next time. Users who didn't engage = silent signal.
        OutcomeRecorder.shared.record(
            .notApplicable,
            for: analysisId,
            planId: planId,
            planAgeDays: planAgeDays
        )
        onComplete()
    }
}

#if DEBUG
struct OutcomePromptView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: AppSpacing.lg) {
            OutcomePromptView(analysisId: UUID(), planId: UUID(), planAgeDays: 12, onComplete: {})
            OutcomePromptView(analysisId: UUID(), planId: UUID(), planAgeDays: 12, style: .banner, onComplete: {})
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif
```
The only behavioural change for `.card` callers is the dismiss glyph moving from `.font(.caption)` to `AppFonts.iconXS` (12pt semibold) with a 44pt hit area. Existing call sites pass no `style`, so they keep `.card`.

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`. `grep -rn "OutcomePromptView(" ios/PT-Helper/COIL` must show only `ProgressTab.swift` and the preview.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COIL/Views/Components/OutcomePromptView.swift
git commit -m "Add a collapsible banner style to OutcomePromptView

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Progress tab order, `ActionTile` row and token sweep

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/ProgressTab.swift` (anchors below are post-Task-5 line numbers; grep the quoted code)

- [ ] **Step 1: Replace the scroll content.** The `ScrollView { VStack(spacing: AppSpacing.lg) { … } .padding(…) .floatingTabBarClearance() }` block inside `ProgressTabContent.body` becomes:
```swift
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                lastAnalysisSection

                if let loadError = workoutViewModel.loadError {
                    // A fetch failure must not masquerade as "No Data Yet" — that's
                    // the brand-new-user message and makes a longtime user fear their
                    // data vanished (audit #62).
                    Spacer(minLength: AppSpacing.xxxl)
                    ErrorStateView(
                        title: "Couldn't load your progress",
                        message: loadError,
                        onRetry: { workoutViewModel.fetchSessions() }
                    )
                    Spacer(minLength: AppSpacing.xxxl)
                    actionsRow
                } else if workoutViewModel.sessions.isEmpty {
                    Spacer(minLength: AppSpacing.xxxl)
                    EmptyStateView(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "No Data Yet",
                        subtitle: "Complete workout sessions to see your progress over time",
                        actionTitle: "Start an Assessment",
                        action: { tabSelection.assessmentRequest = .gateway }
                    )
                    Spacer(minLength: AppSpacing.xxxl)
                    actionsRow
                } else {
                    let chartData = filteredChartData

                    // Region filter picker
                    regionFilterPicker

                    // Pain trend chart
                    painTrendChart(chartData)

                    // Summary stats + streak
                    summaryStats

                    // Log Workout · Recovery Notes
                    actionsRow

                    // AI Recovery Insights
                    RecoveryInsightsCardView(vm: insightsVM)

                    // Tier 3 PR D: outcome rating prompt — surfaces ≥7 days
                    // after a plan starts, asks the user how accurate the
                    // original AI analysis turned out to be. Hidden when
                    // either no eligible plan exists or the rating's
                    // already in. Re-renders on outcomePromptRefreshTick.
                    if let target = outcomePromptTarget {
                        OutcomePromptView(
                            analysisId: target.analysisId,
                            planId: target.plan.id,
                            planAgeDays: OutcomeRecorder.planAgeDays(planStartDate: target.plan.startDate),
                            style: .banner
                        ) {
                            outcomePromptRefreshTick &+= 1
                        }
                        .id(outcomePromptRefreshTick)
                    }

                    // Recent Workouts
                    recentWorkoutsSection
                }

                // Re-assessment prompt
                reassessmentCard
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
            .floatingTabBarClearance()
        }
```
(The two `NavigationLink { navLinkRow(...) }` blocks that followed the `if/else` are gone.)

- [ ] **Step 2: Replace `navLinkRow`** (the `// MARK: - Navigation Link Row` function) with the actions row:
```swift
    // MARK: - Actions Row

    private var actionsRow: some View {
        HStack(spacing: AppSpacing.md) {
            NavigationLink(destination: WorkoutSessionView()) {
                ActionTile(icon: "figure.strengthtraining.traditional",
                           title: "Log Workout", subtitle: "Add a session")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.logWorkoutTile")

            NavigationLink(destination: NotesView()) {
                ActionTile(icon: "note.text",
                           title: "Recovery Notes", subtitle: "Your observations")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.notesTile")
        }
    }
```
and add, at file scope just above `// MARK: - Streak Toolbar Badge`:
```swift
// MARK: - Action Tile

/// Icon tile + title + fixed subtitle, the two-up "what can I do here" row under the stats.
private struct ActionTile: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppFonts.iconM)
                .foregroundColor(AppColors.accent)
                .frame(width: 40, height: 40)
                .background(AppColors.accentTint)
                .cornerRadius(AppCorners.small)

            Text(title)
                .font(AppFonts.bodySemiBold)
                .foregroundColor(AppColors.primaryText)

            Text(subtitle)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 3: Token and copy sweep** — exact line edits (grep each "before"):

| Where | Before | After |
|---|---|---|
| `lastAnalysisCard` stethoscope | `.font(.system(size: 18, weight: .semibold))` | `.font(AppFonts.iconM)` |
| `lastAnalysisCard` text stack | `VStack(alignment: .leading, spacing: 3)` | `VStack(alignment: .leading, spacing: AppSpacing.xs)` |
| `lastAnalysisCard` chevron | `.font(.system(size: 13, weight: .semibold))` | `.font(AppFonts.iconS)` |
| `workoutSessionRow` date | `Text(session.date, style: .date)` | `Text(session.date.formatted(date: .abbreviated, time: .omitted))` |
| `workoutSessionRow` trash | `.font(.system(size: 12))` | `.font(AppFonts.iconXS)` |
| `summaryStats` streak card | `color: Color(CoilPalette.pop),` | `color: AppColors.streak,` |
| `summaryStats` rosette | `.foregroundColor(Color(CoilPalette.pop))` | `.foregroundColor(AppColors.streak)` |
| `summaryStats` callout background | `.background(Color(CoilPalette.pop).opacity(0.08))` | `.background(AppColors.streakTint)` |
| `statCard` icon | `.font(.system(size: 16, weight: .semibold))` | `.font(AppFonts.iconM)` |
| `reassessmentCard` icon | `.font(.system(size: 16, weight: .semibold))` | `.font(AppFonts.iconM)` |
| `reassessmentCard` arrow | `.font(.system(size: 12, weight: .semibold))` | `.font(AppFonts.iconXS)` |
| `StreakToolbarBadge` | `HStack(spacing: 3)` | `HStack(spacing: AppSpacing.xs)` |
| `StreakToolbarBadge` flame | `.font(.system(size: 14, weight: .semibold))` | `.font(AppFonts.iconS)` |

- [ ] **Step 4: Build and audit**
Build → `** BUILD SUCCEEDED **`. Then
```bash
grep -n "\.font(\.system(size\|Color\.white\.opacity\|Color(CoilPalette\|cornerRadius: [0-9]\|spacing: [0-9]\|minLength: 100\|navLinkRow" ios/PT-Helper/COIL/Views/ProgressTab.swift
```
Expected: no matches.

- [ ] **Step 5: Commit**
```bash
git add ios/PT-Helper/COIL/Views/ProgressTab.swift
git commit -m "Reorder the Progress tab around an actions row and the outcome banner

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Progress UI tests

**Files:**
- Modify: `ios/PT-Helper/COILUITests/ProgressTabUITests.swift`

- [ ] **Step 1: Add a scroll helper and two tests** (append inside the class):
```swift
    /// Scroll the Progress ScrollView until `element` is hittable (it exists in the
    /// tree from the start but may sit below the chart).
    @MainActor
    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        guard element.waitForExistence(timeout: 5) else { return false }
        var swipes = 0
        while !element.isHittable && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.isHittable
    }

    @MainActor
    func testActionTiles_navigateToLogWorkoutAndNotes() throws {
        tapTab("Progress")

        // Identifier on a NavigationLink: query `.any`, the file convention for
        // container identifiers (see `progress.streakBadge` above).
        let logTile = app.descendants(matching: .any)["progress.logWorkoutTile"].firstMatch
        XCTAssertTrue(scrollToHittable(logTile), "Log Workout tile should scroll into view")
        XCTAssertTrue(app.descendants(matching: .any)["progress.notesTile"].firstMatch.exists,
                      "Recovery Notes tile should exist")
        logTile.tap()
        let workoutBar = app.navigationBars["Workout Session"]
        XCTAssertTrue(workoutBar.waitForExistence(timeout: 5),
                      "Log Workout tile should push the workout session screen")
        workoutBar.buttons.element(boundBy: 0).tap()

        let notesTile = app.descendants(matching: .any)["progress.notesTile"].firstMatch
        XCTAssertTrue(scrollToHittable(notesTile), "Recovery Notes tile should scroll into view")
        notesTile.tap()
        XCTAssertTrue(app.navigationBars["Recovery Notes"].waitForExistence(timeout: 5),
                      "Recovery Notes tile should push the notes screen")

        captureScreenshot(name: "Progress-ActionTiles")
    }

    @MainActor
    func testOutcomeBanner_expandsToOptions() throws {
        tapTab("Progress")
        // The seeded Knee plan started 10 days ago, so the prompt is eligible unless
        // this simulator already recorded a rating (persisted UserDefaults state).
        let expand = app.buttons["outcomePrompt.expand"]
        guard scrollToHittable(expand) else {
            throw XCTSkip("Outcome prompt already answered in this simulator's persisted state")
        }
        XCTAssertFalse(app.buttons["outcomePrompt.accurate"].exists,
                       "Rating options stay collapsed until the row is tapped")
        expand.tap()
        XCTAssertTrue(app.buttons["outcomePrompt.accurate"].waitForExistence(timeout: 3),
                      "Tapping the banner row should reveal the rating options")

        captureScreenshot(name: "Progress-OutcomeBannerExpanded")
    }
```

- [ ] **Step 2: Run** the FullPlan command with `-only-testing:COILUITests/ProgressTabUITests`. Expected: 3 `passed` (or 2 passed + 1 skipped), `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COILUITests/ProgressTabUITests.swift
git commit -m "Cover the Progress action tiles and the outcome banner in UI tests

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: IA-2 verification and PR

- [ ] **Step 1: Full UnitPlan** → `Executed 1364 tests … 0 failures`, `** TEST SUCCEEDED **`.
- [ ] **Step 2: Screenshots** (same recipe as Task 7): Progress top and scrolled — actions row under the stats, banner collapsed, then expanded; recent workouts with abbreviated dates.
- [ ] **Step 3: Push and open the PR**
```bash
git push -u origin ux/ia-2-progress
gh pr create --base ux/profile-progress-ia --head ux/ia-2-progress \
  --title "IA-2: Progress tab actions row and outcome banner" --body "$(cat <<'EOF'
Implements PR IA-2 of docs/superpowers/specs/2026-09-14-profile-progress-ia-design.md. Stacked on IA-1.

- New order: last analysis · region chips · pain trend · stats + personal best · **actions row** · Recovery Insights · **outcome banner** · recent workouts · re-assessment; the actions row also shows in the empty/error states so Log Workout is always reachable
- `ActionTile` (Log Workout / Recovery Notes) replaces the two nav rows; identifiers `progress.logWorkoutTile` / `progress.notesTile`
- `OutcomePromptView` gains `.banner`: one-line row that expands in place (`outcomePrompt.expand`); `.card` callers unchanged
- Token sweep: `AppColors.streak/streakTint`, `AppFonts.icon*`, `AppSpacing.xs/xxxl`; recent-workout dates abbreviated

Verification: UnitPlan green; ProgressTabUITests green under FullPlan; screenshots attached in the session.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## PR IA-3 — Guided workout focus

### Task 12: `TabSelection.isTabBarHidden` (test first)

**Files:**
- Create: `ios/PT-Helper/COILTests/TabSelectionTests.swift`
- Modify: `ios/PT-Helper/COIL/Views/TabSelection.swift:13` (after `selectedTab`)

- [ ] **Step 0: Branch for IA-3** (from the IA-2 head):
```bash
git switch -c ux/ia-3-workout
```

- [ ] **Step 1: Write the failing tests** (full file):
```swift
import XCTest
@testable import COIL

@MainActor
final class TabSelectionTests: XCTestCase {

    func testTabBarHidden_defaultsToFalse() {
        XCTAssertFalse(TabSelection().isTabBarHidden)
    }

    func testPopToRootAndGoHome_doesNotTouchTabBarHidden() {
        let selection = TabSelection()
        selection.selectedTab = 2
        selection.isTabBarHidden = true
        selection.popToRootAndGoHome()
        XCTAssertEqual(selection.selectedTab, 0)
        XCTAssertTrue(selection.isTabBarHidden,
                      "Only the workout's onDisappear restores the bar; navigation must not")
    }
}
```

- [ ] **Step 2: Run to verify it fails** → `-only-testing:COILTests/TabSelectionTests` → `value of type 'TabSelection' has no member 'isTabBarHidden'`.

- [ ] **Step 3: Add the flag.** After `@Published var selectedTab: Int = 0` insert:
```swift

    /// True while a guided workout is on screen. `MainTabView` drops the floating
    /// bar when this is set; `GuidedWorkoutView` sets it on appear and clears it on
    /// disappear. Nothing else may write it.
    @Published var isTabBarHidden = false
```

- [ ] **Step 4: Run** → 2 `passed`.

- [ ] **Step 5: Commit**
```bash
git add ios/PT-Helper/COILTests/TabSelectionTests.swift ios/PT-Helper/COIL/Views/TabSelection.swift
git commit -m "Add TabSelection.isTabBarHidden for the guided workout

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: `MainTabView` drops the bar when hidden

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/MainTabView.swift:66-77`

- [ ] **Step 1: Wrap the bar.** Replace
```swift
            // Full-width tab bar pinned to bottom
            VStack(spacing: 0) {
                Spacer()
                FloatingTabBar(selectedTab: $tabSelection.selectedTab, onTabTapped: { tapped in
                    if tabSelection.selectedTab == tapped {
                        tabSelection.popToRootCurrentTab()
                    }
                }, onAssessmentTapped: {
                    tabSelection.assessmentRequest = .gateway
                })
                .ignoresSafeArea(edges: .bottom)
            }
```
with
```swift
            // Full-width tab bar pinned to bottom; slides away during a guided workout.
            VStack(spacing: 0) {
                Spacer()
                if !tabSelection.isTabBarHidden {
                    FloatingTabBar(selectedTab: $tabSelection.selectedTab, onTabTapped: { tapped in
                        if tabSelection.selectedTab == tapped {
                            tabSelection.popToRootCurrentTab()
                        }
                    }, onAssessmentTapped: {
                        tabSelection.assessmentRequest = .gateway
                    })
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(AppAnimations.smooth, value: tabSelection.isTabBarHidden)
```
The `TabView` above is unaffected: tab content already ignores the bar (it clears it with `floatingTabBarClearance()`), so nothing jumps when the bar leaves.

- [ ] **Step 2: Build** → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COIL/Views/MainTabView.swift
git commit -m "Hide the floating tab bar while TabSelection.isTabBarHidden is set

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: `ExerciseImageView.showsDifficultyBadge`

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/Components/ExerciseImageView.swift:5-7`, `:141-145`, `:165-168`

- [ ] **Step 1: Add the flag.** After `var isCompact: Bool = false` (`:7`) add:
```swift
    /// The full-size image shows a `DifficultyBadge` under the frame by default; the
    /// guided workout passes `false` because its header already states the difficulty
    /// and the badge clipped inside the 200pt image container.
    var showsDifficultyBadge: Bool = true
```

- [ ] **Step 2: Honour it in `fullImageView`.** Replace
```swift
            // Difficulty badge
            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
    }
```
with
```swift
            if showsDifficultyBadge {
                DifficultyBadge(difficulty: exercise.difficulty)
            }
        }
        .padding(.vertical, showsDifficultyBadge ? AppSpacing.lg : 0)
    }
```
and in `generatingContent` replace
```swift
            DifficultyBadge(difficulty: exercise.difficulty)
        }
        .padding(.vertical, AppSpacing.lg)
    }
```
with
```swift
            if showsDifficultyBadge {
                DifficultyBadge(difficulty: exercise.difficulty)
            }
        }
        .padding(.vertical, showsDifficultyBadge ? AppSpacing.lg : 0)
    }
```
Every existing caller omits the argument, so nothing else changes.

- [ ] **Step 3: Build** → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**
```bash
git add ios/PT-Helper/COIL/Views/Components/ExerciseImageView.swift
git commit -m "Let ExerciseImageView omit the difficulty badge

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: `GuidedWorkoutView` hides the bar, sits on the safe area, and drops raw values

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` (anchors at `d78ceae`: `:5-10`, `:65-74`, `:177`, `:253`, `:330-336`, `:352`, `:384`, `:479`, `:570`, `:631`)
- Modify: `ios/PT-Helper/COIL/Views/GuidedWorkoutSummaryView.swift:113`

Blast radius: `grep -rn "GuidedWorkoutView(plan:" ios/PT-Helper/COIL` — every construction is inside the tab shell (`MainTabView` injects `TabSelection`). If a `#Preview`/`PreviewProvider` constructs it, add `.environmentObject(TabSelection())` there.

- [ ] **Step 1: Environment object and appear/disappear.** After `@EnvironmentObject private var savedPlansVM: SavedPlansViewModel` (`:8`) add:
```swift
    @EnvironmentObject private var tabSelection: TabSelection
```
Replace the `.onAppear { … }` block (`:65-74`) with:
```swift
        .onAppear {
            // Focus mode: the floating tab bar leaves for the whole workout, including
            // the summary; `onDisappear` restores it when the workout is popped.
            tabSelection.isTabBarHidden = true
            AnalyticsService.shared.log(.workoutStarted, parameters: ["exercise_count": vm.totalExercises])
            if let checkpoint = GuidedWorkoutViewModel.savedCheckpoint(forPlanId: vm.plan.id.uuidString) {
                savedCheckpoint = checkpoint
                vm.isAwaitingCheckpointDecision = true
                showResumePrompt = true
            }
            // Auto-expand instructions for first encounter with exercise
            showInstructions = currentFamiliarity == .new
        }
        .onDisappear {
            tabSelection.isTabBarHidden = false
        }
```

- [ ] **Step 2: Bottom bar on the safe area.** In `bottomActionBar` replace
```swift
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, FloatingTabBarMetrics.clearance)
        .background(
            AppColors.cardBackground
                .shadow(color: AppColors.cardShadowColor, radius: 12, y: -4)
        )
```
with
```swift
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
        .background(
            AppColors.cardBackground
                .shadow(color: AppColors.cardShadowColor, radius: 12, y: -4)
                .ignoresSafeArea(edges: .bottom)   // the card colour fills under the home indicator
        )
```
In `restPhaseView`, the Skip Rest button's `.padding(.bottom, FloatingTabBarMetrics.clearance)` (`:479`) becomes `.padding(.bottom, AppSpacing.lg)`.

- [ ] **Step 3: No difficulty badge in the workout image.** `:177` `ExerciseImageView(exercise: exercise, isCompact: false)` becomes `ExerciseImageView(exercise: exercise, isCompact: false, showsDifficultyBadge: false)` (the parameter was added in Task 14).

- [ ] **Step 4: Token sweep** (grep each "before"):

| Where | Before | After |
|---|---|---|
| tips lightbulb (`:253`) | `.foregroundColor(Color(CoilPalette.pop))` | `.foregroundColor(AppColors.streak)` |
| `secondaryActionsRow` (`:352`) | `HStack(spacing: 32)` | `HStack(spacing: AppSpacing.huge)` |
| `compactActionButton` (`:384`) | `.font(.system(size: 16, weight: .medium))` | `.font(AppFonts.iconM)` |
| progress segments (`:570`) | `RoundedRectangle(cornerRadius: 3)` | `Capsule()` |
| `lastSessionContextView` (`:631`) | `.font(.system(size: 14, weight: .semibold))` | `.font(AppFonts.iconS)` |

The empty-state hero glyph `.font(.system(size: 50))` (`:524`) is outside the icon ladder and stays (documented: decorative hero glyph, design pass).

- [ ] **Step 5: Summary spacer.** `GuidedWorkoutSummaryView.swift:113` `Spacer(minLength: FloatingTabBarMetrics.clearance)` becomes `Spacer(minLength: AppSpacing.xxl)` (the summary shows while the bar is still hidden).

- [ ] **Step 6: Build** → `** BUILD SUCCEEDED **`; then
```bash
grep -n "\.font(\.system(size\|Color\.white\.opacity\|Color(CoilPalette\|cornerRadius: [0-9]\|spacing: [0-9]\|FloatingTabBarMetrics" ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift
```
Expected: exactly one match, the `size: 50` hero glyph.

- [ ] **Step 7: Commit**
```bash
git add ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift ios/PT-Helper/COIL/Views/GuidedWorkoutSummaryView.swift
git commit -m "Hide the tab bar during a guided workout and sit its bar on the safe area

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: UI test — the bar hides and comes back

**Files:**
- Modify: `ios/PT-Helper/COILUITests/GuidedWorkoutUITests.swift`

- [ ] **Step 1: Add the test** (append inside the class):
```swift
    @MainActor
    func testWorkout_hidesTabBarUntilDiscarded() throws {
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10),
                      "Tab bar should be visible before the workout")
        navigateToWorkout()
        assertExists("workout.completeSetButton", timeout: 10)

        // The bar is removed from the hierarchy, not just covered.
        XCTAssertTrue(app.buttons["Home"].waitForNonExistence(timeout: 5),
                      "The floating tab bar should hide during a guided workout")

        let endButton = app.buttons["workout.endButton"]
        XCTAssertTrue(endButton.waitForExistence(timeout: 5))
        endButton.tap()
        let discard = button("Discard Without Saving")
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()

        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 5),
                      "Leaving the workout should restore the tab bar")
        captureScreenshot(name: "Workout-TabBarRestored")
    }
```

- [ ] **Step 2: Run** the FullPlan command with `-only-testing:COILUITests/GuidedWorkoutUITests`. Expected: 9 `passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**
```bash
git add ios/PT-Helper/COILUITests/GuidedWorkoutUITests.swift
git commit -m "Assert the tab bar hides during a guided workout and returns after

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 17: IA-3 verification and PR

- [ ] **Step 1: Full UnitPlan** → `Executed 1366 tests, with 1 test skipped and 0 failures`, `** TEST SUCCEEDED **`.
- [ ] **Step 2: Screenshots** (Task 7 recipe): workout exercise phase (no tab bar; bottom bar on the safe area; no clipped Beginner badge), rest phase (no tab bar), summary (no tab bar), then back on the Plan tab (bar restored).
- [ ] **Step 3: Push and open the PR**
```bash
git push -u origin ux/ia-3-workout
gh pr create --base ux/ia-2-progress --head ux/ia-3-workout \
  --title "IA-3: Guided workout hides the tab bar" --body "$(cat <<'EOF'
Implements PR IA-3 of docs/superpowers/specs/2026-09-14-profile-progress-ia-design.md. Stacked on IA-2.

- `TabSelection.isTabBarHidden` (2 unit tests); `MainTabView` drops the floating bar with a slide/fade while it is set
- `GuidedWorkoutView` sets it on appear and clears it on disappear; the bottom action bar and Skip Rest now sit on the safe area (`AppSpacing.lg`) instead of clearing a bar that is gone; the summary's spacer follows
- `ExerciseImageView(showsDifficultyBadge:)` — the workout omits the badge that clipped in the 200pt frame
- Token sweep in the workout file: `AppSpacing.huge`, `AppFonts.iconM/iconS`, `Capsule()` segments, `AppColors.streak`
- `GuidedWorkoutUITests.testWorkout_hidesTabBarUntilDiscarded`

Verification: UnitPlan green; GuidedWorkoutUITests green under FullPlan; screenshots attached in the session.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** IA-1 Structure table → Tasks 2–5 (`ProfileSummary` Task 2, `ProfileHeroCard` Task 3, `ProfileTab` Task 4, `SettingsView` + `ProgressTab` + `MainTabView` Task 5); `ProfileSummary` tests → Task 1; hero anatomy incl. reveal/Reduce Motion → Tasks 3–4; settings groups 1–5, `.cardStyle()` question (answered: bespoke `groupCard` with zero padding, radius unified to `AppCorners.card`), `iconS` icons and the 52pt inset → Task 5; deletions (`profileCard`, `initials`, `showsDoneButton`, inner NavigationStack, `dismiss`) → Task 5; UI tests → Task 6; acceptance → Task 7. IA-2 items 1–5 → Tasks 8–9; acceptance → Tasks 10–11. IA-3 items 1–6 → Tasks 12–15 (item 6 is the note in Task 13); tests → Tasks 12 and 16; acceptance → Task 17. Workstream verification (token audit, FullPlan per touched class, screenshots) → Tasks 7, 11, 17.
- **Type consistency:** `ProfileSummary.ActivePlan(name:statusText:isActive:)`, `PlanWeek(current:total:)`, `Stats(streak:planWeek:sessions:)` are used identically in Tasks 1, 2, 3; `ProfileSummaryBuilder.build(profile:plans:streak:sessionCount:)` in Tasks 1, 2, 4; `RevealOnAppear(index:)` defined in Task 4, used in Tasks 4–5; `OutcomePromptView.Style.banner` defined in Task 8, passed in Task 9; `showsDifficultyBadge` defined in Task 14, passed in Task 15; `isTabBarHidden` defined in Task 12, read in Task 13, written in Task 14.
- **Build order:** Task 4 keeps the old `SettingsView` signature so each commit builds; Task 5 changes the signature and all callers in one commit; Task 14 adds the `showsDifficultyBadge` flag before Task 15 passes it, so every commit builds on its own.
- **Known judgement calls** are the eight deviations at the top; the bounce-past-the-top of the Profile scroll view shows the light page (the nav bar is opaque ink, so the seam is only visible on over-scroll).

---

## Audit Results

### Structural Review
1. FILE COMPLETENESS — PASS. 2. DEPENDENCY ORDER — WARN: Tasks 14 and 15 are not independently buildable (Task 14 passes `showsDifficultyBadge:` before Task 15 defines it); merge them into one task/commit. 3. MISSING STEPS — WARN: Task 9 replaces the error/empty-state spacers with `AppSpacing.xxxl` top and bottom where the spec said `FloatingTabBarMetrics.clearance` for the bottom pair; functionally fine now that the actions row follows the state view, but log it as a deviation. 4. API/FUNCTION VERIFICATION — PASS: every symbol exists with the claimed signature; every quoted "before" block matched byte-for-byte at `d78ceae`; `WorkoutSessionView`/`NotesView` titles match the UI-test assertions. 5. SCOPE CALIBRATION — WARN: Task 5 Step 6 gives `notificationsCard` and `legalCard` as prose ("same treatment") instead of quoted diffs. 6. TESTABILITY — PASS: test counts (SettingsUITests 5→6, ShellNavigation 7, UnitPlan 1350→1360→1362) and seeded data (Test User, streak 3, Knee Rehab Plan 6 weeks started 10 days ago → Week 2 of 6) verified. 7. INTEGRATION RISK — PASS: all callers of `SettingsView(`, `OutcomePromptView(`, `ExerciseImageView(`, `GuidedWorkoutView(plan:`, `FloatingTabBarMetrics.clearance` and every UI-test query enumerated; nothing outside the plan's edits is affected.
OVERALL: MINOR CONCERNS

### Adversarial Review
1. FATAL FLAW — The stack is cut from `d78ceae`, a frozen snapshot of PRs #75/#76/#77, all still open; `main` looks squash-merged, and #76 touches `ProgressTab.swift`, `SettingsView.swift`, `GuidedWorkoutView.swift` and `SettingsUITests.swift` at the lines this plan rewrites, so review changes or the squash-merge could turn "rebase onto main" into a multi-branch conflict slog.
2. HIDDEN ASSUMPTION — That the merged copies of Foundation-F2 and Tokens are final; review feedback could still reshape the tokens (`textOnDark*`, `onDark*`, `streak`, `icon*`) the plan hardcodes.
3. SIMPLER ALTERNATIVE — One PR against `ux/ia-base` instead of three stacked branches; the areas are nearly file-disjoint (only `TabSelection.isTabBarHidden` crosses), so one PR keeps the task list and removes two rebase points.
4. WHAT BREAKS — `SettingsView.notificationsCard` (five toggles/pickers with live `onChange` handlers scheduling notifications) is edited by prose with no test asserting the toggles still round-trip; a dropped binding would build green.
5. FIRST HOUR TEST — Task 0's push of `ux/ia-base` and `gh pr create --base ux/ia-base` need push rights; and the worktree HEAD is now one commit past `d78ceae` (the plan doc), so the base must stay pinned to `d78ceae` (it is).
VERDICT: REVISE BEFORE BUILDING

### Revisions applied (2026-09-15)
- Tasks 14 and 15 swapped: the `ExerciseImageView` flag now lands (Task 14) before `GuidedWorkoutView` passes it (Task 15), so each commit builds alone.
- Task 5 Step 6 now gives `notificationsCard` and `legalCard` verbatim (handlers, identifiers and labels byte-identical to today); the Delete Account row keeps its primary title per the spec.
- Deviation 9 records the `AppSpacing.xxxl` state spacers; deviation 7 now carries the `--onto` rebase recipe (only the IA commits replay), the no-force-push republish route, and the fast-forward-the-base procedure if #75–#77 change under review.
- The user chose to keep the spec's three stacked PRs over the single-PR alternative.

### Re-audit (2026-09-15, the one permitted pass)
- **Structural:** all seven criteria PASS — file map matches the renumbered tasks; Task 14's trailing default parameter builds alone; the verbatim `notificationsCard`/`legalCard` diff byte-for-byte against `SettingsView.swift:540-747` except chrome/icons/dividers/title colour; no prose-only edit instruction remains; test counts consistent; `git rebase --onto origin/main ux/ia-base <branch>` is correct because `--onto` replays by reachability, so the merge commit's ancestors are excluded.
- **Adversarial:** MINOR CONCERNS — round-1 fatal flaw adequately mitigated for the stack-now decision; `ProfileTab`'s new environment objects are already injected by `MainTabView`; `notificationsCard` verified byte-identical; Task 10 should query the tile identifiers via `app.descendants(matching: .any)` like the rest of the suite rather than `app.buttons` (applied above); "Session Events" becoming DEBUG-only is deviation 5, intentional.

**Overall after re-audit: MINOR CONCERNS** — proceed to execution (subagent-driven, per the user).
