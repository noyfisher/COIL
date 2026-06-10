# Virtual User Validation Report — 2026-06-10

**Scope:** Follow-up pass on the 2026-06-09 run — GA4 BigQuery check, F7 second repro, F2 second repro.
**Driver:** Claude Code session via axe coordinate taps on iPhone 16 simulator (UDID 8B908AF6).
**App build:** branch `form-analysis-agent` @ a8c467e (includes F1/F3/F5/F6 fixes + SessionLogger test-host inertness).
**Backend:** pt-helper-dev (live Firestore/Auth/Storage; no AI calls were needed this run).

## Verdict

- **F7 → PROMOTED TO BUG (2/2).** Reproduced exactly; root cause identified by code reading — it is a
  **deterministic logic bug, not a race** (details below).
- **F2 → CONFIRMED BUG (2/2).** Stored analysis has no re-entry point anywhere in the 3-tab UI;
  corroborated by static code evidence.
- **GA4 BigQuery export: NOT misconfigured** — it lands the next morning ~07:50–09:25 PT and skips
  zero-event days. `events_20260609` had not landed yet at 06:40 PT; query re-run pending the table
  (see GA4 section for status).
- **Bonus: F3 fix (42c4c6f) re-verified live** — backgrounding the app uploaded the session trail
  (sessionLogs 0 → 1) with **no analysis run**, exactly as designed.

## F7 — BUG (promoted, 2/2): completing sets via Skip Rest silently ends the workout with zeroed stats

**Repro (2026-06-10, fresh install):** seeded vuser-veteran-001, signed in via `--virtual-user-token`,
started the guided workout from the seeded Knee Recovery Plan (3 exercises, Wall Sits first, 3 sets),
then rapidly: Complete Set 1 → Skip Rest → Complete Set → Skip Rest → Complete Set → (rest appeared) →
Skip Rest → **"Workout Complete!" — Duration 1m, Completed 0, Skipped 0** after touching only what the
user believes is exercise 1. Identical signature to 2026-06-09.

**Worse than the first observation:** this time the corruption reached Firestore. The live-written
workoutSessions doc has `exercisesPerformed: []` and duration 86s (the 2026-06-09 doc happened to be
written correctly). Evidence: `vuser-veteran-001/f7-workout-complete-repro2.png`, `f7_04_after_rapid.png`.

**Root cause (GuidedWorkoutViewModel.swift — read, not guessed):**
- `completeSet()` (line 123): when more sets remain it increments `currentSet` and starts an
  **inter-set** rest via `startRestTimer(seconds: interSetRest)` (line 148).
- But every rest-ending path — `skipRest()` (line 167), natural timer expiry (lines 360, 376) —
  unconditionally calls `moveToNextExercise()`, which advances `currentExerciseIndex` and resets
  `currentSet = 1` (lines 308–317).
- The model has **no notion of "rest before next set" vs "rest before next exercise."** Any rest, whether
  skipped or fully waited out, jumps to the next exercise.
- `completedExercises.append` only happens when `currentSet >= exercise.sets` (line 130) — unreachable
  for any multi-set exercise, because every rest resets the set counter. `skippedExercises` is only
  appended by the explicit Skip button. Hence **Completed 0 / Skipped 0 is the guaranteed outcome**, and
  the Nth rest (N = exercise count) triggers `finishWorkout()`.

**Implication:** this is not a rapid-tap race — *every* user doing a multi-set exercise hits it, including
patient users who wait out the rest timer. The workout flow effectively does one set per exercise and ends
early with zeroed stats. The 2026-06-09 "rapid taps" framing was a red herring; rapid taps just made the
walk through exercises 1→2→3 invisible.

**Fix sketch:** make the rest phase carry its destination (e.g. `enum RestKind { interSet, interExercise }`
or check `currentSet <= exercise.sets` on rest end): inter-set rest should return to `phase = .exercise`
on the same exercise without touching `currentExerciseIndex`; only the post-final-set rest advances.
`completedExercises.append` placement (only on the final-set branch) is then reachable again. Add a unit
test driving completeSet/skipRest through a full 3-set exercise.

## F2 — BUG (confirmed, 2/2): stored analysis result unreachable in the 3-tab UI

