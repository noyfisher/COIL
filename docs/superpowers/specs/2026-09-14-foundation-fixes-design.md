# Foundation Fixes — Design Spec

**Date:** 2026-09-14 · **Workstream:** 1 of 3 (Foundation → Tokens → IA) · **Source:** `docs/archive/ux-audits/ux-audit-2026-09-14.md`
**Branch:** `ux/foundation-fixes` (own worktree) · **Delivery:** two small PRs, both gated on `xcodebuild build` + UnitPlan, FullPlan before merge.

## Goal

Land the audit's three P0 accessibility gaps and five functional P1s with no visual redesign, so the later token and IA workstreams build on correct behaviour. Every change is behaviour-preserving for sighted users except where the audit showed a bug.

## Non-goals

- No new design tokens (workstream 2). No colour, spacing or font changes.
- No information-architecture change (workstream 3): the Progress gear stays, `SettingsView` keeps its "Settings" title.
- No changes to `functions/`, prompts, or Firestore schema. `weeklySchedule` storage format is unchanged.

## PR F1 — Accessibility labels and a11y P1s

All changes are modifier additions; no layout changes.

| # | File | Change |
|---|------|--------|
| 1 | `Views/SettingsView.swift:557` | `Toggle("", isOn: $notificationService.isEnabled)` gains `.accessibilityLabel("Reminders")`. |
| 2 | `Views/SettingsView.swift:595` | Reminder-time `DatePicker` gains `.accessibilityLabel("Reminder time")`. |
| 3 | `Views/SettingsView.swift:630, 654, 678` | Toggles gain `.accessibilityLabel("Workout reminders")`, `"Re-assessment prompts"`, `"Inactivity nudges"`. |
| 4 | `Views/OnboardingSteps/BasicInfoStepView.swift:151-158` | Terms checkbox `Button` gains `.accessibilityLabel("I agree to the Terms of Service and Privacy Policy")` and `.accessibilityValue(viewModel.hasAcceptedTerms ? "Checked" : "Unchecked")`. Identifier `onboarding.termsCheckbox` unchanged. |
| 5 | `Views/OnboardingSteps/BasicInfoStepView.swift:71-109` | Each height `Menu` gains `.accessibilityLabel("Height, \(feet) feet")` / `"Height, \(inches) inches"` (value interpolated from the profile). |
| 6 | `Views/OnboardingSteps/BasicInfoStepView.swift:29-31` | Date-of-birth `DatePicker` gains `.accessibilityLabel("Date of birth")`. |
| 7 | `Views/ProgressTab.swift:171-175` | Streak `NavigationLink` gains `.accessibilityLabel("\(streak) day streak, view achievements")` (streak = `streakService.streakData.currentStreak`). Identifier `progress.streakBadge` unchanged. |
| 8 | `Views/MyPlanTab.swift:149-230` | Keep the card's `.onTapGesture` (hit-testing unchanged) but expose the open action to VoiceOver on the **info block** (the `HStack` at 157-197, which contains no buttons): `.accessibilityElement(children: .combine)`, `.accessibilityAddTraits(.isButton)`, `.accessibilityLabel("\(plan.planName), \(plan.totalWeeks) weeks")`, `.accessibilityHint("Opens plan")`, `.accessibilityAction { route = .detail(plan.id) }`. Identifier `myPlan.planCard` goes on the plan-name `Text` leaf (tapping it triggers the card gesture). Do **not** wrap the card in a `Button` and do **not** put an identifier or label on the outer container: either would swallow the inner `myPlan.startWorkoutButton` that three UI test classes rely on (see the container-id shadowing note in the project memory). |
| 9 | `Views/HomeTab.swift:123-165` | `DayCell` gains `.accessibilityElement(children: .combine)` and `.accessibilityLabel("\(weekdayName) \(dayNumber), \(isCompleted ? "workout completed" : "no workout")")` where `weekdayName` is the full weekday (`DateFormatter` `EEEE`). |
| 10 | `Views/RehabPlanView.swift:613-617, 638` | The exercise name `Text` (a leaf) gains `.accessibilityIdentifier("rehabPlan.exerciseName.\(index)")` (enumerate `plan.exercises`). Nothing is added to the `NavigationLink` or the card container. The swap button keeps `rehabPlan.swapExerciseButton`. |

**Acceptance (F1):** VoiceOver on the simulator reads a name for every toggle, the checkbox, both height menus, the DOB picker and the streak badge; `xcrun simctl` accessibility snapshot (or the XcodeBuildMCP `snapshot_ui`) shows no `switch||` or `button|||` entries on Settings or Onboarding step 1; `MyPlanTabUITests`, `GuidedWorkoutUITests`, `SettingsUITests`, `ShellNavigationUITests` still pass unchanged.

