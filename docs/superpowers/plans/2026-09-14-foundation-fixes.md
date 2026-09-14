# Foundation Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the audit's three P0 accessibility gaps and five functional P1s (PDF share, schedule-aware Home, real plan status, dosage copy, presentation-agnostic Settings) in two small PRs with no visual redesign.

**Architecture:** Pure logic goes into small testable units (`RehabExercise.dosageText`, `RehabPlan.status`, `HomeProgramLogic`) covered by XCTest unit tests; view changes are modifier additions and call-site swaps verified by XCUI tests that query accessibility labels and identifiers. Each task is one commit on `ux/foundation-fixes` in its own worktree.

**Tech Stack:** Swift 5 / SwiftUI, XCTest + XCUITest, `xcodebuild` against the iPhone 16 (iOS 18.2) simulator. Spec: `docs/superpowers/specs/2026-09-14-foundation-fixes-design.md`.

---

## Ground rules for every task

- **Warnings are errors** in this project (COIL builds with `-warnings-as-errors`). Unused variables, unhandled results or implicit `self` captures fail the build.
- **Build command** (run from the worktree root; the UDID is this machine's iPhone 16 / iOS 18.2 — find it with `xcrun simctl list devices | grep "iPhone 16 ("` if it differs):

```bash
SIM=8B908AF6-D437-40DC-9593-2DDC315B0480
xcodebuild build -project ios/PT-Helper/COIL.xcodeproj -scheme COIL \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath /tmp/coil-dd-foundation 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
```
Expected last line: `** BUILD SUCCEEDED **`.

- **Unit test command** (one class):

```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj -scheme COIL \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /tmp/coil-dd-foundation \
  -only-testing:COILTests/<ClassName> 2>&1 | grep -E "Test Case .* (passed|failed)|error:|\*\* TEST"
```

- **UI test command** (one method): same as above with `-only-testing:COILUITests/<ClassName>/<methodName>`. UI tests launch the app with `--uitesting --skip-onboarding --seed-mock-data` via `UITestBase`; the seeded data is in `Services/TestDataSeeder.swift` (plans "Knee Rehab Plan" started 10 days ago, 6 weeks, schedule Sun/Tue/Thu; "Shoulder Mobility Plan" never started; streak 3; three sessions).
- **Line numbers are anchors, not addresses.** They refer to the files as of commit `33ace5d`. Tasks 5, 11 and 13 all insert code into `HomeTab.swift`, and Task 6 inserts a line into `RehabPlanView.swift` above Task 9's anchor, so later tasks' cited lines drift; per CLAUDE.md R1, grep for the quoted code before editing and never edit by line number alone.
- **Never `git add .`** — stage the files named in each task.
- Commit messages: imperative sentence, no prefix (repo convention), ending with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## File map

| File | Responsibility | Tasks |
|---|---|---|
| `ios/PT-Helper/COIL/Models/RehabPlan.swift` | Add `RehabExercise.repsText/dosageText` and `RehabPlan.PlanStatus/status` | 8, 10 |
| `ios/PT-Helper/COIL/Views/HomeTab.swift` | `HomeProgramLogic`, schedule-aware `ProgramDayView`, `RestDayCard`, week-strip accessibility, `preferredPlan` | 5, 11, 12, 13 |
| `ios/PT-Helper/COIL/Views/MyPlanTab.swift` | Card VoiceOver action + `myPlan.planCard`, real status badge | 4, 12 |
| `ios/PT-Helper/COIL/Views/ProgressTab.swift` | Streak badge label, Settings sheet host wraps in `NavigationStack` | 3, 15 |
| `ios/PT-Helper/COIL/Views/RehabPlanView.swift` | Exercise-name identifiers, `dosageText`, PDF `initial: true` | 6, 9, 14 |
| `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift` | `repsText` / `dosageText` call sites | 9 |
| `ios/PT-Helper/COIL/Views/WellnessPlanView.swift`, `ExerciseSwapSheet.swift`, `EditRehabPlanView.swift` | `dosageText` call sites (found by the audit) | 9 |
| `ios/PT-Helper/COIL/Views/SettingsView.swift` | Toggle/date-picker labels; drop inner `NavigationStack`; `showsDoneButton` | 1, 15 |
| `ios/PT-Helper/COIL/Views/OnboardingSteps/BasicInfoStepView.swift` | Checkbox, height menu and DOB labels | 2 |
| `ios/PT-Helper/COILTests/RehabExerciseDosageTests.swift` (new) | Unit tests for dosage copy | 8 |
| `ios/PT-Helper/COILTests/RehabPlanStatusTests.swift` (new) | Unit tests for plan status | 10 |
| `ios/PT-Helper/COILTests/HomeProgramLogicTests.swift` (new) | Unit tests for today's program / next session / preferred plan | 11 |
| `ios/PT-Helper/COILUITests/SettingsUITests.swift` | Toggle label test; no-Done-on-Profile test | 1, 15 |
| `ios/PT-Helper/COILUITests/OnboardingUITests.swift` | Step-1 control label test | 2 |
| `ios/PT-Helper/COILUITests/ProgressTabUITests.swift` (new) | Streak badge label test | 3 |
| `ios/PT-Helper/COILUITests/MyPlanTabUITests.swift` | Card button test, exercise-id test, status test, share-button test | 4, 6, 12, 14 |
| `ios/PT-Helper/COILUITests/HomeTabUITests.swift` (new) | Week-strip label test, start-button-every-day test | 5, 13 |
| `ios/PT-Helper/COILUITests/GuidedWorkoutUITests.swift` | Dosage badge test | 9 |

---

### Task 0: Worktree and baseline

**Files:** none changed.

- [ ] **Step 1: Create the worktree from the specs branch**

Run from the main checkout (`/Users/noyfisher/IOS-Projects/PT-Helper-Agent-v1`):

```bash
git worktree add .claude/worktrees/ux-foundation-fixes -b ux/foundation-fixes ux/design-specs
cd .claude/worktrees/ux-foundation-fixes
ls functions/.env >/dev/null && echo "worktreeinclude ok"
git log --oneline -1
```
Expected: `worktreeinclude ok` and the top commit `33ace5d Add the Foundation fixes implementation plan` (or a later commit on `ux/design-specs` if the audit revisions were committed after this line was written — anything at or after `33ace5d` is fine). If `functions/.env` is missing, copy it from the main checkout: `cp ../../../functions/.env functions/.env`.

- [ ] **Step 2: Baseline build**

Run the build command from "Ground rules". Expected: `** BUILD SUCCEEDED **`, no `error:` lines.

- [ ] **Step 3: Baseline unit test**

Run the unit test command with `-only-testing:COILTests/HomeStripLogicTests`. Expected: 3 `passed`, `** TEST SUCCEEDED **`.

---

## PR F1 — Accessibility labels and a11y P1s

### Task 1: Settings toggles and reminder-time picker announce their names

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/SettingsView.swift:557-559, 595-596, 630-631, 654-655, 678-679`
- Test: `ios/PT-Helper/COILUITests/SettingsUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `final class SettingsUITests: UITestBase { … }` (after the existing tests; `navigateToSettings()` is a private helper in this class):

```swift
    @MainActor
    func testReminderToggle_hasAccessibleName() throws {
        navigateToSettings()
        // Toggle("", …).labelsHidden() had no name at all; VoiceOver read an unnamed switch.
        let toggle = app.switches["Reminders"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5),
                      "The Reminders toggle should be named for VoiceOver")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: UI test command with `-only-testing:COILUITests/SettingsUITests/testReminderToggle_hasAccessibleName`
Expected: `failed` — "The Reminders toggle should be named for VoiceOver".

- [ ] **Step 3: Add the labels**

In `SettingsView.swift`, change the five controls exactly as follows.

Line 557 block:
```swift
                Toggle("", isOn: $notificationService.isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Reminders")
                    .accessibilityIdentifier("settings.reminderToggle")
```

Line 595 block:
```swift
                    DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Reminder time")
```

Line 630 block:
```swift
                    Toggle("", isOn: $notificationService.workoutRemindersEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Workout reminders")
```

Line 654 block:
```swift
                    Toggle("", isOn: $notificationService.reassessmentRemindersEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Re-assessment prompts")
```

Line 678 block:
```swift
                    Toggle("", isOn: $notificationService.inactivityNudgesEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Inactivity nudges")
```
(The existing `.onChange { … }` chains stay attached after these modifiers.)

- [ ] **Step 4: Build, then run the test to verify it passes**

Run: build command → `** BUILD SUCCEEDED **`. Then the UI test command from Step 2. Expected: `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/SettingsView.swift ios/PT-Helper/COILUITests/SettingsUITests.swift
git commit -m "Name the Settings toggles and reminder-time picker for VoiceOver

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Onboarding step 1 controls announce their names

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/OnboardingSteps/BasicInfoStepView.swift:29-31, 71-109, 151-158`
- Test: `ios/PT-Helper/COILUITests/OnboardingUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `final class OnboardingUITests: UITestBase { … }` (`waitForStep(_:)` and `dismissHealthConsentIfPresent()` already exist for this class):

```swift
    @MainActor
    func testStepOne_controlsHaveAccessibleNames() throws {
        dismissHealthConsentIfPresent()
        XCTAssertTrue(waitForStep(1), "Should be on step 1")

        // The Terms checkbox announced as "Square" (the SF Symbol name).
        let checkbox = app.buttons["I agree to the Terms of Service and Privacy Policy"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5), "Terms checkbox should be named")
        XCTAssertEqual(checkbox.value as? String, "Unchecked")

        // Both height menus exposed an unlabeled inner button.
        let heightMenus = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Height, "))
        XCTAssertEqual(heightMenus.count, 2, "Feet and inches menus should both be named")

        // The compact date picker announced as "Date Picker".
        XCTAssertTrue(app.descendants(matching: .any)["Date of birth"].exists, "DOB picker should be named")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: UI test command with `-only-testing:COILUITests/OnboardingUITests/testStepOne_controlsHaveAccessibleNames`
Expected: `failed` at the checkbox assertion.

- [ ] **Step 3: Add the labels**

Date of birth (lines 29-34) becomes:
```swift
                    DatePicker("", selection: $viewModel.userProfile.dateOfBirth, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .accessibilityLabel("Date of birth")
                        .tint(AppColors.accent)
                        .colorScheme(.dark)
                        .frame(maxWidth: .infinity, alignment: .leading)
```

Feet menu: after the closing `}` of the first `Menu { … } label: { … }` (line 89) add:
```swift
                        .accessibilityLabel("Height, \(viewModel.userProfile.heightFeet) feet")
```
Inches menu: after the closing `}` of the second `Menu` (line 109) add:
```swift
                        .accessibilityLabel("Height, \(viewModel.userProfile.heightInches) inches")
```

Terms checkbox (lines 151-158) becomes:
```swift
                        Button {
                            viewModel.hasAcceptedTerms.toggle()
                        } label: {
                            Image(systemName: viewModel.hasAcceptedTerms ? "checkmark.square.fill" : "square")
                                .font(.title3)
                                .foregroundColor(viewModel.hasAcceptedTerms ? AppColors.accent : OnboardingColors.muted)
                        }
                        .accessibilityLabel("I agree to the Terms of Service and Privacy Policy")
                        .accessibilityValue(viewModel.hasAcceptedTerms ? "Checked" : "Unchecked")
                        .accessibilityIdentifier("onboarding.termsCheckbox")
```

- [ ] **Step 4: Build, then run the test to verify it passes**

Build → `** BUILD SUCCEEDED **`; UI test → `passed`. If the height-menu count is 0, XCUI is exposing the `Menu` as `otherElements`; change the query to `app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Height, "))` and re-run.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/OnboardingSteps/BasicInfoStepView.swift ios/PT-Helper/COILUITests/OnboardingUITests.swift
git commit -m "Name the onboarding checkbox, height menus and date-of-birth picker for VoiceOver

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Streak badge announces what it is

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/ProgressTab.swift:170-174` (the `NavigationLink(destination: AchievementsView(...))` in the toolbar)
- Create: `ios/PT-Helper/COILUITests/ProgressTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

```swift
import XCTest

/// Covers the Progress tab's toolbar and top-of-page content.
final class ProgressTabUITests: UITestBase {

    @MainActor
    func testStreakBadge_hasDescriptiveLabel() throws {
        tapTab("Progress")
        // Seeded streak is 3; the badge used to announce just "3".
        let badge = app.buttons["3 day streak, view achievements"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10),
                      "Streak badge should say what the number means and where it goes")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/ProgressTabUITests/testStreakBadge_hasDescriptiveLabel` → `failed`.

- [ ] **Step 3: Add the label**

`ProgressTab.swift` lines 170-174 become:
```swift
                    NavigationLink(destination: AchievementsView(streakService: streakService)) {
                        StreakToolbarBadge(streakService: streakService)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(streakService.streakData.currentStreak) day streak, view achievements")
                    .accessibilityIdentifier("progress.streakBadge")
```

- [ ] **Step 4: Build and run the test** → `** BUILD SUCCEEDED **`, `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/ProgressTab.swift ios/PT-Helper/COILUITests/ProgressTabUITests.swift
git commit -m "Describe the Progress streak badge to VoiceOver

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: My Plan card is reachable as a button

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/MyPlanTab.swift:157-197`
- Test: `ios/PT-Helper/COILUITests/MyPlanTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `final class MyPlanTabUITests: UITestBase { … }`:

```swift
    @MainActor
    func testPlanCard_isExposedAsButtonAndOpensPlan() throws {
        tapTab("Plan")

        // The card's open action was an onTapGesture with no accessibility trait, so
        // VoiceOver had no way to open a plan.
        let cardButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Knee Rehab Plan, 6 weeks")).firstMatch
        XCTAssertTrue(cardButton.waitForExistence(timeout: 10), "Plan card should be exposed as a button")

        let name = app.descendants(matching: .any)["myPlan.planCard"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        assertExists("rehabPlan.editButton", timeout: 10)
        captureScreenshot(name: "MyPlan-CardOpensPlan")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/MyPlanTabUITests/testPlanCard_isExposedAsButtonAndOpensPlan` → `failed` at "Plan card should be exposed as a button".

- [ ] **Step 3: Expose the open action on the info block and identify the name**

In `MyPlanTab.swift`, the `HStack(alignment: .top) { … }` at lines 157-197 (the plan info row; it contains no buttons) gets these modifiers after its closing brace, and the plan-name `Text` at 164-170 gets the identifier:

```swift
                        Text(plan.planName)
                            .font(AppFonts.sectionTitle)
                            .textCase(.uppercase)
                            .kerning(0.3)
                            .foregroundColor(AppColors.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("myPlan.planCard")
```

```swift
                }   // end HStack(alignment: .top)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(plan.planName), \(plan.totalWeeks) weeks")
                .accessibilityHint("Opens plan")
                .accessibilityAction { route = .detail(plan.id) }
```

Do **not** wrap the card in a `Button` and do not put a label or identifier on the outer `VStack`: either would swallow the inner `myPlan.startWorkoutButton` that `GuidedWorkoutUITests`, `MyPlanTabUITests` and `ShellNavigationUITests` rely on. The `.onTapGesture` at line 229 stays.

- [ ] **Step 4: Build, run the new test and the existing class**

Build → succeeded. Run `-only-testing:COILUITests/MyPlanTabUITests` (whole class). Expected: all `passed`, including the pre-existing `testInjuryPlans_ShowWithSeededData` (proves `myPlan.startWorkoutButton` is still addressable).

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/MyPlanTab.swift ios/PT-Helper/COILUITests/MyPlanTabUITests.swift
git commit -m "Expose the My Plan card's open action to VoiceOver

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Home week strip reads one element per day

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/HomeTab.swift:123-165`
- Create: `ios/PT-Helper/COILUITests/HomeTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

```swift
import XCTest

/// Covers the Home tab (week strip + today's program).
final class HomeTabUITests: UITestBase {

    @MainActor
    func testWeekStrip_announcesEachDayWithCompletionState() throws {
        // Home is the launch tab. Each day cell was three separate elements ("TUE", "8",
        // an unlabeled dot); it should be one element ending in its completion state.
        let predicate = NSPredicate(format: "label ENDSWITH %@ OR label ENDSWITH %@",
                                    "no workout", "workout completed")
        let cells = app.descendants(matching: .any).matching(predicate)
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "Day cells should be labelled")
        XCTAssertEqual(cells.count, 7, "One combined element per day in the 7-day strip")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/HomeTabUITests/testWeekStrip_announcesEachDayWithCompletionState` → `failed` ("Day cells should be labelled").

- [ ] **Step 3: Combine each `DayCell` into one labelled element**

In `HomeTab.swift`, add a full-weekday formatter next to the existing ones (line 128-133):

```swift
    private static let fullDayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()
```

and append these modifiers to the `DayCell` body's outer `VStack` (after the `.overlay(...)` at line 157-163):

```swift
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(Self.fullDayFmt.string(from: date)) \(Self.numFmt.string(from: date)), "
            + (isCompleted ? "workout completed" : "no workout")
        )
```

- [ ] **Step 4: Build and run the test** → succeeded, `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/HomeTab.swift ios/PT-Helper/COILUITests/HomeTabUITests.swift
git commit -m "Read each Home week-strip day as one element with its completion state

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Rehab plan exercise cards get their own identifiers

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/RehabPlanView.swift:606-628, 630-641`
- Test: `ios/PT-Helper/COILUITests/MyPlanTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `MyPlanTabUITests`:

```swift
    @MainActor
    func testRehabPlan_exerciseCardsHaveUniqueIdentifiers() throws {
        tapTab("Plan")
        let name = app.descendants(matching: .any)["myPlan.planCard"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Seeded Knee plan has three exercises.
        assertExists("rehabPlan.exerciseName.0", timeout: 10)
        assertExists("rehabPlan.exerciseName.2")

        // The whole card used to inherit the swap button's identifier, so the id
        // matched six elements (three cards + three buttons) instead of three.
        let swapButtons = app.buttons.matching(identifier: "rehabPlan.swapExerciseButton")
        XCTAssertEqual(swapButtons.count, 3, "Only the three swap buttons should carry the swap identifier")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/MyPlanTabUITests/testRehabPlan_exerciseCardsHaveUniqueIdentifiers` → `failed` at `rehabPlan.exerciseName.0`.

- [ ] **Step 3: Enumerate the exercises and identify the name leaf**

`exerciseList(for:)` (lines 606-628) becomes:

```swift
    private func exerciseList(for plan: RehabPlan) -> some View {
        VStack(spacing: AppSpacing.lg) {
            // Verification summary banner (only show if verification has been performed)
            if !viewModel.exerciseVerifications.isEmpty {
                verificationSummaryBanner
            }

            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                    exerciseCard(for: exercise, index: index)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(action: {
                        exerciseToSwap = exercise
                        showSwapSheet = true
                    }) {
                        Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
        }
    }
```

`exerciseCard(for:)` (line 630) gains an `index` parameter and the name `Text` (638-641) gets the identifier:

```swift
    private func exerciseCard(for exercise: RehabExercise, index: Int) -> some View {
        HStack(spacing: AppSpacing.lg) {
            // Compact exercise image with SF Symbol fallback
            ExerciseImageView(exercise: exercise, isCompact: true)

            // Exercise info
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                HStack(spacing: AppSpacing.xs) {
                    Text(exercise.name)
                        .font(AppFonts.bodySemiBold)
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(2)
                        .accessibilityIdentifier("rehabPlan.exerciseName.\(index)")
```
(the rest of the function body is unchanged).

- [ ] **Step 4: Build and run the test**

Build → succeeded; test → `passed`. **If the swap count is still 6:** the `NavigationLink` is still inheriting the inner button's identifier. Add `.accessibilityIdentifier("rehabPlan.exerciseCard.\(index)")` directly on the `NavigationLink` (after `.buttonStyle(.plain)`), rebuild, and confirm both that the count is now 3 **and** that `swapButtons.firstMatch.isHittable` is true (the swap button must remain individually addressable — see the container-id note in the project memory). Record which variant was needed in the commit body.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/RehabPlanView.swift ios/PT-Helper/COILUITests/MyPlanTabUITests.swift
git commit -m "Give rehab-plan exercise cards their own accessibility identifiers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: PR F1

- [ ] **Step 1: Full unit run**

Run: `xcodebuild test … -only-testing:COILTests` (UnitPlan default). Expected: `** TEST SUCCEEDED **`, 0 failures (baseline 1311 tests).

- [ ] **Step 2: Run every UI class touched**

Run `-only-testing:COILUITests/SettingsUITests -only-testing:COILUITests/OnboardingUITests -only-testing:COILUITests/ProgressTabUITests -only-testing:COILUITests/MyPlanTabUITests -only-testing:COILUITests/HomeTabUITests -only-testing:COILUITests/GuidedWorkoutUITests -only-testing:COILUITests/ShellNavigationUITests`. Expected: all `passed`.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin ux/foundation-fixes
gh pr create --base ux/design-specs --title "Foundation fixes F1: accessibility labels and a11y P1s" --body "$(cat <<'EOF'
Implements PR F1 of docs/superpowers/specs/2026-09-14-foundation-fixes-design.md.

- Settings toggles and reminder-time picker, onboarding Terms checkbox, height menus and DOB picker are named for VoiceOver (audit P0s)
- Streak badge, My Plan card, Home week strip and rehab-plan exercise cards get descriptive labels / unique identifiers (audit P1s)
- Seven new XCUI assertions; UnitPlan green

Base is ux/design-specs (docs); retarget to main once that merges.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## PR F2 — Functional P1s

### Task 8: `RehabExercise.repsText` and `dosageText`

**Files:**
- Modify: `ios/PT-Helper/COIL/Models/RehabPlan.swift` (append after line 123)
- Create: `ios/PT-Helper/COILTests/RehabExerciseDosageTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import COIL

final class RehabExerciseDosageTests: XCTestCase {

    private func exercise(sets: Int, reps: String) -> RehabExercise {
        RehabExercise(
            id: UUID(), name: "Wall Sits", targetArea: "Knee", description: "d",
            sets: sets, reps: reps, restSeconds: 30, difficulty: .beginner,
            demonstrationIcon: "figure.cooldown", tips: [], contraindications: []
        )
    }

    func testRepsText_integerReps_appendsReps() {
        XCTAssertEqual(exercise(sets: 3, reps: "12").repsText, "12 reps")
    }

    func testRepsText_singleRep_singular() {
        XCTAssertEqual(exercise(sets: 3, reps: "1").repsText, "1 rep")
    }

    func testRepsText_timedReps_verbatim() {
        XCTAssertEqual(exercise(sets: 3, reps: "30 seconds").repsText, "30 seconds")
    }

    func testRepsText_freeText_verbatim() {
        XCTAssertEqual(exercise(sets: 2, reps: "10 each side").repsText, "10 each side")
    }

    func testRepsText_paddedInteger_trimmed() {
        XCTAssertEqual(exercise(sets: 3, reps: " 15 ").repsText, "15 reps")
    }

    func testDosageText_numeric() {
        XCTAssertEqual(exercise(sets: 3, reps: "12").dosageText, "3 sets \u{00D7} 12 reps")
    }

    func testDosageText_timed() {
        XCTAssertEqual(exercise(sets: 3, reps: "30 seconds").dosageText, "3 sets \u{00D7} 30 seconds")
    }

    func testDosageText_singleSet_singular() {
        XCTAssertEqual(exercise(sets: 1, reps: "12").dosageText, "1 set \u{00D7} 12 reps")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:COILTests/RehabExerciseDosageTests`. Expected: build error `value of type 'RehabExercise' has no member 'repsText'`.

- [ ] **Step 3: Implement**

Append to `ios/PT-Helper/COIL/Models/RehabPlan.swift`:

```swift

// MARK: - Dosage copy

extension RehabExercise {
    /// "12 reps" when `reps` is an integer, otherwise the value verbatim ("30 seconds",
    /// "10 each side"). Timed exercises used to render as "30 seconds reps".
    var repsText: String {
        let trimmed = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        if let count = Int(trimmed) {
            return count == 1 ? "1 rep" : "\(count) reps"
        }
        return trimmed
    }

    /// "3 sets × 12 reps" — the single dosage string every screen uses.
    var dosageText: String {
        let setsText = sets == 1 ? "1 set" : "\(sets) sets"
        return "\(setsText) \u{00D7} \(repsText)"
    }
}
```

- [ ] **Step 4: Run the tests** → 8 `passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Models/RehabPlan.swift ios/PT-Helper/COILTests/RehabExerciseDosageTests.swift
git commit -m "Add RehabExercise.dosageText so timed exercises stop reading as \"30 seconds reps\"

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Use `dosageText` on Home, Guided Workout and Rehab Plan

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/HomeTab.swift:298`, `ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift:229, 463`, `ios/PT-Helper/COIL/Views/RehabPlanView.swift:665`, `ios/PT-Helper/COIL/Views/WellnessPlanView.swift:133-135`, `ios/PT-Helper/COIL/Views/ExerciseSwapSheet.swift:266`, `ios/PT-Helper/COIL/Views/EditRehabPlanView.swift:31`
- Test: `ios/PT-Helper/COILUITests/GuidedWorkoutUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `GuidedWorkoutUITests` (`navigateToWorkout()` is a private helper in this class):

```swift
    @MainActor
    func testInfoBadges_useDosageText() throws {
        navigateToWorkout()
        assertExists("workout.exerciseName", timeout: 10)

        // Seeded "Wall Sits" has reps "30 seconds"; the badge read "30 seconds reps".
        XCTAssertTrue(staticText("30 seconds").waitForExistence(timeout: 5))
        XCTAssertFalse(staticText("30 seconds reps").exists)
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/GuidedWorkoutUITests/testInfoBadges_useDosageText` → `failed`.

- [ ] **Step 3: Swap the seven call sites**

`HomeTab.swift:298` (`Text("\(exercise.sets) sets · \(exercise.reps) reps")`):
```swift
                Text(exercise.dosageText)
```
`GuidedWorkoutView.swift:229`:
```swift
                            infoBadge(icon: "repeat", text: exercise.repsText)
```
`GuidedWorkoutView.swift:463`:
```swift
                upNextCard(exercise: next, subtitle: next.dosageText)
```
`RehabPlanView.swift:665` (`Text("\(exercise.sets) sets \u{00D7} \(exercise.reps)")`):
```swift
                    Text(exercise.dosageText)
```
`WellnessPlanView.swift:133-135` — the three children `Text("\(exercise.sets) sets")`, `Text("·")`, `Text("\(exercise.reps) reps")` collapse into one, so the row reads "3 sets × 12 reps · Beginner":
```swift
                    HStack(spacing: AppSpacing.sm) {
                        Text(exercise.dosageText)
                        Text("·")
                        Text(exercise.difficulty.rawValue.capitalized)
                            .foregroundColor(difficultyColor(exercise.difficulty))
                    }
```
`ExerciseSwapSheet.swift:266` (`Text("\(substitute.sets) sets \u{00D7} \(substitute.reps)")`):
```swift
                        Text(substitute.dosageText)
```
`EditRehabPlanView.swift:31`:
```swift
                                    Text("\(exercise.dosageText) \u{2022} \(exercise.difficulty.rawValue.capitalized)")
```

Then this gate must print nothing:
```bash
grep -rnE '\.sets\) sets|\.reps\) reps' ios/PT-Helper/COIL/Views
```

- [ ] **Step 4: Build and run the test** → succeeded, `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/HomeTab.swift ios/PT-Helper/COIL/Views/GuidedWorkoutView.swift ios/PT-Helper/COIL/Views/RehabPlanView.swift ios/PT-Helper/COIL/Views/WellnessPlanView.swift ios/PT-Helper/COIL/Views/ExerciseSwapSheet.swift ios/PT-Helper/COIL/Views/EditRehabPlanView.swift ios/PT-Helper/COILUITests/GuidedWorkoutUITests.swift
git commit -m "Render exercise dosage through dosageText on every screen that shows sets and reps

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: `RehabPlan.status`

**Files:**
- Modify: `ios/PT-Helper/COIL/Models/RehabPlan.swift:39-44` (inside `struct RehabPlan`)
- Create: `ios/PT-Helper/COILTests/RehabPlanStatusTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import COIL

final class RehabPlanStatusTests: XCTestCase {

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    func testStatus_noStartDate_notStarted() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: nil)
        XCTAssertEqual(plan.status, .notStarted)
    }

    func testStatus_startedToday_activeWeekOne() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: daysAgo(0))
        XCTAssertEqual(plan.status, .active(week: 1))
    }

    func testStatus_startedTenDaysAgo_activeWeekTwo() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: daysAgo(10))
        XCTAssertEqual(plan.status, .active(week: 2))
    }

    func testStatus_durationElapsed_completed() {
        let plan = TestFixtures.makePlan(totalWeeks: 6, startDate: daysAgo(42))
        XCTAssertEqual(plan.status, .completed)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:COILTests/RehabPlanStatusTests` → build error `has no member 'status'`.

- [ ] **Step 3: Implement**

Insert after `isCompleted` (line 44) inside `struct RehabPlan`:

```swift

    /// Lifecycle state derived from `startDate`: drives the My Plan badge and Home's plan choice.
    enum PlanStatus: Equatable {
        case notStarted
        case active(week: Int)
        case completed
    }

    var status: PlanStatus {
        guard startDate != nil else { return .notStarted }
        if isCompleted { return .completed }
        return .active(week: currentWeek ?? 1)
    }
```

- [ ] **Step 4: Run the tests** → 4 `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Models/RehabPlan.swift ios/PT-Helper/COILTests/RehabPlanStatusTests.swift
git commit -m "Add RehabPlan.status (not started / active week N / completed)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 11: `HomeProgramLogic`

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/HomeTab.swift` (insert after `HomeStripLogic`, line 11)
- Create: `ios/PT-Helper/COILTests/HomeProgramLogicTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import COIL

final class HomeProgramLogicTests: XCTestCase {

    /// Fixed UTC Gregorian calendar so weekday maths does not depend on the runner.
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var monday: Date { date(2026, 9, 14) }   // 2026-09-14 is a Monday
    private var sundayDate: Date { date(2026, 9, 13) }
    private var saturday: Date { date(2026, 9, 12) }

    private let wallSits = TestFixtures.makeExercise(name: "Wall Sits")
    private let legRaises = TestFixtures.makeExercise(name: "Straight Leg Raises")
    private let clamshells = TestFixtures.makeExercise(name: "Clamshells", targetArea: "Hip")

    /// Mirrors TestDataSeeder's Knee plan: names, Sun/Tue/Thu (index 0 = Sunday).
    private func seededPlan() -> RehabPlan {
        TestFixtures.makePlan(
            exercises: [wallSits, legRaises, clamshells],
            weeklySchedule: [["Wall Sits", "Straight Leg Raises"], [], ["Clamshells"], [], ["Wall Sits"], [], []]
        )
    }

    func testTodaysExercises_restDay_empty() {
        XCTAssertEqual(HomeProgramLogic.todaysExercises(for: seededPlan(), on: monday, calendar: calendar)?.map(\.name), [])
    }

    func testTodaysExercises_scheduledDay_matchesByName() {
        let result = HomeProgramLogic.todaysExercises(for: seededPlan(), on: sundayDate, calendar: calendar)
        XCTAssertEqual(result?.map(\.name), ["Wall Sits", "Straight Leg Raises"])
    }

    func testTodaysExercises_matchesByIdCaseInsensitively() {
        let plan = TestFixtures.makePlan(
            exercises: [wallSits, clamshells],
            weeklySchedule: [[clamshells.id.uuidString.lowercased()], [], [], [], [], [], []]
        )
        XCTAssertEqual(HomeProgramLogic.todaysExercises(for: plan, on: sundayDate, calendar: calendar)?.map(\.name), ["Clamshells"])
    }

    func testTodaysExercises_emptySchedule_nil() {
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: Array(repeating: [], count: 7))
        XCTAssertNil(HomeProgramLogic.todaysExercises(for: plan, on: monday, calendar: calendar))
    }

    func testTodaysExercises_malformedScheduleLength_nil() {
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: [["Wall Sits"], [], []])
        XCTAssertNil(HomeProgramLogic.todaysExercises(for: plan, on: monday, calendar: calendar))
    }

    /// After an exercise swap the schedule still holds the OLD exercise id (ExerciseSwapViewModel
    /// never rewrites weeklySchedule), so a scheduled day can resolve to nothing. That must
    /// fall back to "show everything" (nil), never to a false rest day ([]).
    func testTodaysExercises_entriesResolveToNothing_fallsBackToNil() {
        let staleId = UUID().uuidString
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: [[staleId], [], [], [], [], [], []])
        XCTAssertNil(HomeProgramLogic.todaysExercises(for: plan, on: sundayDate, calendar: calendar))
    }

    func testNextSession_unresolvedEntries_countsRawEntries() {
        let staleId = UUID().uuidString
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: [[], [staleId, staleId], [], [], [], [], []])
        let next = HomeProgramLogic.nextSession(for: plan, after: sundayDate, calendar: calendar)
        XCTAssertEqual(next?.weekdayName, "Mon")
        XCTAssertEqual(next?.exerciseCount, 2)
    }

    func testNextSession_fromMonday_isTuesdayWithOneExercise() {
        let next = HomeProgramLogic.nextSession(for: seededPlan(), after: monday, calendar: calendar)
        XCTAssertEqual(next?.weekdayName, "Tue")
        XCTAssertEqual(next?.exerciseCount, 1)
    }

    func testNextSession_fromSaturday_wrapsToSunday() {
        let next = HomeProgramLogic.nextSession(for: seededPlan(), after: saturday, calendar: calendar)
        XCTAssertEqual(next?.weekdayName, "Sun")
        XCTAssertEqual(next?.exerciseCount, 2)
    }

    func testNextSession_noScheduledDays_nil() {
        let plan = TestFixtures.makePlan(exercises: [wallSits], weeklySchedule: Array(repeating: [], count: 7))
        XCTAssertNil(HomeProgramLogic.nextSession(for: plan, after: monday, calendar: calendar))
    }

    func testPreferredPlan_prefersActiveRehabPlan() {
        let notStarted = TestFixtures.makePlan(name: "Later", startDate: nil)
        let active = TestFixtures.makePlan(name: "Now", startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()))
        XCTAssertEqual(HomeProgramLogic.preferredPlan(from: [notStarted, active])?.planName, "Now")
    }

    func testPreferredPlan_noActive_firstRehabPlan() {
        let a = TestFixtures.makePlan(name: "A", startDate: nil)
        let b = TestFixtures.makePlan(name: "B", startDate: nil)
        XCTAssertEqual(HomeProgramLogic.preferredPlan(from: [a, b])?.planName, "A")
    }

    func testPreferredPlan_empty_nil() {
        XCTAssertNil(HomeProgramLogic.preferredPlan(from: []))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `-only-testing:COILTests/HomeProgramLogicTests` → build error `cannot find 'HomeProgramLogic' in scope`.

- [ ] **Step 3: Implement**

Insert into `HomeTab.swift` directly after the `HomeStripLogic` enum (after line 11):

```swift

/// Pure schedule logic for the Home tab's "Today's Program".
/// `weeklySchedule` is indexed 0 = Sunday … 6 = Saturday (see `RehabPlanView.weeklyCalendar`
/// and `RehabPlanViewModel.createWeeklySchedule`); entries are exercise ids (generator) or
/// exercise names (test seeder), so both are accepted, case-insensitively.
enum HomeProgramLogic {

    /// nil = no usable schedule, OR today's entries resolve to no current exercise (e.g. the
    ///       schedule still names an exercise id that was swapped out) → show every exercise;
    /// []  = a scheduled rest day (today's entry is genuinely empty);
    /// otherwise today's exercises in plan order.
    static func todaysExercises(for plan: RehabPlan, on date: Date,
                                calendar: Calendar = .current) -> [RehabExercise]? {
        let schedule = plan.weeklySchedule
        guard schedule.count == 7, schedule.contains(where: { !$0.isEmpty }) else { return nil }
        let dayIndex = calendar.component(.weekday, from: date) - 1
        let entries = schedule[dayIndex]
        if entries.isEmpty { return [] }
        let resolved = exercises(in: plan, matching: entries)
        return resolved.isEmpty ? nil : resolved
    }

    /// The next scheduled day strictly after `date`, within the following 7 days. Counts
    /// resolved exercises, falling back to the raw entry count when none resolve.
    static func nextSession(for plan: RehabPlan, after date: Date,
                            calendar: Calendar = .current) -> (weekdayName: String, exerciseCount: Int)? {
        let schedule = plan.weeklySchedule
        guard schedule.count == 7 else { return nil }
        let today = calendar.component(.weekday, from: date) - 1
        for offset in 1...7 {
            let index = (today + offset) % 7
            let entries = schedule[index]
            if entries.isEmpty { continue }
            let resolved = exercises(in: plan, matching: entries).count
            return (calendar.shortWeekdaySymbols[index], resolved > 0 ? resolved : entries.count)
        }
        return nil
    }

    /// The plan Home should show: the first active rehab plan, else the first rehab plan, else any plan.
    static func preferredPlan(from plans: [RehabPlan]) -> RehabPlan? {
        let rehab = plans.filter { $0.planType == .rehab }
        if let active = rehab.first(where: { isActive($0) }) { return active }
        return rehab.first ?? plans.first
    }

    private static func isActive(_ plan: RehabPlan) -> Bool {
        if case .active = plan.status { return true }
        return false
    }

    private static func exercises(in plan: RehabPlan, matching entries: [String]) -> [RehabExercise] {
        let keys = Set(entries.map { $0.lowercased() })
        return plan.exercises.filter {
            keys.contains($0.id.uuidString.lowercased()) || keys.contains($0.name.lowercased())
        }
    }
}
```

- [ ] **Step 4: Run the tests** → 13 `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/HomeTab.swift ios/PT-Helper/COILTests/HomeProgramLogicTests.swift
git commit -m "Add HomeProgramLogic for today's exercises, next session and preferred plan

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 12: Real plan status on My Plan; Home prefers the active plan

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/MyPlanTab.swift:159-162`, `ios/PT-Helper/COIL/Views/HomeTab.swift:22-25`
- Test: `ios/PT-Helper/COILUITests/MyPlanTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `MyPlanTabUITests`:

```swift
    @MainActor
    func testPlanCards_showRealStatus() throws {
        tapTab("Plan")
        // The card's info block is ONE combined accessibility element (Task 4), so its
        // children are not queryable as static texts — assert on the combined label.
        // Seeded "Shoulder Mobility Plan" has no start date; it used to say ACTIVE.
        let notStarted = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Shoulder Mobility Plan, 4 weeks, Not started")).firstMatch
        XCTAssertTrue(notStarted.waitForExistence(timeout: 10),
                      "A plan without a start date should read Not started")
        let active = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Knee Rehab Plan, 6 weeks, Active")).firstMatch
        XCTAssertTrue(active.waitForExistence(timeout: 5), "The started plan should read Active")
    }
```

- [ ] **Step 2: Run it to verify it fails** → `failed` (the Task 4 label ends at "…weeks" with no status).

- [ ] **Step 3: Implement**

`MyPlanTab.swift`: the accessibility label added in Task 4 on the info `HStack` now includes the status, so VoiceOver hears it even though the badge text is inside the combined element:
```swift
                .accessibilityLabel("\(plan.planName), \(plan.totalWeeks) weeks, \(statusText(for: plan))")
```
with this helper inside `struct MyPlanTab`:
```swift
    private func statusText(for plan: RehabPlan) -> String {
        switch plan.status {
        case .active(let week): return "Active, week \(week)"
        case .notStarted: return "Not started"
        case .completed: return "Completed"
        }
    }
```

Lines 159-162 become:
```swift
                        HStack(spacing: AppSpacing.sm) {
                            statusBadge(for: plan)
                            Spacer()
                        }
```
and add this helper inside `struct MyPlanTab` (after `planCard`):
```swift
    @ViewBuilder
    private func statusBadge(for plan: RehabPlan) -> some View {
        switch plan.status {
        case .active:
            CoilBadge(text: "Active")
        case .notStarted:
            Text("Not started")
                .font(AppFonts.captionMedium)
                .foregroundColor(AppColors.secondaryText)
        case .completed:
            Text("Completed")
                .font(AppFonts.captionMedium)
                .foregroundColor(AppColors.success)
        }
    }
```

`HomeTab.swift` lines 22-25 become:
```swift
    private var activePlan: RehabPlan? {
        HomeProgramLogic.preferredPlan(from: savedPlansViewModel.rehabPlans)
    }
```

- [ ] **Step 4: Build and run** the new test plus `MyPlanTabUITests` whole class → all `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/MyPlanTab.swift ios/PT-Helper/COIL/Views/HomeTab.swift ios/PT-Helper/COILUITests/MyPlanTabUITests.swift
git commit -m "Show each plan's real status instead of a hardcoded ACTIVE badge

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 13: Home shows today's exercises and a rest-day card

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/HomeTab.swift:207-281`
- Test: `ios/PT-Helper/COILUITests/HomeTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `HomeTabUITests`:

```swift
    @MainActor
    func testStartWorkoutButton_existsOnRestAndTrainingDays() throws {
        // The seeded Knee plan trains Sun/Tue/Thu. On a rest day the CTA moves into the
        // rest-day card as "Start a workout anyway" but keeps the same identifier, so
        // this assertion holds whichever weekday the suite runs on.
        assertExists("home.startWorkoutButton", timeout: 10)
        let weekday = Calendar.current.component(.weekday, from: Date())   // 1 = Sunday
        let isTrainingDay = [1, 3, 5].contains(weekday)
        if isTrainingDay {
            let todayCount = app.staticTexts.matching(
                NSPredicate(format: "label ENDSWITH %@", "today")).firstMatch   // "N exercises today"
            XCTAssertTrue(todayCount.waitForExistence(timeout: 5), "Training day should show today's exercise count")
        } else {
            XCTAssertTrue(staticText("Rest day").waitForExistence(timeout: 5), "Rest day should show the rest-day card")
        }
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/HomeTabUITests/testStartWorkoutButton_existsOnRestAndTrainingDays`. Expected on a rest weekday: `failed` at "Rest day"; on a training weekday: `failed` at "exercises today". (Both branches fail before the change because neither string exists yet.)

- [ ] **Step 3: Implement**

Replace `ProgramDayView` (lines 207-281) with:

```swift
struct ProgramDayView: View {
    let plan: RehabPlan?

    @EnvironmentObject private var tabSelection: TabSelection

    var body: some View {
        if let plan = plan {
            let todays = HomeProgramLogic.todaysExercises(for: plan, on: Date())
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                CoilDividerHeader(title: "Today's Program")

                // Plan name badge — only a started plan is "Active" (preferredPlan can
                // fall back to a not-started plan when nothing has been started yet).
                HStack(spacing: AppSpacing.sm) {
                    if case .active = plan.status {
                        CoilBadge(text: "Active")
                    }
                    Text(plan.planName)
                        .font(AppFonts.smallSemiBold)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                    Spacer()
                    Text(countLabel(plan: plan, todays: todays))
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.mutedText)
                }

                if let todays, todays.isEmpty {
                    RestDayCard(plan: plan, next: HomeProgramLogic.nextSession(for: plan, after: Date()))
                } else {
                    let shown = todays ?? plan.exercises

                    // Exercise rows
                    ForEach(shown.prefix(8)) { exercise in
                        ExerciseProgramRow(exercise: exercise)
                    }

                    if shown.count > 8 {
                        Text("+ \(shown.count - 8) more exercises")
                            .font(AppFonts.caption)
                            .foregroundColor(AppColors.mutedText)
                            .padding(.leading, AppSpacing.xs)
                    }

                    // Start workout CTA
                    NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Start Guided Workout")
                                .font(AppFonts.cardTitle)
                                .textCase(.uppercase)
                                .kerning(1.0)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.ctaBackground)
                        .clipShape(Capsule())
                        .shadow(color: AppColors.ctaBackground.opacity(0.30), radius: 8, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xs)
                    .accessibilityIdentifier("home.startWorkoutButton")
                }
            }
        } else {
            noPlanState
        }
    }

    private func countLabel(plan: RehabPlan, todays: [RehabExercise]?) -> String {
        guard let todays else { return "\(plan.exercises.count) exercises" }
        if todays.isEmpty { return "Rest day" }
        return todays.count == 1 ? "1 exercise today" : "\(todays.count) exercises today"
    }

    private var noPlanState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: AppSpacing.xxl)
            EmptyStateView(
                icon: "list.clipboard",
                title: "No Active Program",
                subtitle: "Complete an assessment to get a personalized rehab program",
                actionTitle: "Start Assessment",
                action: { tabSelection.assessmentRequest = .gateway }
            )
            Spacer(minLength: AppSpacing.xl)
        }
    }
}

// MARK: - Rest Day Card

/// Shown when today's `weeklySchedule` entry is empty. Keeps the Start identifier so
/// the workout is one tap away on every day of the week.
private struct RestDayCard: View {
    let plan: RehabPlan
    let next: (weekdayName: String, exerciseCount: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Rest day")
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.primaryText)

            if let next {
                Text("Next session: \(next.weekdayName) · \(next.exerciseCount) \(next.exerciseCount == 1 ? "exercise" : "exercises")")
                    .font(AppFonts.small)
                    .foregroundColor(AppColors.secondaryText)
            }

            NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                Text("Start a workout anyway")
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("home.startWorkoutButton")
        }
        .cardStyle()
    }
}
```

- [ ] **Step 4: Build and run** the test → succeeded, `passed`. Then run `-only-testing:COILUITests/HomeTabUITests` (both tests) → `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/HomeTab.swift ios/PT-Helper/COILUITests/HomeTabUITests.swift
git commit -m "Make Home's Today's Program follow the weekly schedule with a rest-day card

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 14: PDF share appears on saved plans

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/RehabPlanView.swift:296`
- Test: `ios/PT-Helper/COILUITests/MyPlanTabUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `MyPlanTabUITests`:

```swift
    @MainActor
    func testOpenSavedPlan_showsShareButton() throws {
        tapTab("Plan")
        let name = app.descendants(matching: .any)["myPlan.planCard"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // cachedPDFData was only generated on a plan-id *change*, which never fires for
        // a plan set in init(existingPlan:), so the ShareLink never appeared.
        assertExists("rehabPlan.editButton", timeout: 10)
        assertExists("rehabPlan.shareButton", timeout: 5)
    }
```

- [ ] **Step 2: Run it to verify it fails** → `failed` at `rehabPlan.shareButton`.

- [ ] **Step 3: Implement**

`RehabPlanView.swift` line 296:
```swift
        .onChange(of: viewModel.rehabPlan?.id, initial: true) { _, _ in
```
(the body at 297-301 is unchanged).

- [ ] **Step 4: Build and run the test** → `passed`.

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/RehabPlanView.swift ios/PT-Helper/COILUITests/MyPlanTabUITests.swift
git commit -m "Generate the plan PDF on first appearance so saved plans can be shared

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 15: `SettingsView` is presentation-agnostic

**Files:**
- Modify: `ios/PT-Helper/COIL/Views/SettingsView.swift:6-9, 31-33, 74-80, 161`, `ios/PT-Helper/COIL/Views/ProgressTab.swift:25-35`
- Test: `ios/PT-Helper/COILUITests/ShellNavigationUITests.swift`

