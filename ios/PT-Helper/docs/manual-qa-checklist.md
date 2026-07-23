# COIL Pre-Release Manual QA Checklist

Run through this checklist before every release. Estimated time: ~25 minutes.

**App structure (for orientation):** 4-tab shell — **Home**, **Plan**, **Progress**, **Profile** — plus a floating center **"Assess" (+)** button that opens the assessment gateway (pain analysis *or* wellness goals). Settings and session history live under the **Progress** tab.

Backend note: verify which Firebase project this build points at before testing (`ios/PT-Helper/COIL/Services/APIConfig.swift` + `GoogleService-Info.plist`). A dev-targeted build exercises the dev AI budget and rate limits.

## Login & Onboarding (5 min)

### Auth
- [ ] Fresh launch (no account): Login screen appears (dark hero, intentional in both appearances)
- [ ] Sign in with Apple completes successfully
- [ ] Sign in with Google completes successfully
- [ ] Sign out (Progress → Settings), sign back in — returns to the main app, profile intact

### Legal & consent gate (new — MHMDA/WS3)
- [ ] First-run after sign-in: legal acceptance gate appears (Terms + Privacy + Consumer Health Data policy, version 2026.07)
- [ ] Health-data consent screen appears and must be accepted to proceed
- [ ] Age-policy / minor-safety interstitial behaves (under-13 blocked; minor path if applicable)
- [ ] Grandfathered/returning user with no prior consent is still gated (not silently let through)

### Onboarding
- [ ] Intro carousel shows COIL branding (teal, no red/"PT Helper" leftovers)
- [ ] Onboarding steps show correct titles
- [ ] Fill basic info (name, DOB, sex, height, weight) — Continue enables
- [ ] Skip through remaining steps — main app loads
- [ ] Profile data persists on re-launch

## Body Map & Analysis (5 min)

- [ ] Open the floating **Assess (+)** button → gateway offers **Pain analysis** and **Wellness goals**
- [ ] Choose pain analysis → 3D body model loads within ~3 seconds
- [ ] Drag to rotate works smoothly (full 360)
- [ ] Pinch to zoom in/out works
- [ ] Tap region highlights it correctly
- [ ] Back regions accessible (lower back, upper back, back of head)
- [ ] Coach mark overlay appears on first launch only
- [ ] Zone drill-down panel opens when tapping a broad region
- [ ] Select 2 regions — region count updates
- [ ] Continue → pain assessment form appears
- [ ] Fill pain type, intensity, duration, frequency, onset (essential fields); optional fields stay collapsed
- [ ] "Apply to All Regions & Analyze" works
- [ ] Analysis loading screen shows animated steps and elapsed timer
- [ ] Analysis completes — 3 conditions displayed with details
- [ ] Medical disclaimer banner visible
- [ ] Expandable condition details work (tap to expand/collapse)

## Rehab Plan Generation (3 min)

- [ ] Tap "Build Rehab Plan" — preferences sheet appears
- [ ] Select equipment (none/bands/dumbbells/gym), session length (15/30/45), difficulty (gentle/moderate/challenging)
- [ ] Plan generates — exercise list appears, honoring the selected equipment/length/difficulty
- [ ] Exercise images load (no missing placeholders)
- [ ] Exercise detail view shows tips and contraindications
- [ ] Exercise swap: pick a reason → AI alternatives load and match difficulty/purpose

## Guided Workout (4 min)

- [ ] Tap "Start Guided Workout" — exercise phase loads
- [ ] Exercise name, image, set counter visible
- [ ] New/unfamiliar exercise auto-expands the 3-phase stepper (Start → Movement → Return)
- [ ] "Complete Set" advances the **set** counter (stays on the same exercise between sets)
- [ ] Inter-set rest returns to the **same** exercise at the next set (regression guard for the "rest advances exercise" bug)
- [ ] Only the final set's rest advances to the **next exercise**
- [ ] Rest timer counts down correctly; **background the app during a rest, return — remaining time is reconciled to wall-clock** (not frozen or reset)
- [ ] "Skip Exercise" advances to the next exercise
- [ ] Pause/Resume works
- [ ] "End" shows a confirmation dialog before ending early
- [ ] Complete all exercises — summary view appears
- [ ] Pain slider works (0–10)
- [ ] "Save & Done" saves and returns to plan
- [ ] Kill the app mid-workout, relaunch — "Resume Workout?" prompt appears; resuming does **not** double-count completed sets