## PR F2 — Functional P1s

### F2.1 `RehabExercise.dosageText`

Add to `Models/RehabPlan.swift` (extension on `RehabExercise`):

```swift
/// "12 reps" when `reps` parses as an integer, otherwise `reps` verbatim ("30 seconds", "10 each side").
var repsText: String
/// "\(sets) sets × \(repsText)" — the one dosage string every screen uses.
var dosageText: String
```

Parsing: trim whitespace; `Int(trimmed)` non-nil and ≥ 0 → `"\(n) reps"` (`"1 rep"` when n == 1); a unit-less range matching `^\d+\s*(?:-|–|—|to)\s*\d+$` ("10-12", "10–12", "8 to 10") → `"\(trimmed) reps"` (the most common AI-emitted shape, and the `TestFixtures.makeExercise` default; found by the code review, the workout badge would otherwise lose its unit); else the trimmed string verbatim ("30 seconds", "10 each side", "-3"). `sets` renders as `"\(sets) sets"` (`"1 set"` when 1). Separator is the multiplication sign `\u{00D7}` with spaces, matching `RehabPlanView.swift:665` today.

Call sites: `HomeTab.swift:298` → `dosageText`; `GuidedWorkoutView.swift:229` → `repsText`; `GuidedWorkoutView.swift:463` (up-next subtitle) → `dosageText`; `RehabPlanView.swift:665` → `dosageText`. `MyPlanTab` and `ExerciseDetailView` untouched unless they render the same pair (grep `sets) sets` before finishing).

Tests (`COILTests/RehabExerciseDosageTests.swift`): numeric reps → "3 sets × 12 reps"; timed → "3 sets × 30 seconds"; free text → "2 sets × 10 each side"; `sets == 1` → "1 set × 12 reps"; `reps == "1"` → "1 rep"; whitespace-padded `" 15 "` → "15 reps"; ranges "10-12" / "10–12" / "8 to 10" → "… reps"; "-3" → verbatim; "3 sets × 10-12 reps".

### F2.2 `RehabPlan.status`

Add to `Models/RehabPlan.swift`:

```swift
enum PlanStatus: Equatable { case notStarted, active(week: Int), completed }
var status: PlanStatus   // notStarted when startDate == nil; completed when isCompleted; else active(week: currentWeek ?? 1)
```

`MyPlanTab.swift:160`: replace the hardcoded `CoilBadge(text: "Active")` with:
- `.active` → `CoilBadge(text: "Active")` (unchanged look);
- `.notStarted` → `Text("Not started")` in `AppFonts.captionMedium` / `AppColors.secondaryText`;
- `.completed` → `Text("Completed")` in `AppFonts.captionMedium` / `AppColors.success`.
(No `CoilBadge` variants: that is a token-PR concern.)

`HomeTab.swift:22-25` (`activePlan`): prefer the first rehab plan whose `status` is `.active`, then any rehab plan, then any plan (current fallback order otherwise unchanged).

Tests (`COILTests/RehabPlanStatusTests.swift`): nil start → `.notStarted`; start today, 6 weeks → `.active(week: 1)`; start 10 days ago → `.active(week: 2)`; start 42+ days ago → `.completed`; `HomeTab` selection preference is covered by a pure helper `HomeProgramLogic.preferredPlan(from:)` (see F2.3) tested with [notStarted, active] → active.

### F2.3 Home honours the weekly schedule

New `enum HomeProgramLogic` (in `HomeTab.swift`, beside `HomeStripLogic`), pure and testable:

```swift
/// nil = the plan has no usable schedule (empty, or every day empty) → show all exercises (today's behaviour).
/// []  = a scheduled rest day.
static func todaysExercises(for plan: RehabPlan, on date: Date, calendar: Calendar = .current) -> [RehabExercise]?
/// Next scheduled day strictly after `date` within 7 days: (weekdayName: "Tue", exerciseCount: 2), or nil.
static func nextSession(for plan: RehabPlan, after date: Date, calendar: Calendar = .current) -> (weekdayName: String, exerciseCount: Int)?
static func preferredPlan(from plans: [RehabPlan]) -> RehabPlan?
```

Day index = `calendar.component(.weekday, from: date) - 1` (Sunday = 0), matching `RehabPlanView.swift:547` (`dayNames` starts at "Sun") and `RehabPlanViewModel.createWeeklySchedule` (comments "1 = Mon"). A schedule entry matches an exercise when it equals `exercise.id.uuidString` (generator, `RehabPlanViewModel.swift:723`) **or** `exercise.name` case-insensitively (test seeder, `TestDataSeeder.swift:291`). Entries that match nothing are ignored. `weeklySchedule.count != 7` or all-empty → return nil.

