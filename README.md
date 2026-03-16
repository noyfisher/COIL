# PT Helper

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

## Project Structure

```
├── ios/PT-Helper/
│   └── PT-Helper/
│       ├── Models/            # Data models (12 files)
│       ├── Services/          # API, validation, logging (14 files)
│       ├── ViewModels/        # Business logic (10 files)
│       ├── Views/             # SwiftUI views (37 files)
│       │   ├── Components/    # Reusable UI components
│       │   └── OnboardingSteps/  # Onboarding flow steps
│       ├── Resources/         # Exercise images, mappings
│       └── DesignSystem.swift # Colors, spacing, typography
│   └── PT-HelperTests/        # 23 test files, 148+ tests
├── functions/src/             # Firebase Cloud Functions
│   └── index.ts               # Rate limiting + system prompts
├── scripts/                   # Exercise image pipeline
│   ├── generate_exercise_images.py
│   ├── qa_exercise_images.py
│   ├── exercise_list.json     # 178 exercise metadata
│   └── output/                # Generated images
├── docs/                      # Product brief, UX flows, safety
├── firebase.json              # Firebase deployment config
└── firestore.rules            # Security rules
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
   open ios/PT-Helper/PT-Helper.xcodeproj
   ```

2. **Firebase configuration**
   - Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
   - Enable Firestore and Authentication (Apple Sign-In, Google Sign-In)
   - Download `GoogleService-Info.plist` and add it to `ios/PT-Helper/PT-Helper/`

3. **Deploy Cloud Functions**
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```

4. **Configure API endpoint**
   - Update `ios/PT-Helper/PT-Helper/Services/APIConfig.swift` with your Cloud Functions URL
   - The app calls the `callClaude` function which handles rate limiting and prompt assembly

5. **Deploy Firestore rules**
   ```bash
   firebase deploy --only firestore:rules
   ```

## Data Flow

### Injury Analysis Flow

1. User taps pain region on 3D body map
2. `PainDetailView` collects: pain level, type, duration, triggers, treatment history
3. `InjuryAnalysisViewModel` builds the assessment with `HistoryRelevanceFilter` sorting medical history by anatomical proximity
4. Request goes to Cloud Function → Claude API with structured system prompt
5. `ResponseValidationPipeline` validates the response (8 checks including medication safety)
6. Results displayed in `AnalysisResultView`

### Health History Relevance

The `HistoryRelevanceFilter` classifies surgeries and injuries as:
- **Directly relevant** — Same body region or active recovery/restrictions
- **Possibly relevant** — Connected via kinetic chain (e.g., hip issue when assessing knee)
- **Background only** — Unrelated or old and fully recovered

This produces focused AI prompts with detailed relevant history and condensed background context.

## Testing

```bash
# Run all tests from Xcode or command line
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'
```

**23 test files** organized by layer:
- **Models** (9) — Data model encoding, enums, validation
- **Services** (8) — API config, prompt construction, relevance filtering, image service
- **ViewModels** (6) — Business logic, state management, navigation

## Safety

The app includes multiple safety layers:

1. **Red-flag detection** — Flags symptoms requiring emergency care (numbness, bowel/bladder changes, etc.)
2. **Input sanitization** — Strips prompt injection attempts from user text
3. **Response validation pipeline** — 8-step validation:
   - JSON structure verification
   - Required field checks
   - Medical safety phrase detection
   - Exercise count and format validation
   - Severity range validation
   - Content coherence checks
   - Medication-aware safety (blood thinners, beta blockers, corticosteroids)
   - Post-surgical restriction warnings
4. **Rate limiting** — 20 requests/minute per user (server-side)
5. **Firestore rules** — Users can only read/write their own data
6. **Disclaimer** — App presents wellness guidance disclaimer, not medical diagnosis

## Exercise Image Pipeline

178 exercise illustrations generated with AI:

```bash
# Generate images (requires BFL API key)
cd scripts
python generate_exercise_images.py --api-key YOUR_BFL_KEY

# Run automated QA (requires Gemini API key)
python qa_exercise_images.py --api-key YOUR_GEMINI_KEY
```

- **Generator**: FLUX 2 Pro via BFL API with structured pose descriptions
- **QA**: Gemini 2.5 Flash vision model checking pose accuracy
- **Pass rate**: 92% (163/178) — remaining are subtle poses or false safety blocks
- **Style**: Clean white background, anatomical mannequin figure

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
