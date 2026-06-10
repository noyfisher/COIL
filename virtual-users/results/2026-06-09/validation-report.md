# Virtual User Validation Report — 2026-06-09

**Personas run:** 3 (vuser-happy-path-001, vuser-veteran-001, vuser-dropoff-001)
**Driver:** Claude Code session via XcodeBuildMCP/axe UI automation on iPhone 16 simulator
**App build:** branch `form-analysis-agent` + DEBUG-gated `--virtual-user-token` sign-in (checkpoint 4d84949)
**Backend:** pt-helper-dev (live Firestore/Storage/Cloud Functions, real Claude API calls)

## Verdict

- **Charts: PASS — every chart verified renders seeded ground truth exactly** (see Chart Verification).
- **Firestore data writes: PASS** — profile, plan, workout session, streak writes from the real app all landed and decode round-trip.
- **Session logging: FAIL** — trails upload only when an AI analysis runs; screen tracking nearly absent in current UI (details below).
- **2 app bugs found**, one P1 (Generate Plan freezes the app).
- **Firebase Analytics events: DEFERRED** — GA4 BigQuery export lags up to 24h; re-run query below tomorrow.

## Firestore + SessionLogger Validation (20/23 passed)

  ✅ vuser-happy-path-001.profile.exists / firstName=Harper
  ✅ vuser-happy-path-001.rehabPlans=0, workoutSessions=0, streak absent (journey ended at analysis — see F1)
  ✅ vuser-happy-path-001.sessionLogs=1 (170-event trail in Firestore + Storage, crashMarker=true)
  ❌ vuser-happy-path-001.trail.hasAppLaunched (see F4)
  ✅ vuser-veteran-001.profile/plan/sessions(11)/streak all present, plan decodable by app parser
  ❌ vuser-veteran-001.sessionLogs=0 (see F3 — no analysis ran, so no upload trigger)
  ✅ vuser-dropoff-001.profile exists, no plans/sessions/streak (correct for dropoff)
  ❌ vuser-dropoff-001.sessionLogs=0 (see F3)

## Findings

### F1 — P1 BUG: "Generate Plan" freezes the app (reproduced 2/2)
Tapping **Generate Plan** on the Plan Preferences sheet hangs the main thread in a
SwiftUI render loop (`ViewRendererHost.render` wall-to-wall in sample; accessibility
tree goes empty; all taps dead; UI frozen on the sheet). Force-kill is the only exit.
The user loses the analysis they just paid for (see F2). Happy-path could never
generate a plan; funnel events `rehab_plan_generated` → `workout_*` unreachable on
this path. Evidence: `bugs/generate-plan-freeze-sample.txt`, `bugs/generate-plan-freeze-screen.png`.

### F2 — UX GAP: stored analysis has no re-entry point
After relaunch, the persisted analysis result (AnalysisResultStore/UserDefaults) is
not reachable anywhere in the 3-tab UI — no way to build a plan from a completed
analysis without redoing the assessment (and re-paying for 2 AI calls).

### F3 — LOGGING GAP: session trails only upload when an AI analysis runs
`SessionLogger.uploadToFirestore()` has exactly one call site
(`ResponseValidationPipeline.swift:1429`). `endSession()` has **zero** call sites.
Consequences, all observed live:
  - Sessions without an analysis (veteran's 9-min workout session, dropoff's full
    onboarding session) never upload — 2 of 3 personas left no trail despite
    multiple relaunches.
  - `endedAt` is never set, so the crash detector flags **every** prior session as
    a crash → nightly-report crash counts inflated, session-log counts undercounted.
  - The crash-recovery upload path (`uploadPreviousSessionLog`) produced no
    documents in 3 opportunities — needs investigation (suspect Storage/Firestore
    rules vs. auth-user mismatch during sign-in transitions, rules require
    `userId == request.auth.uid`).
Fix sketch: call `endSession()` + `uploadToFirestore()` on `scenePhase == .background`
in PT_HelperApp, and re-test crash recovery.

### F4 — TRACKING GAP: screen tracking nearly absent in current UI
The one uploaded 170-event trail contains **a single `screenAppeared` event — "Login"**
— for a journey spanning carousel → 6-step onboarding → assess gateway → body map →
8-step pain wizard → analysis. `.trackScreen()` is missing from effectively all
screens in the current 3-tab/MVVC UI (the March 2026 run captured Onboarding /
BodyMap3D / DashboardTab screens in the legacy UI). `appLaunched` was also absent
from the trail. Additionally 24 `errorOccurred` events fired during a fully
successful journey — worth triage.

