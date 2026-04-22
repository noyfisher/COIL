# PT Helper

An iOS app that uses AI to deliver personalized physical therapy guidance — from injury analysis through guided rehab workouts.

Users tap where it hurts on a 3D body model, answer targeted questions, and receive a PT-style analysis with a structured exercise plan they can follow with built-in workout guidance.

## Features

- **3D Body Map** — Interactive RealityKit body model with tap-to-select pain regions and invisible proxy entities for occluded areas
- **AI Injury Analysis** — Claude-powered assessment that considers pain characteristics, medical history, and kinetic chain relationships
- **Wellness Goals** — Proactive wellness pathway for posture, sleep, mobility, strength, and pain management with AI-generated exercise + habit plans
- **Smart Health History** — Relevance-filtered surgical/injury/medication history using anatomical proximity and temporal rules
- **Rehab Plans** — Structured exercise programs with phases, progressions, and weekly schedules
- **Guided Workouts** — Step-by-step exercise sessions with sticky action bar, 3-phase instruction stepper, progressive learning, timers, and rep counters
- **Exercise Form Analysis** — Video-based form feedback using MLKit pose detection, biomechanical rules, and AI analysis
- **Exercise Substitution** — AI-powered exercise swap from plan view or mid-workout
- **Recovery Insights** — Weekly AI-generated recovery digest via Claude Managed Agents with pain trends, adherence scoring, and recommendations
- **Adaptive Progressions** — Rules-based difficulty scaling based on workout performance
- **Exercise Images** — ~190 AI-generated exercise illustrations (FLUX 2 Pro) with automated Gemini QA
- **Progress Tracking** — Workout streaks, achievements, re-assessment comparisons, and progress charts
- **Session Logging** — Detailed logging of analysis and workout sessions for debugging and analytics
- **Safety Pipeline** — Analysis validation (6 steps) and rehab plan validation (9 steps) including medication-aware checks and red-flag detection
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
│  • Managed Agents     │
└──────────┬───────────┘
           │
┌──────────▼───────────┐     ┌──────────────────┐
│   Claude API          │     │  Firestore        │
│   (Anthropic)         │     │  • User profiles  │
│   • Analysis (9 types)│     │  • Assessments    │
│   • Managed Agents    │     │  • Rehab plans    │
└───────────────────────┘     │  • Workouts       │
                              │  • Wellness plans  │
                              └──────────────────┘
```

## Project Structure

```
├── ios/PT-Helper/
│   └── PT-Helper/
│       ├── Models/            # Data models (21 files)
│       ├── Services/          # API, validation, logging (24 files)
│       ├── ViewModels/        # Business logic (15 files)
│       ├── Views/             # SwiftUI views (69 files)
│       │   ├── Components/    # Reusable UI components
│       │   ├── Dashboard/     # Dashboard widgets and charts
│       │   └── OnboardingSteps/  # Onboarding flow steps
│       ├── Resources/         # Exercise images, mappings
│       └── DesignSystem.swift # Colors, spacing, typography
│   └── PT-HelperTests/        # Unit + UI tests
├── functions/src/             # Firebase Cloud Functions
│   ├── index.ts               # Rate limiting, system prompts, endpoints
│   └── managed-agent.ts       # Managed Agents API client
├── scripts/                   # Exercise image pipeline
│   ├── generate_exercise_images.py
│   ├── qa_exercise_images.py
│   ├── exercise_list.json     # Exercise metadata
│   └── output/                # ~190 generated images
├── docs/                      # Product brief, UX flows, safety, API, data models
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
5. `ResponseValidationPipeline` validates the response (6-step analysis validation)
6. Results displayed in `AnalysisResultView`

### Wellness Flow

1. User selects wellness goals (posture, sleep, mobility, strength, pain management)
2. Two-call analysis pipeline (`wellness_analysis` + `wellness_verify`)
3. Wellness plan generated with exercises + daily habits/micro-practices

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

Test plans: SmokePlan (11 key tests), UnitPlan (all unit), FullPlan (all + collision + UI), PreReleasePlan (all + UI + coverage).

## Safety

The app includes multiple safety layers:

1. **Red-flag detection** — Flags symptoms requiring emergency care (numbness, bowel/bladder changes, etc.)
2. **Input sanitization** — Strips prompt injection attempts from user text
3. **Analysis validation** — 6-step pipeline: content validation, symptom/condition red flags, anatomical relevance, confidence calibration (85% cap), deduplication
4. **Rehab plan validation** — 9-step pipeline: contraindications, knowledge graph verification, parameter ranges, exercise count, duration, age safety, medical conditions, medication-aware checks, post-surgical restrictions
5. **Form feedback validation** — `FormFeedbackValidationPipeline` + `BiomechanicalRuleEngine` for exercise form analysis safety
6. **Rate limiting** — 20 requests/minute per user (server-side)
7. **Firestore rules** — Users can only read/write their own data
8. **Disclaimer** — App presents wellness guidance disclaimer, not medical diagnosis

## Exercise Image Pipeline

~190 exercise illustrations generated with AI:

```bash
# Generate images (requires BFL API key)
cd scripts
python generate_exercise_images.py --api-key YOUR_BFL_KEY

# Run automated QA (requires Gemini API key)
python qa_exercise_images.py --api-key YOUR_GEMINI_KEY
```

- **Generator**: FLUX 2 Pro via BFL API with structured pose descriptions
- **QA**: Gemini 2.5 Flash vision model checking pose accuracy
- **Style**: Clean white background, anatomical mannequin figure
- **Image resolution**: 7-layer fuzzy matching in `ExerciseImageService`

## Key Files

| File | Purpose |
|------|---------|
| `Models/InjuryAnalyzer.swift` | Builds AI prompts with relevance-sorted history |
| `Models/WellnessAnalyzer.swift` | Builds wellness analysis prompts |
| `Services/ResponseValidationPipeline.swift` | Analysis (6-step) and rehab plan (9-step) validation |
| `Services/BiomechanicalRuleEngine.swift` | Exercise-specific form validation rules |
| `Services/HistoryRelevanceFilter.swift` | Kinetic chain health history classification |
| `Services/ExerciseImageService.swift` | 7-layer fuzzy image matching and caching |
| `ViewModels/InjuryAnalysisViewModel.swift` | Analysis flow orchestration |
| `ViewModels/RecoveryInsightsViewModel.swift` | Managed Agent recovery insights |
| `ViewModels/GuidedWorkoutViewModel.swift` | Workout state machine with checkpointing |
| `Views/ThreeTabView.swift` | 3-tab navigation container |
| `Views/BodyMap3DView.swift` | RealityKit 3D body model |
| `Services/ClaudeAPIService.swift` | Claude API client (9 request types) |
| `functions/src/index.ts` | Cloud Functions with system prompts |
| `functions/src/managed-agent.ts` | Managed Agents API client |
| `DesignSystem.swift` | App-wide colors, spacing, typography |
