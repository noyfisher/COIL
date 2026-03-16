# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

### iOS App
```bash
# Build
xcodebuild build -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

# Run all unit tests (default: UnitPlan)
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

# Run smoke tests only (11 key tests, 60s timeout)
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan SmokePlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run full suite including collision tests (300s timeout)
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -testPlan FullPlan -destination 'platform=iOS Simulator,name=iPhone 16'

# Run a single test class
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/UserProfileTests

# Run a single test method
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PT-HelperTests/UserProfileTests/testDefaultUserProfile
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
The iOS app (`ios/PT-Helper/PT-Helper/`) uses MVVM with a singleton service layer:

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
`BodyMap3DView` uses RealityKit for interactive body region selection. Invisible proxy entities handle occluded regions (lower back, back of head, etc.). Collision tests in `BodyMapCollisionTests` (excluded from UnitPlan, included in FullPlan).

### Firestore Data Structure
- `users/{uid}/profile/health` — UserProfile document
- `users/{uid}/rehabPlans` — Collection of RehabPlan documents
- `missingExerciseImages` — Public collection for logging missing images

### Shared State via EnvironmentObject
`MainTabView` injects shared state into the view hierarchy:
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
4. Copy PNGs + `exercise_image_mapping.json` to `ios/PT-Helper/PT-Helper/Resources/`