### F5 — UX BUG: pain-wizard option rows have dead tap zones
`optionCard` rows (PainWizardSteps.swift:201) hit-test only the label text and the
trailing icon — the entire middle of each row is dead (missing
`.contentShape(Rectangle())`). Automation taps at row center silently failed;
real users tapping mid-row will experience the same.

### F6 — MINOR: intro-carousel close button sits in the status-bar region
The xmark (IntroNavBar, `.ignoresSafeArea`) renders at y≈26pt where taps are
unreliable. Swiping works; the close affordance often won't.

### F7 — ANOMALY: workout completion summary shows 0 Completed / 0 Skipped
Veteran completed 3 sets of Wall Sits (with Skip Rest between), after which the
workout jumped to "Workout Complete!" showing Duration <1m, **Completed 0,
Skipped 0** — it also ended after exercise 1 of 3 instead of advancing. Rapid
set-completion may race exercise advancement. The Firestore session doc itself
was written correctly (count went 10 → 11). Screenshot:
`vuser-veteran-001/workout-complete-summary.png`.

## Chart Verification (vuser-veteran-001) — ALL PASS

| Chart | Expected (seed) | Displayed | Verdict |
|---|---|---|---|
| Summary stats (before live workout) | 10 sessions / 4.8 avg pain / 250 min | 10 / 4.8 / 250 | ✅ exact |
| Summary stats (after live workout) | 11 / 4.64 / 250 | 11 / 4.6 / 250 | ✅ exact |
| Pain trend (Overall) | 10 pts declining 7.0→3.0, flat 3.0 tail | matches incl. tail | ✅ |
| Region chips | Overall + Left Hip + Right Knee auto-discovered | all 3 | ✅ |
| Pain trend (Right Knee filter) | 10 pts 7.0→3.0, retitled | matches | ✅ |
| Pain trend (Left Hip filter) | 5 pts 4.0→2.0 (sparse) | matches | ✅ |
| Recent workouts list | 10 rows May 27–Jun 9, pain circles color-coded, 20–30 min, 2–3 ex | all correct | ✅ |
| Streak badge | 3 | 🔥 3 | ✅ |
| My Plan card | Knee Recovery Plan, Active, PFPS, 3 ex, 6 wks, May 19 | all correct | ✅ |
| Achievements | cur 3 / longest 5 / 3 earned w/ correct dates, rest locked | all correct | ✅ |
| Outcome-rating prompt | shown (plan ≥ 7 days old) | shown | ✅ |
| Empty states (fresh user) | "No Data Yet", "No Injury Plans Yet", streak 0 | both render | ✅ |

Screenshots: `vuser-veteran-001/*.png`, `/tmp/dropoff_*_empty.png` archived in run dir.

## What worked end-to-end

- DEBUG-gated `--virtual-user-token` custom-token sign-in → full production code path
  (real Firestore writes, Crashlytics user id, analytics user id, session logger).
- Two-call AI analysis pipeline ran twice with clinically sensible top-3 results
  (PFPS strong match for stair-aggravated knee pain).
- Live guided workout wrote a correct workoutSessions doc; charts updated instantly.
- Crash detection flagged the frozen session (correct in that instance).
- Profile round-trip: onboarding form → Firestore → "HI, HARPER!" / "HI, VERA!".

## Deferred: Firebase Analytics (BigQuery)

GA4 export lags up to 24h (and intraday streaming export was not relied upon — the
March 2026 failure). Run on/after 2026-06-10:

```
bq query --use_legacy_sql=false 'SELECT event_name, COUNT(*) c
FROM `pt-helper-dev.analytics_506142273.events_*`
WHERE user_id LIKE "vuser-%" AND _TABLE_SUFFIX >= "20260609"
GROUP BY 1 ORDER BY c DESC'
```

Expected events (from ground-truth files): app_opened, sign_in_completed,
onboarding_started/step_completed×5/completed (×2 personas),
assessment_gateway_chosen{injury} (×2), body_map_opened (×2+), regions_selected,
assessment_started/completed (×2), analysis_completed (×2), workout_started,
workout_completed, tab_switched (many), plan_viewed.
NOT expected (blocked by F1): rehab_plan_generated.

## Cleanup

All `vuser-*` Firestore/Auth/Storage data deleted post-validation via
`node virtual-users/seed_vuser_data.js --cleanup` (results in this directory are
the durable record). Note: vuser activity from today may still appear in tomorrow's
`aggregateDailyMetrics` totals if the 01:00 UTC job ran mid-test — one-day blip only.