- [ ] **Step 1: Write the failing UI test**

Append inside `ShellNavigationUITests`:

```swift
    @MainActor
    func testProfileTab_hasNoDoneButton() throws {
        tapTab("Profile")
        XCTAssertTrue(app.descendants(matching: .any)["settings.signOutButton"].waitForExistence(timeout: 10))
        // As a tab root there is nothing to dismiss; the inert Done button must go.
        XCTAssertFalse(app.buttons["Done"].exists, "Profile tab should not show a Done button")
    }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `-only-testing:COILUITests/ShellNavigationUITests/testProfileTab_hasNoDoneButton` → `failed`.

- [ ] **Step 3: Implement**

`SettingsView.swift`:

Insert the new property directly after the existing `var onEditProfile: () -> Void` (line 8); lines 7-8 already exist and are shown only for position:
```swift
    let userName: String                       // existing
    var onEditProfile: () -> Void              // existing
    /// True only when a sheet hosts this view; the tab host has nothing to dismiss.
    var showsDoneButton: Bool = false          // NEW
```

Remove the `NavigationStack {` opener at line 32 and its matching closing `}` at line 161 (the one immediately before `.trackScreen("Settings")`), de-indenting the block by one level. The `ZStack` becomes the root of `body`, and every modifier previously attached to the `NavigationStack` (`.navigationTitle`, `.toolbar`, the `.confirmationDialog`/`.alert` chain, `.overlay`) now attaches to the `ZStack` — keep them in the same order.

Toolbar (lines 76-80) becomes:
```swift
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
            }
