# UX Flows

## Navigation Structure
4-tab layout via `MainTabView`:
- **Home** (Tab 0) — Dashboard, quick actions, recent plans
- **Analyze** (Tab 1) — 3D body map → pain assessment → AI analysis
- **Plans** (Tab 2) — Saved rehab plans list
- **Progress** (Tab 3) — Pain trend charts, recovery insights

## Core Flow: Analysis → Plan → Workout

### 1. Body Map Selection (`BodyMap3DView`)
- RealityKit 3D body model with 19 bilateral zones (~32 with L/R)
- Tap to select/deselect (haptic + red highlight + toast)
- Drag to rotate, pinch to zoom, double-tap zoom toggle
- First-time coach mark overlay with gesture hints
- Continue button requires >= 1 region selected
- First-use disclaimer sheet before proceeding

### 2. Pain Assessment (`PainDetailView`)
- One form per selected region, navigated with Next/Back
- **Essential fields** (always visible): pain type chips, intensity slider (1-10), duration, frequency, onset, aggravating factors, relieving factors
- **Optional fields** (collapsed behind "Add More Details"): pain description, treatment history, additional notes
- "Apply to All Regions & Analyze" button shown on every region for multi-region selections
- Form completion progress bar with encouraging micro-copy

### 3. AI Analysis (`AnalyzingView` → `AnalysisResultView`)
- Two-call pipeline: primary analysis → verification (15-30s)
- Loading screen with 4-step progress indicator and elapsed timer
- Results: top 3 conditions with expand/collapse cards
- Match strength indicator (Strong/Moderate/Weak) with info button explaining 85% cap
- Red flag alerts as prominent banners
- "Build Rehab Plan" opens preferences sheet before generation

### 4. Rehab Plan Preferences (`AnalysisResultView` sheet)
- Equipment: None / Resistance bands / Dumbbells / Full gym
- Session length: 15 / 30 / 45 min
- Difficulty: Gentle / Moderate / Challenging
- "Skip" option uses defaults; "Generate Plan" passes preferences to AI

### 5. Rehab Plan (`RehabPlanView`)
- Plan header with conditions, duration, start date
- Weekly calendar with exercise-day indicators
- Exercise cards with images, sets/reps, difficulty, verification badges
- Visible swap button on each exercise card (saved plans only)
- Context menu also available for swap
- "Start Guided Workout" button
- Share plan as PDF, edit plan via sheet
- Adaptive progression banner when performance data warrants changes

### 6. Guided Workout (`GuidedWorkoutView`)
- Exercise phase: image, 3-step instructions, tips, "Complete Set" button
- Rest phase: circular countdown timer, next exercise preview
- Pause/resume, skip exercise, swap exercise mid-workout
- "End" button shows confirmation dialog ("End & Save" / "Cancel")
- **Checkpointing**: state saved to UserDefaults on every set completion/skip
- **Resume**: on relaunch, detects incomplete session and offers resume prompt
- Checkpoints expire after 24 hours

### 7. Workout Summary (`GuidedWorkoutSummaryView`)
- Trophy celebration animation
- Stats: duration, completed, skipped
- Pain input: overall slider + per-region sliders
- Session notes
- "Save & Done" saves session; button changes to "Done" for explicit dismiss
- No auto-dismiss — user controls when to leave

## Secondary Flows

### Home Tab
- Personalized greeting, stats (active plans, last pain, streak)
- Quick actions: Update Health Info, Recovery Notes, Log Workout
- Recovery Insights teaser with progress dots (shown when < 3 sessions)
- Recovery Digest quick action (shown when insights available)
- Recent plans preview (first 2)

### Onboarding (6-step wizard)
1. Basic info (name, DOB, sex, height/weight) — required
2. Medical history — optional, subtitle explains AI accuracy impact
3. Surgical history — optional, subtitle explains safety value
4. Injury history — optional, subtitle explains personalization value
5. Activity level — required
6. Review & submit

### Health Check Prompt
- Shown when user returns after 3+ months of inactivity
- Options: "Update My Profile" or "Continue to Analysis"

### Settings
- Reminders (toggle + time picker)
- Debug log export
- Sign out, delete account (two-step confirmation)

### Progress Tab
- Pain trend line chart filtered by region
- Summary stats: total sessions, avg pain, total minutes
- Recovery insights (AI-generated weekly digest, requires 3+ sessions in 14 days)