**Repro (2026-06-10):** seeded a stored analysis into UserDefaults via the app's own
`TestDataSeeder` path (`--uitesting --seed-mock-data` writes `dashboardLastAnalysisResult` through
`AnalysisResultStore.save`, so the payload is valid by construction — verified present in the app
container plist), then relaunched plain with the signed-in vuser-veteran-001 session and searched
**every screen of all three tabs** via accessibility-tree enumeration + scroll sweeps:

- **Assess:** Something Hurts / Improve My Life / Quick Actions (Update Health Info, Recovery Notes,
  Log Workout) — nothing.
- **My Plan:** Injury list, full Rehab Plan detail (week banner, Stay the Course, Midpoint Check-In →
  "Start Re-Assessment" = NEW assessment, exercise list, calendar), Wellness segment (empty state) — nothing.
- **Progress:** streak, pain trend + region chips, summary stats, Recovery Insights, outcome-rating
  prompt, Recent Workouts + See All, Settings sheet (Reminders / Export Debug Log / Session Events /
  legal / Update Health Info / Sign Out / Delete Account) — nothing. Notably the outcome prompt asks
  "Thinking back to the original analysis — how accurate did it turn out?" **while offering no way to
  view that analysis.**

**Static corroboration:** `AnalysisResultStore.lastResult` is read by exactly one view —
`AnalysisDashboardView` (Views/Dashboard/AnalysisDashboardView.swift:33) — which is only presented by
`DashboardMainTabView`, which is only reachable from legacy `MainTabView` (`--use-legacy-ui`).
`ThreeTabView` injects the store as an environment object (ThreeTabView.swift:51) but **no view in the
3-tab hierarchy consumes it**. The user pays 2 AI calls for an analysis that survives relaunch in
storage but is permanently invisible.

**Fix sketch:** surface the stored analysis in the 3-tab UI — e.g. an "Last Analysis" card on Assess
(with "Generate Plan" CTA wired to the existing flow), or a row on Progress. Evidence: `f2-evidence/*.png`.

## F3 fix re-verification (bonus)

With commit 42c4c6f on this build: pressing home (scenePhase → .background) after the workout uploaded
the session trail immediately — `sessionLogs` went 0 → 1 for vuser-veteran-001 **without any AI analysis
running**. The 2026-06-09 gap (trails only on analysis) is confirmed closed for the no-analysis path.

## GA4 BigQuery (deferred item from 2026-06-09)

**The export is healthy — the 02:30 PT checks were simply too early.** Investigation:

- Daily tables are created the **following morning ~07:50–09:25 PT** (observed creationTime:
  `events_20260604` → 06-05 08:01, `events_20260605` → 06-06 08:49, `events_20260606` → 06-07 07:52,
  `events_20260608` → 06-09 09:24).
- Gaps in the table series (e.g. 06-02, 06-03, 06-07 missing) correspond to **zero-event days** — GA4
  creates no table for days with no events. Not a misconfiguration.
- There is **no intraday/streaming export** configured (no `events_intraday_*` tables) — so nothing can
  appear same-day. This is what sank the March 2026 run: checking same-day against a next-morning daily
  export.
- `user_id` is correctly populated in exported rows (checked on `events_20260608`), so the
  `user_id LIKE "vuser-%"` filter will work.
- As of 06:40 PT on 2026-06-10, `events_20260609` had not landed (inside the normal window). A monitor
  was armed to run the report's query the moment it lands.

**Result (run after table landed):** see addendum below.

## Addendum — same-day fixes

Both confirmed bugs were fixed later on 2026-06-10 in commit `b35e65a` (single commit, message
mentions F2 only but contains both): F7 via a `RestKind { interSet, interExercise }` distinction in
`GuidedWorkoutViewModel` (+ new `GuidedWorkoutViewModelTests`), F2 via a "Your Last Analysis" card on
`AssessTab` that pushes the existing `AnalysisResultView` / Generate Plan flow.

## Cleanup

- `node virtual-users/seed_vuser_data.js --cleanup`: deleted 4 user trees, 1 sessionLogs index doc,
  1 Storage trail, 1 Auth record, cleared rateLimits. `--verify` → 0 vuser docs.
- Simulator neutralized per README: app terminated, local `session_log_current.json` deleted, app
  **uninstalled** from iPhone 16 sim (keychain vuser session cleared).
- Note: the F7 live workout session and trail existed only between seed and cleanup; today's
  `aggregateDailyMetrics` may show a one-day blip.