## Wellness Flow (2 min)

- [ ] Assess (+) → **Wellness goals** → goal picker (posture, sleep, mobility, strength, pain management)
- [ ] Wellness analysis completes and returns recommendations
- [ ] Wellness plan generates with **daily habits / micro-practices** alongside exercises

## Home, Plan & Progress (2 min)

- [ ] **Home**: week strip shows honest completion dots (not a cosmetic rolling 21-day strip); today's program is correct
- [ ] **Home**: Preventative section is shown **only when an active plan exists** (hidden with no plan)
- [ ] **Plan**: active plan hero card + saved plans list; swipe-to-delete shows a confirmation
- [ ] **Progress**: pain-trend chart renders (or a clear empty state); axis labels are readable
- [ ] **Progress**: "Your Last Analysis" card is present and re-opens the most recent completed analysis
- [ ] **Progress**: Recovery Insights generate from session data → insight card loads

## Notifications (2 min — new/WS2)

- [ ] Progress → Settings: reminders toggle + time picker; enabling actually schedules (reminders are no longer a no-op)
- [ ] Starting a fresh plan schedules a first-workout activation nudge
- [ ] Re-assessment reminders exist at plan midpoint and completion
- [ ] Toggling reminders off cancels pending notifications; sign-out clears them

## Edge Cases & Error States (2 min)

- [ ] Airplane mode **before** an AI action: the AI flows (analysis, rehab plan, exercise swap, form analysis, wellness) fail fast with a clear offline message — no indefinite spinner
- [ ] Offline banner appears; local data still accessible
- [ ] Come back online: banner disappears, AI actions work again
- [ ] Delete all plans: empty state with a "Start Analysis" action
- [ ] No workout sessions: Progress shows an appropriate empty state

## Settings, Consent & Account (2 min)

- [ ] **Appearance** picker (System / Light / Dark) — switching updates the whole app; dark mode renders with correct contrast (no invisible text)
- [ ] "Update Health Info" navigates to profile edit
- [ ] **Withdraw Health Data Consent** control is present, shows a destructive confirmation, and applies (re-gates health-data collection)
- [ ] Sign Out: confirmation dialog, returns to login
- [ ] Delete Account: destructive confirmation dialog; on delete, all data (plans, sessions, analysis, consent, preventative keys) is cleared and Auth user removed

## Accessibility & Visual (2 min)

- [ ] Icon-only buttons have VoiceOver labels (nav, close, assessment "+", etc.)
- [ ] Text meets contrast in **both** light and dark (teal accent-as-text is legible on white)
- [ ] Dynamic Type at a large size: no clipping/overlap on core screens
- [ ] iPhone SE (small screen): no clipping or overlapping
- [ ] iPhone 16 Pro Max (large screen): layout fills appropriately
- [ ] Animations smooth (exercise transitions, rest timer, completion); card shadows/gradients render properly

## Real API Round-Trip (verify against the intended backend)

- [ ] Full analysis: 2 regions → pain forms → analysis → 3 conditions appear
- [ ] Rehab plan generation with preferences → exercises appear
- [ ] Exercise swap: select reason → AI alternatives load
- [ ] Recovery insights: generate from session data → insight card loads
- [ ] Confirm no server errors / rate-limit hits under normal use

## Pre-Submission

- [ ] All automated tests pass (`PreReleasePlan`)
- [ ] No new Xcode warnings or deprecations
- [ ] Archive builds successfully
- [ ] dSYMs upload to Crashlytics
- [ ] App version / build number incremented
- [ ] **APNs entitlement (P3-06):** the source `COIL.entitlements` carries `aps-environment = development`; signing/provisioning is expected to override it to `production` for the distribution archive. Verify the SIGNED archive with `codesign -d --entitlements - <App>.app` (or Transporter/distribution tooling) shows `production` before submitting — a mismatch breaks push delivery. If it does not, switch to configuration-specific entitlements (Debug=development / Release=production).
- [ ] **Nightly report recipient (P3-03):** `REPORT_RECIPIENT_EMAIL` is set to an org-controlled distribution address in the target environment (the job now skips sending when unset — there is no personal-email fallback).
- [ ] **Public/GA only:** legal wording counsel-signed (LegalContent renames per audit WS4-03/WS3-06), support contact is a real address (not a personal Gmail), and the intended production Firebase project is fully provisioned (functions, secrets, Managed Agents, Firestore rules/indexes, exercise images in Storage)
