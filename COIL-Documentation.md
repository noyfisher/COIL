# PT Helper — Complete Documentation
**Generated: March 17, 2026** *(Stale — refer to individual docs for current information: README.md, CLAUDE.md, docs/\*.md)*

---

# Table of Contents

1. [README](#1-readme)
2. [Product Brief](#2-product-brief)
3. [Architecture & Developer Guide (CLAUDE.md)](#3-architecture--developer-guide)
4. [UX Flows](#4-ux-flows)
5. [iOS App Layout](#5-ios-app-layout)
6. [Data Models & Firestore Schema](#6-data-models--firestore-schema)
7. [API Reference](#7-api-reference)
8. [Safety Documentation](#8-safety-documentation)
9. [Exercise Image Pipeline](#9-exercise-image-pipeline)
10. [Backend Setup](#10-backend-setup)
11. [Contributing Guide](#11-contributing-guide)
12. [Changelog](#12-changelog)
13. [Privacy Policy](#13-privacy-policy)
14. [Terms of Service](#14-terms-of-service)
15. [Agent Prompts](#15-agent-prompts)

---

# 1. README

An iOS app that uses AI to deliver personalized physical therapy guidance — from injury analysis through guided rehab workouts.

Users tap where it hurts on a 3D body model, answer targeted questions, and receive a PT-style analysis with a structured exercise plan they can follow with built-in workout guidance.

## Features

- **3D Body Map** — Interactive RealityKit body model with tap-to-select pain regions and invisible proxy entities for occluded areas
- **AI Injury Analysis** — Claude-powered assessment that considers pain characteristics, medical history, and kinetic chain relationships
- **Smart Health History** — Relevance-filtered surgical/injury/medication history using anatomical proximity and temporal rules
- **Rehab Plans** — Structured exercise programs with phases, progressions, and weekly schedules
- **Guided Workouts** — Step-by-step exercise sessions with timers, rep counters, and AI-generated exercise illustrations
- **Exercise Images** — 178 AI-generated exercise illustrations (FLUX 2 Pro) with automated Gemini QA
- **Progress Tracking** — Workout streaks, achievements, re-assessment comparisons, and progress charts
- **Session Logging** — Detailed logging of analysis and workout sessions for debugging and analytics
- **Safety Pipeline** — 8-layer response validation including medication-aware checks and red-flag detection
- **PDF Export** — Export rehab plans as formatted PDFs

## Architecture

```
┌─────────────────────┐
│   iOS App (SwiftUI)  │
│                      │
│  Views → ViewModels  │
│  Models → Services   │
└──────────┬───────────┘
           │ HTTPS
┌──────────▼───────────┐
│  Firebase Cloud Fns   │
│  (Node.js 20)        │
│  • Rate limiting      │
│  • System prompts     │
│  • Prompt assembly    │
└──────────┬───────────┘
           │
┌──────────▼───────────┐     ┌──────────────────┐
│   Claude API          │     │  Firestore        │
│   (Anthropic)         │     │  • User profiles  │
│   • Analysis          │     │  • Assessments    │
│   • Rehab plans       │     │  • Rehab plans    │
└───────────────────────┘     │  • Sessions/Notes │
                              └──────────────────┘
```

## Getting Started

### Prerequisites
- Xcode 16+
- iOS 17+ deployment target
- Node.js 20 (for Cloud Functions)
- Firebase CLI (`npm install -g firebase-tools`)
- A Firebase project with Firestore and Authentication enabled

### Setup

1. **Clone and open in Xcode**
   ```bash
   git clone <repo-url>
   open ios/PT-Helper/COIL.xcodeproj
   ```

2. **Firebase configuration**
   - Create a Firebase project at console.firebase.google.com
   - Enable Firestore and Authentication (Apple Sign-In, Google Sign-In)
   - Download `GoogleService-Info.plist` and add it to `ios/PT-Helper/COIL/`

3. **Deploy Cloud Functions**
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```

4. **Configure API endpoint**
   - Update `ios/PT-Helper/COIL/Services/APIConfig.swift` with your Cloud Functions URL

5. **Deploy Firestore rules**
   ```bash
   firebase deploy --only firestore:rules
   ```

## Testing

```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Key Files

| File | Purpose |
|------|---------|
| `Models/InjuryAnalyzer.swift` | Builds AI prompts with relevance-sorted history |
| `Services/ResponseValidationPipeline.swift` | 8-layer response safety validation |
| `Services/HistoryRelevanceFilter.swift` | Kinetic chain health history classification |
| `ViewModels/InjuryAnalysisViewModel.swift` | Analysis flow orchestration |
| `ViewModels/RehabPlanViewModel.swift` | Rehab plan generation and management |
| `ViewModels/GuidedWorkoutViewModel.swift` | Workout session state machine |
| `Views/BodyMap3DView.swift` | RealityKit 3D body model |
| `Services/ClaudeAPIService.swift` | Claude API client |
| `functions/src/index.ts` | Cloud Functions with system prompts |
| `DesignSystem.swift` | App-wide colors, spacing, typography |

---

# 2. Product Brief

Goal: Help athletes self-assess pain via a 3D body map, answer PT-style questions, and receive AI-powered condition analysis with personalized rehab plans and guided workouts.

Users: Athletes and fitness enthusiasts (self-directed rehabilitation).

## Core Flows
1. **3D Body Map** — Tap body regions to select pain areas (RealityKit, coach marks for first-time users)
2. **Pain Assessment** — Per-region form with collapsible optional sections, "Apply to All" for multi-region
3. **AI Analysis** — Two-call verification pipeline → top 3 conditions with confidence bands, red flag alerts
4. **Rehab Plan** — AI-generated plan with user preferences (equipment, session length, difficulty), exercise verification via knowledge graph + cross-model check
5. **Guided Workout** — Step-by-step execution with rest timers, exercise swaps, and crash-resilient checkpointing
6. **Progress Tracking** — Pain trend charts, workout streaks, AI-powered weekly recovery insights

## Safety
- Non-diagnosis disclaimer shown on first use
- Red flags trigger prominent urgent care alerts
- Confidence capped at 85% with user-facing explanation
- Exercise verification (knowledge graph + cross-model) flags contraindicated exercises
- Medication interaction checks via validation pipeline

## Technical Stack
- iOS: SwiftUI + RealityKit + Firebase (Auth, Firestore, Crashlytics)
- Backend: Firebase Cloud Functions (TypeScript) → Claude API proxy
- Images: 178 AI-generated exercise illustrations (FLUX 2 Pro)

---

# 3. Architecture & Developer Guide

## Build & Test Commands

### iOS App
```bash
# Build
xcodebuild build -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all unit tests (default: UnitPlan)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'

# Run smoke tests only (11 key tests, 60s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run full suite including collision tests (300s timeout)
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test class
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:COILTests/UserProfileTests

# Run a single test method
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:COILTests/UserProfileTests/testDefaultUserProfile
```

### Cloud Functions (Firebase)
```bash
cd functions
npm install
npm run build        # Compile TypeScript → lib/
npm run serve        # Local emulator
npm run lint         # ESLint
firebase deploy --only functions
```

## Architecture

### MVVM + Services Pattern
The iOS app (`ios/PT-Helper/COIL/`) uses MVVM with a singleton service layer:

- **Models/** — Codable structs (`UserProfile`, `PainAssessment`, `RehabPlan`, `AnalysisResult`, `BodyRegion`)
- **ViewModels/** — `@MainActor @ObservableObject` classes that own business logic and publish UI state
- **Views/** — SwiftUI views using `@ObservedObject`/`@StateObject`. Navigation via `NavigationStack`
- **Services/** — Singletons (`static let shared`) for API, persistence, validation, logging

### Two-Call AI Analysis Pipeline
The core feature is AI-powered injury analysis via a two-call pipeline in `InjuryAnalyzer.swift`:

1. **Primary call** (`analysis` request type) — Sends user profile + pain assessments → returns top 5 conditions
2. **Verification call** (`analysis_verify` request type) — Devil's advocate review → refines to top 3 conditions
3. **Graceful degradation** — If call 2 fails, falls back to call 1 results
4. **Validation** — `ResponseValidationPipeline` runs 8 layers of checks (structure, safety phrases, red flags, medication interactions, confidence clamping to 85% max)

All API calls go through `ClaudeAPIService` → Firebase Cloud Function proxy (`functions/src/index.ts`) → Claude API. System prompts and model config live server-side.

### History Relevance Filtering
`HistoryRelevanceFilter` classifies user's surgical/injury history before including it in AI prompts:
- **directlyRelevant** — Same body zone, or "still recovering"/"has restrictions"
- **possiblyRelevant** — Kinetic chain match (e.g., hip affecting knee) or <5 years old
- **backgroundOnly** — Old, unrelated history (included as context only)

### RealityKit 3D Body Map
`BodyMap3DView` uses RealityKit for interactive body region selection. Invisible proxy entities handle occluded regions (lower back, back of head, etc.). Collision tests in `BodyMapCollisionTests` (excluded from UnitPlan, included in FullPlan). First-time users see a coach mark overlay (persisted via `@AppStorage("hasSeenBodyMapCoach")`).

### Guided Workout Checkpointing
`GuidedWorkoutViewModel` saves workout state to `UserDefaults` (`GuidedWorkoutCheckpoint`) on every set completion and exercise skip. On relaunch, `GuidedWorkoutView` detects incomplete sessions and offers a "Resume Workout?" prompt. Checkpoints expire after 24 hours. The "End" button shows a confirmation dialog before ending early.

### Rehab Plan Preferences
Before generating a rehab plan, `AnalysisResultView` shows a preferences sheet where users select equipment (none/bands/dumbbells/gym), session length (15/30/45 min), and difficulty (gentle/moderate/challenging). These are stored in `RehabPlanPreferences` on `RehabPlanViewModel` and included in the AI prompt.

### Pain Assessment Collapsible Form
`PainDetailView` splits fields into essential (always visible: pain type, intensity, duration, frequency, onset, aggravating/relieving factors) and optional (collapsed by default: description, treatment history, notes). The "Apply to All Regions & Analyze" button is shown on every region when multiple are selected.

### Firestore Data Structure
- `users/{uid}/profile/health` — UserProfile document
- `users/{uid}/rehabPlans` — Collection of RehabPlan documents
- `missingExerciseImages` — Public collection for logging missing images

### Shared State via EnvironmentObject
`ThreeTabView` injects shared state into the view hierarchy:
- `TabSelection` — Cross-tab navigation
- `SavedPlansViewModel` — Rehab plans (real-time Firestore listener)
- `WorkoutViewModel` — Workout session tracking
- `NetworkMonitor` — Connectivity status

## Code Conventions

### Design System
Always use tokens from `DesignSystem.swift` — never hardcode colors, spacing, or typography:
- `AppSpacing.xs/sm/md/lg/xl/xxl/xxxl` (4–40pt)
- `AppColors.accent/success/warning/danger/cardBackground`
- `AppCorners.small/medium/card/large/xl/pill`
- `AppFonts.heroTitle/sectionTitle/cardTitle/statNumber`
- `AppAnimations.springy/smooth/bouncy`

Use `CardSection` for form sections, `.cardStyle()` for card elevation, `ChipButton` for selectable tags.

### Adding Files
Xcode 16 uses `PBXFileSystemSynchronizedRootGroup` — new Swift files are auto-discovered. No manual pbxproj edits needed.

### Testing Patterns
- Test fixtures in `TestFixtures.swift` — use factory methods (`makeProfile()`, `makeAssessment()`, `makePlan()`, etc.)
- Mock API via `MockClaudeAPIService` (conforms to `ClaudeAPIServiceProtocol`)
- ViewModels require `@MainActor` in tests
- Test naming: `test<What>_<Condition>_<Expected>` (e.g., `testClassifySurgery_sameRegion_recentWithRestrictions`)

### New Request Type (AI Feature)
1. Add system prompt to `SYSTEM_PROMPTS` in `functions/src/index.ts`
2. Add model config to `MODEL_CONFIG` in the same file
3. Add `AIRequestType` case in `ClaudeAPIService.swift`
4. Add response parsing in the appropriate ViewModel

### Session Logging
Use `.trackScreen("ScreenName")` modifier on new views. `SessionLogger` auto-tracks navigation, API calls, errors, and crash recovery.

## Exercise Image Pipeline
178 AI-generated exercise illustrations in `scripts/output/`. Generation uses FLUX 2 Pro (BFL API), QA uses Gemini 2.5 Flash vision. To add a new exercise:
1. Add metadata to `scripts/exercise_list.json`
2. Generate: `python scripts/generate_exercise_images.py --api-key KEY --exercise "name"`
3. QA: `python scripts/qa_exercise_images.py --api-key KEY`
4. Copy PNGs + `exercise_image_mapping.json` to `ios/PT-Helper/COIL/Resources/`

---

# 4. UX Flows

## Navigation Structure
`MainTabView` is a thin passthrough to `ThreeTabView`; `MainTabView.swift` also hosts the shared `TabSelection` class and `AssessmentRoute` enum. `ThreeTabView` (named for a historical 3-tab IA) is the primary navigation shell with 4 tabs plus a floating "+":
- **Home** (Tab 0) — weekly date strip, today's program + preventative tasks
- **My Plan** (Tab 1) — Active plan hero card + saved plans list
- **Progress** (Tab 2) — Pain trend charts, recovery insights, settings, session history
- **Profile** (Tab 3) — profile summary + edit (`OnboardingEditView`)
- **Floating "+"** — Dual gateway: pain analysis or wellness goals (`AssessmentGatewayView`)

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

---

# 5. iOS App Layout

```
ios/PT-Helper/COIL/
  PT_HelperApp.swift              # App entry point, Firebase init
  DesignSystem.swift              # Tokens: AppColors, AppSpacing, AppFonts, AppCorners, AppAnimations + reusable components

  Models/
    UserProfile.swift             # User health profile (Codable)
    PainAssessment.swift          # Per-region pain data
    AnalysisResult.swift          # AI analysis output (conditions, red flags)
    RehabPlan.swift               # Exercise plan with weekly schedule
    RehabExercise.swift           # Individual exercise definition
    BodyRegion.swift              # Body map region model
    BodyMapConstants.swift        # 3D model config (colors, scales, proxy geometry)
    RecoveryInsight.swift         # AI-generated weekly recovery digest
    AdaptiveProgressionAnalyzer.swift  # Pain trend analysis for plan adjustments

  ViewModels/
    OnboardingViewModel.swift     # 6-step profile wizard
    InjuryAnalysisViewModel.swift # Pain assessment + two-call AI pipeline
    RehabPlanViewModel.swift      # Plan generation, preferences, verification, Firestore save
    GuidedWorkoutViewModel.swift  # Step-by-step workout with checkpointing
    ExerciseSwapViewModel.swift   # AI-powered exercise substitution
    RecoveryInsightsViewModel.swift # Weekly digest generation + caching

  Views/
    MainTabView.swift             # Thin passthrough to ThreeTabView + TabSelection/AssessmentRoute
    OnboardingEditView.swift      # Profile edit wrapper
    BodyMap3DView.swift           # RealityKit 3D body map + coach marks
    PainDetailView.swift          # Per-region pain form (collapsible sections)
    AnalyzingView.swift           # AI analysis loading screen
    AnalysisResultView.swift      # Results display + preferences sheet
    RehabPlanView.swift           # Plan display, edit, swap, guided workout entry
    GuidedWorkoutView.swift       # Exercise execution with resume support
    GuidedWorkoutSummaryView.swift # Post-workout stats + pain input
    ExerciseSwapSheet.swift       # Exercise substitution modal
    RecoveryInsightsCardView.swift
    RecoveryInsightsDetailView.swift
    AdaptiveProgressionBannerView.swift

  Services/
    ClaudeAPIService.swift        # Firebase proxy → Claude API
    UserProfileService.swift      # Profile read/write + caching
    ExerciseImageService.swift    # Exercise illustration loading
    SessionLogger.swift           # Navigation, API, error tracking

  Resources/
    exercise_image_mapping.json   # Exercise name → image filename mapping
    *.png                         # 178 AI-generated exercise illustrations

ios/PT-Helper/COILTests/
  TestFixtures.swift              # Factory methods for test data
  BodyMap3D/                      # Collision tests (FullPlan only)
  Models/                         # Model unit tests
  ViewModels/                     # ViewModel unit tests
  Services/                       # Service unit tests
```

---

# 6. Data Models & Firestore Schema

## Firestore Collections

### `users/{userId}/profile/health`
Single document per user containing their complete health profile.

```
{
  userId: string                    // Firebase Auth UID
  firstName: string
  lastName: string
  dateOfBirth: Timestamp
  sex: string                       // "Male" | "Female" | "Other"
  heightFeet: number
  heightInches: number
  weight: number                    // pounds
  activityLevel: string             // "Sedentary" | "Light" | "Moderate" | "Active" | "Very Active"
  primarySport: string?             // optional
  medicalConditions: string[]       // ["Diabetes", "High Blood Pressure", "Arthritis", ...]
  otherMedicalConditions: string?   // free text
  medications: string[]?            // ["Blood Thinners", "Beta Blockers", ...]
  surgeries: [{
    id: string                      // UUID
    name: string                    // "ACL Reconstruction"
    year: number                    // 2023
    bodyArea: string?               // "Left Knee"
    recoveryStatus: string?         // "Fully recovered" | "Still recovering" | "Have restrictions"
    restrictions: string?           // free text, only when "Have restrictions"
  }]
  injuries: [{
    id: string                      // UUID
    bodyArea: string                // "Left Knee"
    description: string             // "ACL tear from skiing"
    isCurrent: boolean
    year: number?
    sawDoctor: boolean?
    hadPhysicalTherapy: boolean?
    recoveryStatus: string?         // "Fully recovered" | "Mostly recovered" | "Still dealing with it"
  }]
}
```

### `users/{userId}/assessments/{assessmentId}`
Analysis results from AI injury assessments.

```
{
  id: string                        // UUID
  generatedDate: Timestamp
  overallSummary: string
  disclaimerText: string
  assessments: [{                   // pain regions assessed
    id: string
    selectedRegion: {
      zoneKey: string               // "left_knee", "lower_back", etc.
      name: string                  // "Left Knee"
      side: string?                 // "left" | "right" | null
    }
    painTypes: string[]             // ["Sharp", "Aching"]
    customPainDescription: string?
    painIntensity: number           // 1-10
    painDurations: string[]
    painFrequencies: string[]
    painOnsets: string[]
    aggravatingFactors: string[]
    relievingFactors: string[]
    additionalNotes: string?
    currentTreatment: {
      hasSeenDoctor: boolean
      imagingDone: string[]
      hasDiagnosis: boolean
      diagnosisText: string?
      currentlyReceivingTreatment: boolean
      treatmentDetails: string?
    }?
  }]
  conditions: [{                    // AI-returned possible conditions
    id: string
    conditionName: string
    commonName: string
    confidence: number              // 0-85 (capped by pipeline)
    explanation: string
    whatItMeans: string
    howToManage: string
    isRedFlag: boolean
    redFlagMessage: string?
    nextSteps: string[]
  }]
  userProfileSnapshot: { ... }      // frozen copy of profile at analysis time
}
```

### `users/{userId}/rehabPlans/{planId}`
Rehab exercise plans generated from analysis results.

```
{
  id: string                        // UUID
  planName: string
  conditions: string[]
  createdDate: Timestamp
  startDate: Timestamp?
  lastModifiedDate: Timestamp?
  totalWeeks: number                // 4-8 typical
  notes: string?
  exercises: [{
    id: string
    name: string
    targetArea: string
    description: string
    sets: number
    reps: string                    // "10-15" or "30 seconds"
    restSeconds: number
    difficulty: string              // "beginner" | "intermediate" | "advanced"
    demonstrationIcon: string       // SF Symbol name
    tips: string[]
    contraindications: string[]
    startPosition: string?
    movement: string?
    endPosition: string?
    exerciseCategory: string?
    imageFileName: string?
  }]
  weeklySchedule: string[][]        // 7 arrays (Mon-Sun), each with exercise names
}
```

### `users/{userId}/workoutSessions/{sessionId}`
```
{
  id: string
  planId: string
  completedDate: Timestamp
  duration: number                  // seconds
  exercisesCompleted: [{
    exerciseId: string
    setsCompleted: number
    repsCompleted: string
    painDuring: number?
    notes: string?
  }]
}
```

### `missingExerciseImages/{docId}`
```
{
  exerciseName: string
  imageFileName: string
  reportedAt: Timestamp
  userId: string
}
```

## Security Rules
```
users/{userId}/**     → read/write only if auth.uid == userId
missingExerciseImages → read/write if authenticated
```

## iOS Data Models

| Swift Type | File | Firestore Location |
|-----------|------|-------------------|
| `UserProfile` | `Models/UserProfile.swift` | `users/{uid}/profile/health` |
| `PainAssessment` | `Models/PainAssessment.swift` | Embedded in assessments |
| `AnalysisResult` | `Models/PainAssessment.swift` | `users/{uid}/assessments/{id}` |
| `RehabPlan` | `Models/RehabPlan.swift` | `users/{uid}/rehabPlans/{id}` |
| `RehabExercise` | `Models/RehabPlan.swift` | Embedded in rehabPlans |
| `WorkoutSession` | `Models/WorkoutSession.swift` | `users/{uid}/workoutSessions/{id}` |

## Backward Compatibility
All new fields added to existing models use `Optional` types. Existing Firestore documents from earlier app versions decode without issues — missing fields default to `nil`.

---

# 7. API Reference

PT Helper uses a Firebase Cloud Function (`claudeProxy`) as a secure proxy between the iOS app and the Anthropic Claude API.

## Endpoint
```
POST https://us-central1-<project-id>.cloudfunctions.net/claudeProxy
```

## Authentication
All requests require a valid Firebase ID token:
```
Authorization: Bearer <firebase-id-token>
```

## Request Body
```json
{
  "requestType": "analysis" | "rehab_plan",
  "messages": [
    { "role": "user", "content": "<user message string>" }
  ]
}
```

**Message content limit**: 10,000 characters total

## Response
```json
{
  "content": [
    { "type": "text", "text": "<JSON string>" }
  ],
  "stop_reason": "end_turn"
}
```

## Error Responses

| Status | Error | Description |
|--------|-------|-------------|
| `400` | `Missing required fields` | Request body incomplete |
| `400` | `Invalid requestType` | Not in allowed set |
| `400` | `Message content too long` | Exceeds 10,000 characters |
| `401` | `Missing or invalid Authorization header` | No Bearer token |
| `401` | `Invalid Firebase ID token` | Token expired/invalid |
| `405` | `Method not allowed` | Non-POST request |
| `429` | `Rate limit exceeded` | >20 requests/minute |
| `500` | `Server configuration error` | `ANTHROPIC_API_KEY` not set |
| `502` | `Failed to reach AI service` | Anthropic API unreachable |

## Server-Side Configuration

| Request Type | Model | Max Tokens |
|-------------|-------|------------|
| `analysis` | `claude-haiku-4-5-20251001` | 2048 |
| `rehab_plan` | `claude-haiku-4-5-20251001` | 4096 |

## Deployment
```bash
cd functions
npm install
firebase deploy --only functions
firebase functions:secrets:set ANTHROPIC_API_KEY
```

---

# 8. Safety Documentation

PT Helper provides wellness guidance, not medical diagnosis.

## Disclaimer
Every analysis includes: "This is not a medical diagnosis — it's a starting point to help you understand what might be going on."

## Analysis Validation (6 steps)

**Step 1: Content Validation** — Verifies 1-3 conditions, validates confidence scores, flags confidence >= 95 as unreliable

**Step 2: Symptom Red Flag Detection** — Scans for emergency patterns (cardiac, stroke, meningitis, cauda equina, DVT, fracture). Pain >= 9/10 with sudden onset triggers urgent warning.

**Step 3: Condition Red Flag Detection** — Checks AI-returned conditions against dangerous keywords (fracture, dislocation, infection, tumor, DVT, compartment syndrome, etc.)

**Step 4: Anatomical Relevance Check** — Maps body regions to expected conditions, flags mismatches

**Step 5: Confidence Calibration** — Caps at 85%, maps to: Strong Match (65+), Possible Match (35-64), Less Likely (<35)

**Step 6: Deduplication** — Removes duplicate conditions

## Rehab Plan Validation (8 steps)

**Step 1: Exercise Contraindication Check** — Cross-references exercises against diagnosed conditions (e.g., herniated disc: no deadlifts; ACL injury: no deep squats)

**Step 2: Parameter Range Validation** — Sets 1-10, rest 0-300 seconds

**Step 3-4: Exercise Count & Plan Duration** — Flags empty plans or unusual durations

**Step 5: Age-Based Safety** — Users 65+ get warnings about advanced exercises

**Step 6: Medical Condition Safety** — Osteoporosis: impact warnings; heart disease: heart rate monitoring

**Step 7: Medication-Aware Safety** — Blood thinners: fall risk; corticosteroids: tendon weakness; beta blockers: RPE guidance

**Step 8: Post-Surgical Restriction Check** — Flags active surgical recovery

## Input Sanitization
- 500 character limit per field
- Prompt injection patterns stripped
- User content wrapped in XML delimiter tags

## Server-Side Protections
- Authentication required (Firebase ID token)
- Rate limiting: 20 requests/minute per user
- Request type whitelist
- Server-side system prompts and model config (not client-controlled)

---

# 9. Exercise Image Pipeline

178 exercise illustrations generated with AI.

```
exercise_list.json  →  generate_exercise_images.py  →  output/*.png
(178 exercises)        (FLUX 2 Pro via BFL API)        (512x512 images)
                                                            │
                                                     qa_exercise_images.py
                                                     (Gemini 2.5 Flash QA)
                                                            │
                                                     output/qa_report.json
```

## Files

| File | Purpose |
|------|---------|
| `exercise_list.json` | Master list of 178 exercises with metadata |
| `generate_exercise_images.py` | Image generation (FLUX 2 Pro) |
| `qa_exercise_images.py` | Automated QA (Gemini 2.5 Flash) |
| `process_missing_images.py` | Re-processes failed images |
| `output/exercise_image_mapping.json` | Exercise name → filename mapping |

## Usage
```bash
# Generate all missing
python generate_exercise_images.py --api-key YOUR_BFL_KEY

# Generate specific exercise
python generate_exercise_images.py --api-key YOUR_BFL_KEY --exercise "quad-sets"

# Run QA
python qa_exercise_images.py --api-key YOUR_GEMINI_KEY
```

## Results
- **Pass rate**: 92% (163/178)
- **4 Gemini safety blocks**: False positives on fitness poses
- **11 pose accuracy failures**: Exercises too subtle for AI vision QA
- 14 exercises use custom visual prompts for hard-to-describe poses

## Deploying to iOS
```bash
cp output/*.png ../ios/PT-Helper/COIL/Resources/
cp output/exercise_image_mapping.json ../ios/PT-Helper/COIL/Resources/
```

---

# 10. Backend Setup

## Option A — Firebase
- Create project; enable Auth (Apple), Firestore, Storage, FCM
- Add iOS app bundle ID; download `GoogleService-Info.plist`
- Write Firestore Rules enforcing role-based access
- Collections: users, assessments, exercises, conditions, guidance

## Option B — Supabase
- Create project; enable Apple sign-in via GoTrue
- Define tables with RLS policies
- Storage bucket for exercise videos
- Realtime for messaging

---

# 11. Contributing Guide

## Development Setup

### Prerequisites
- Xcode 16+, iOS 17+, Node.js 20, Firebase CLI

### Getting Started
1. Clone the repo and open `ios/PT-Helper/COIL.xcodeproj`
2. Add your `GoogleService-Info.plist`
3. Build and run on a simulator

## Code Style

### Design System
Use tokens from `DesignSystem.swift`:
- **Spacing**: `AppSpacing.xs/sm/md/lg/xl/xxl/xxxl` (4-40pt)
- **Colors**: `AppColors.accent/success/warning/danger/cardBackground`
- **Corner radius**: `AppCorners.small/medium/card/large/xl/pill`
- **Typography**: `AppFonts.heroTitle/sectionTitle/cardTitle/statNumber`
- **Animations**: `AppAnimations.springy/smooth/bouncy`

### Reusable Components
- `CardSection` — Form sections
- `.cardStyle()` — Card elevation modifier
- `ChipButton` — Selectable tag
- `FlowLayout` — Wrapping horizontal layout
- `StyledTextField` — Consistent text input
- `EmptyStateView` — Empty state placeholder
- `QuickActionCard` / `QuickActionButton` — Navigation cards

## Adding a New Feature

### New Model
1. Create a `Codable` struct in `Models/`
2. Xcode 16 auto-discovers new files

### New View
1. Create in `Views/`
2. Use `DesignSystem.swift` tokens
3. Add `.trackScreen()` for session logging

### New Exercise
1. Add to `scripts/exercise_list.json`
2. Generate image → Run QA → Copy to Resources

## Testing
```bash
xcodebuild test -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL -destination 'platform=iOS Simulator,name=iPhone 16'
```

Test naming: `test_classifySurgery_sameRegion_recentWithRestrictions`

## Before Submitting
1. All tests pass
2. Build succeeds with no warnings
3. New features have tests
4. Design system tokens used

---

# 12. Changelog

## [Unreleased]

### Added
- **Smart Health History** — Enriched data model for surgeries, injuries, and medications
- **Health History Relevance Filter** — Kinetic chain-based classification
- **Medication-Aware Safety** — Blood thinners, corticosteroids, beta blockers checks
- **Post-Surgical Restriction Warnings**
- **Treatment History Per Assessment**
- **Expanded Medical Conditions** — Osteoporosis, Blood Clotting Disorder, Fibromyalgia, etc.
- **Medications Tracking**
- **Production Documentation**

### Changed
- System prompts updated with patient history usage instructions

## [0.9.0] — 2025-03-08
- Firebase Crashlytics, Apply to All Regions, Session Logging

## [0.8.0] — 2025-02-28
- 3D Body Map Proxy Entities, Collision Tests, Test Reorganization

## [0.7.0] — 2025-02-20
- AI Response Validation Pipeline, Exercise Contraindication Checker, Medical Red Flag Detector, Confidence Calibration, 178 Exercise Images

## [0.6.0] — 2025-02-10
- Tester Feedback Round, TestFlight Configuration

## [0.5.0] — 2025-01-30
- Firebase Cloud Functions Proxy, Exercise Image Logging

## [0.4.0] — 2025-01-20
- Injury Analysis, Rehab Plans, Guided Workouts, Plan Management, Onboarding Flow

## [0.3.0] — 2025-01-10
- 3D Body Map, Pain Detail Collection, Progress Tracking

## [0.2.0] — 2024-12-15
- Initial app structure, Firebase Authentication, Basic profile management

---

# 13. Privacy Policy

**Last Updated: March 2025**

## Data We Collect
- **Account**: Email, auth provider, user ID (Firebase)
- **Health Profile**: Name, DOB, sex, height/weight, medical conditions, medications, surgical/injury history, activity level
- **Pain Assessments**: Body regions, pain characteristics, treatment history
- **Generated Data**: AI analysis results, rehab plans, workout sessions, notes, session logs
- **Automatic**: Crash reports (Crashlytics), missing image reports

## How We Use Your Data
- Generate AI analysis and rehab plans
- Safety validation (medications, surgical history)
- Track workout progress
- App debugging

## AI Processing
Data sent to Anthropic's Claude API via Firebase Cloud Function proxy. Transmitted over HTTPS, not stored by Anthropic beyond the API request.

## Data Storage
Google Cloud Firestore (Firebase). Encrypted in transit and at rest. Each user can only access their own data.

## Your Rights
Access, correct, delete your data, export rehab plans as PDF.

## Contact
noyfisher2003@gmail.com

---

# 14. Terms of Service

**Last Updated: March 2025**

PT Helper is NOT a medical device and does NOT provide medical diagnosis, treatment, or advice. All analysis results are educational only. Confidence scores reflect pattern matching, not clinical certainty.

Users should consult healthcare providers before starting any exercise program and seek immediate medical attention for severe symptoms.

The app is provided "as is" without warranty. Governed by the laws of the State of California.

Contact: noyfisher2003@gmail.com

---