```

`ProgressTab.swift` lines 25-35 become:
```swift
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView(
                    userName: UserProfileService.shared.profile?.firstName ?? "User",
                    onEditProfile: {
                        showSettings = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showProfileEdit = true
                        }
                    },
                    showsDoneButton: true
                )
            }
        }
```

`MainTabView.swift` `ProfileTab` (lines 203-218) needs no change: its `NavigationStack` now supplies the bar and the default `showsDoneButton` is false.

- [ ] **Step 4: Build and run**

Build → succeeded. Run `-only-testing:COILUITests/ShellNavigationUITests -only-testing:COILUITests/SettingsUITests` → all `passed` (the gear path still shows Done and dismisses; the Profile path shows none).

- [ ] **Step 5: Commit**

```bash
git add ios/PT-Helper/COIL/Views/SettingsView.swift ios/PT-Helper/COIL/Views/ProgressTab.swift ios/PT-Helper/COILUITests/ShellNavigationUITests.swift
git commit -m "Let the host own SettingsView's navigation stack and Done button

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 16: PR F2

- [ ] **Step 1: Full unit run** → `-only-testing:COILTests` → `** TEST SUCCEEDED **` (baseline 1311 + 25 new).

- [ ] **Step 2: FullPlan** (nightly gate, includes collision + UI tests; 300 s timeouts):

