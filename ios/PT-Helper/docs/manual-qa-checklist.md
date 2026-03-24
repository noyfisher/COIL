# PT Helper Pre-Release Manual QA Checklist

Run through this checklist before every release. Estimated time: 20 minutes.

## Happy Path End-to-End (10 min)

### Login & Onboarding
- [ ] Fresh launch: Login screen appears
- [ ] Sign in with Apple completes successfully
- [ ] Onboarding shows all 6 steps with correct titles
- [ ] Fill basic info (name, DOB, sex, height, weight) — Continue enables
- [ ] Skip through remaining steps — main app loads
- [ ] Profile data persists on re-launch

### Body Map & Analysis
- [ ] 3D body model loads within 3 seconds
- [ ] Drag to rotate works smoothly (full 360)
- [ ] Pinch to zoom in/out works
- [ ] Tap region highlights it correctly
- [ ] Back regions accessible (lower back, upper back, back of head)
- [ ] Coach mark overlay appears on first launch only
- [ ] Zone drill-down panel opens when tapping a broad region
- [ ] Select 2 regions — region count updates
- [ ] Tap "Continue" — pain assessment form appears
- [ ] Fill pain type, intensity, duration, frequency, onset
- [ ] "Apply to All Regions & Analyze" button works
- [ ] Analysis loading screen shows animated steps and elapsed timer
- [ ] Analysis completes — 3 conditions displayed with details
- [ ] Disclaimer banner visible
- [ ] Expandable condition details work (tap to expand/collapse)

### Rehab Plan Generation
- [ ] Tap "Build Rehab Plan" — preferences sheet appears
- [ ] Select equipment, session length, difficulty
- [ ] Plan generates — exercise list appears
- [ ] Exercise images load (no missing placeholders)
- [ ] Exercise detail view shows tips and contraindications

### Guided Workout
- [ ] Tap "Start Guided Workout" — exercise phase loads
- [ ] Exercise name, image, set counter visible
- [ ] "Complete Set" advances set counter
- [ ] Rest timer appears between exercises
- [ ] "Skip Exercise" advances to next exercise
- [ ] Pause/Resume button works
- [ ] "End" button shows confirmation dialog
- [ ] Complete all exercises — summary view appears
- [ ] Pain slider works (0-10)
- [ ] "Save & Done" saves and returns to plan

### Plans & Progress
- [ ] Plans tab shows saved plan(s)
- [ ] Swipe-to-delete shows confirmation
- [ ] Progress tab shows pain trend chart (or empty state)

## Real API Round-Trip (5 min)

- [ ] Full analysis: 2 regions → pain forms → analysis → 3 conditions appear
- [ ] Rehab plan generation with preferences → exercises appear
- [ ] Exercise swap: select reason → AI alternatives load
- [ ] Recovery insights: generate from session data → insight card loads

## Edge Cases & Error States (3 min)

- [ ] Airplane mode: offline banner appears, local data still accessible
- [ ] Come back online: banner disappears
- [ ] Kill app mid-workout, relaunch: resume prompt appears
- [ ] Health check prompt: simulate 3+ months inactivity → prompt shows on Analyze tab
- [ ] Delete all plans: empty state with "Start Analysis" action
- [ ] No workout sessions: progress shows appropriate empty state

## Settings & Auth (2 min)

- [ ] Notifications toggle works, time picker appears when enabled
- [ ] "Update Health Info" navigates to profile edit
- [ ] Sign Out: confirmation dialog, returns to login
- [ ] Delete Account: destructive confirmation dialog

## Device & Visual Check

- [ ] iPhone SE (small screen): no clipping or overlapping
- [ ] iPhone 16 Pro Max (large screen): layout fills appropriately
- [ ] Dashboard dark theme renders correctly
- [ ] Animations smooth (exercise transitions, rest timer, completion)
- [ ] Card shadows and gradients render properly

## Pre-Submission

- [ ] All automated tests pass (PreReleasePlan)
- [ ] No Xcode warnings or deprecations
- [ ] Archive builds successfully
- [ ] dSYMs upload to Crashlytics
- [ ] App version number incremented