**Stale schedule entries (audit finding):** `ExerciseSwapViewModel.selectSubstitute` replaces an exercise with a new UUID and never rewrites `weeklySchedule`, so on a generated (id-keyed) plan a swapped exercise's day resolves to nothing. `todaysExercises` therefore returns nil (show everything) when a day's entries are non-empty but none resolve — a false "rest day" is never shown. `nextSession` counts resolved exercises and falls back to the raw entry count. Keeping `weeklySchedule` in sync on swap is a follow-up (below), not part of this workstream.

`ProgramDayView` (`HomeTab.swift:207-281`):
- `nil` → unchanged rendering.
- non-empty → rows show only today's exercises; the count label reads "N exercises today"; the CTA is unchanged and still passes the full plan to `GuidedWorkoutView` (the workout screen owns skipping).
- `[]` → `RestDayCard`: `CoilDividerHeader("Today's Program")` stays; a `.cardStyle()` card with `Text("Rest day")` in `AppFonts.cardTitle`, a line `"Next session: \(weekdayName) · \(count) exercises"` in `AppFonts.small` / `AppColors.secondaryText` (omitted when `nextSession` is nil), and a `SecondaryButtonStyle` button "Start a workout anyway" that navigates to `GuidedWorkoutView(plan:)`. This button carries `accessibilityIdentifier("home.startWorkoutButton")` so the identifier exists on every day.

Tests (`COILTests/HomeProgramLogicTests.swift`, fixed calendar `Calendar(identifier: .gregorian)` with `TimeZone(identifier: "UTC")` and explicit dates): Monday with the seeded schedule → `[]`; Sunday → Wall Sits + Straight Leg Raises by name; id-based schedule → matches by id; empty schedule → nil; 5-element schedule → nil; `nextSession` from Monday → ("Tue", 1) for the seeded plan; from Saturday wraps to Sunday.

### F2.4 PDF share on saved plans

`RehabPlanView.swift:296-301`: change `.onChange(of: viewModel.rehabPlan?.id) { _, _ in … }` to `.onChange(of: viewModel.rehabPlan?.id, initial: true) { _, _ in … }` so `cachedPDFData` is generated for a plan set in `init(existingPlan:)`. No other change.

Test: `COILUITests/MyPlanTabUITests.swift` gains `testOpenSavedPlan_showsShareButton`: seeded launch → Plan tab → tap `myPlan.planCard` (first match) → assert `rehabPlan.shareButton` exists within 5 s.

### F2.5 `SettingsView` hosting

`SettingsView.swift`:
- Remove the inner `NavigationStack` (line 32); the content root becomes the `ZStack`. Hosts supply the stack.
- Add `var showsDoneButton: Bool = false`; the `.toolbar` Done item (76-79) renders only when true.
- `ProgressTab.swift:25-35`: the sheet body becomes `NavigationStack { SettingsView(userName:…, onEditProfile:…, showsDoneButton: true) }`.
- `MainTabView.swift:203-218` (`ProfileTab`): unchanged call (defaults to no Done); its own `NavigationStack` now provides the bar.
- The "Update Health Info" row (473) keeps `dismiss()` (a no-op when not presented) so the sheet path still closes before the editor opens.

Acceptance: Profile tab shows no Done button; Progress gear → sheet still shows Done and it dismisses; `SettingsUITests` (gear path) and `ShellNavigationUITests:89` (Profile-tab path) pass unchanged.

## Verification

- `xcodebuild build` (COIL scheme, iPhone 16 / OS 18.2 by UDID) and UnitPlan green after each PR.
- FullPlan (includes UI tests) before merge; the three new unit test files plus the one new UI test must be in the run.
- Manual: VoiceOver pass on Settings, Onboarding step 1, Progress (streak badge), My Plan (card), Home (week strip); open the seeded Knee plan and see the share icon; set the simulator date to a rest day (Monday for the seeded plan) and see the rest-day card.

## Out of scope but noted

- `TestDataSeeder` schedules use names while the generator uses ids; `HomeProgramLogic` tolerates both. A follow-up could make the seeder use ids.
- `ExerciseSwapViewModel.selectSubstitute` (and `AdaptiveProgressionAnalyzer.applyProgression` if it replaces exercises) should rewrite matching `weeklySchedule` entries to the substitute's id so schedules stay resolvable; until then Home falls back to showing all exercises for that day.
- `WellnessPlanView`, `ExerciseSwapSheet` and `EditRehabPlanView` also render "sets × reps" and are migrated to `dosageText` in F2.1 (found by the plan audit).
- The seeded streak (3 / 7) versus "Earned 0" on Achievements is a seeding gap (`seedStreakData` does not seed `StreakService.achievements`); not fixed here.