```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj -scheme COIL -testPlan FullPlan \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath /tmp/coil-dd-foundation 2>&1 | grep -E "failed|\*\* TEST"
```
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Manual checks on the simulator** (launch with `--uitesting --skip-onboarding --seed-mock-data`): Home shows a rest-day card or "N exercises today" as appropriate; My Plan shows ACTIVE on Knee and "Not started" on Shoulder; the Knee plan shows the share icon; the workout badge reads "30 seconds"; Profile tab has no Done. Attach screenshots to the PR.

- [ ] **Step 4: Push and open the PR**

```bash
git push
gh pr create --base ux/design-specs --title "Foundation fixes F2: functional P1s" --body "$(cat <<'EOF'
Implements PR F2 of docs/superpowers/specs/2026-09-14-foundation-fixes-design.md.

- RehabExercise.dosageText / repsText replace "30 seconds reps" on Home, the workout, the plan, the wellness plan, the swap sheet and the plan editor
- RehabPlan.status drives the My Plan badge (Active / Not started / Completed); Home prefers the active plan
- Home's Today's Program follows weeklySchedule (index 0 = Sunday) with a rest-day card that keeps home.startWorkoutButton; a day whose entries no longer resolve (swapped exercise) falls back to showing everything
- Saved plans generate their PDF on first appearance so the share button exists
- SettingsView no longer nests a NavigationStack; Done shows only when sheet-hosted

25 new unit tests (dosage, status, HomeProgramLogic) + 4 UI tests; UnitPlan and FullPlan green.
Stacked on the F1 PR; retarget to main once ux/design-specs merges.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** F1 items 1-10 → Tasks 1-6 (items 1-3 Task 1; 4-6 Task 2; 7 Task 3; 8 Task 4; 9 Task 5; 10 Task 6). F2.1 → Tasks 8-9; F2.2 → Tasks 10, 12; F2.3 → Tasks 11, 13; F2.4 → Task 14; F2.5 → Task 15. Verification section → Tasks 7, 16.
- **Type consistency:** `HomeProgramLogic.todaysExercises(for:on:calendar:)`, `nextSession(for:after:calendar:)` returning `(weekdayName: String, exerciseCount: Int)?`, `preferredPlan(from:)`; `RehabPlan.PlanStatus` / `.status`; `RehabExercise.repsText` / `.dosageText`; `SettingsView.showsDoneButton`; identifiers `myPlan.planCard`, `rehabPlan.exerciseName.N`, `home.startWorkoutButton` — used identically across tasks.
- **Known judgement calls:** Task 6 documents the fallback if the NavigationLink still inherits the swap identifier; Task 13's UI test branches on the weekday because the seeded schedule is fixed to Sun/Tue/Thu.

---

## Audit Results

### Structural Review
1. FILE COMPLETENESS — FAIL. Task 9's closing gate (`grep -rn 'sets) sets' ios/PT-Helper/COIL/Views` empty) is already false: `WellnessPlanView.swift:133`, `ExerciseSwapSheet.swift:266` and `EditRehabPlanView.swift:31` render the same "N sets × reps" pattern and are not migrated. Fix: migrate those call sites in Task 9 or scope the grep. Secondary: Task 3 cites `ProgressTab.swift:171-175` (actual 170-174); Tasks 9 and 13 cite `HomeTab.swift` line numbers that drift after Tasks 5 and 11 insert code above them — anchors are identifiable by content, and R1 requires grepping before editing.
2. DEPENDENCY ORDER — PASS.
3. MISSING STEPS — WARN. Task 0's expected baseline commit (`e080c55`) is stale; `ux/design-specs` HEAD is `33ace5d`. Test-target auto-discovery confirmed (PBXFileSystemSynchronizedRootGroup).
4. API/FUNCTION VERIFICATION — PASS (fixtures, UITestBase helpers, private helpers, identifiers, `onChange(of:initial:)` on iOS 18.2 all confirmed).
5. SCOPE CALIBRATION — PASS.
6. TESTABILITY — WARN. Fail-first claims hold; the Task 9 grep is a false completion gate (see 1).
7. INTEGRATION RISK — PASS (two `SettingsView` call sites both handled; `exerciseCard(for:)` has one caller; no identifier collisions with existing tests).
OVERALL: NEEDS REVISION

### Adversarial Review
1. FATAL FLAW — `HomeProgramLogic.todaysExercises` assumes every `weeklySchedule` entry resolves to a current exercise. `ExerciseSwapViewModel.selectSubstitute` replaces `exercises[index]` with a new UUID and never updates `weeklySchedule`; on a generated (id-keyed) plan, a swapped training day resolves to zero matches and renders as "Rest day".
2. HIDDEN ASSUMPTION — that `weeklySchedule` stays in sync with `plan.exercises`. True for generated and seeded plans, false after any substitution.
3. SIMPLER ALTERNATIVE — distinguish "entries present but nothing resolves" from "entries empty": fall back to all exercises (today's behaviour) instead of the rest card.
4. WHAT BREAKS — `HomeTab.swift` `ProgramDayView`/`RestDayCard`: any user who swapped an exercise on a scheduled day sees a false rest day on the most-viewed screen.
5. FIRST HOUR TEST — Task 0's "Expected" commit is one behind the branch head.
VERDICT: REVISE BEFORE BUILDING

**Overall: NEEDS REVISION** → revised (below) and re-audited once.

### Audit revisions (applied 2026-09-14)
- Task 11: `todaysExercises` returns nil (show everything) when a day's entries are non-empty but resolve to no current exercise; `nextSession` falls back to the raw entry count. Two tests added (`testTodaysExercises_entriesResolveToNothing_fallsBackToNil`, `testNextSession_unresolvedEntries_countsRawEntries`). Spec updated with the swap/schedule gap and a follow-up.
- Task 9: `WellnessPlanView.swift:133-135`, `ExerciseSwapSheet.swift:266`, `EditRehabPlanView.swift:31` migrated to `dosageText`; the completion gate is now `grep -rnE '\.sets\) sets|\.reps\) reps' ios/PT-Helper/COIL/Views` (empty).
- Task 0: expected baseline commit corrected to `33ace5d` or later. Task 3: anchor corrected to `ProgressTab.swift:170-174`. Ground rules: line numbers are anchors as of `33ace5d`; grep before editing (R1).

### Re-audit (one pass, per protocol)
**Structural — MINOR CONCERNS.** All seven `dosageText` call sites verified against the code; the new grep gate is empty after them. WARN: drift note should also cover `RehabPlanView.swift` (Task 6 → 9) — fixed; Task 15's property snippet re-quoted existing lines — reworded as insert-after. Noted: `ProgramDayView` hardcoded "Active" badge — fixed in Task 13 (badge only when `.active`).
**Adversarial — REVISE BEFORE BUILDING.** Task 4's `.accessibilityElement(children: .combine)` on the info block hides Task 12's status text from VoiceOver and from `staticText(...)`. Fixed: Task 12 folds the status into the combined label ("Knee Rehab Plan, 6 weeks, Active, week 2" / "…, Not started") and its test asserts on `app.buttons` labels instead of static texts.

**Overall after revisions: MINOR CONCERNS** — proceed to execution.
