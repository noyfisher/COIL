# Contributing to PT Helper

## Development Setup

### Prerequisites
- Xcode 16+
- iOS 17+ simulator or device
- Node.js 20 (for Cloud Functions)
- Firebase CLI (`npm install -g firebase-tools`)

### Getting Started
1. Clone the repo and open `ios/PT-Helper/PT-Helper.xcodeproj`
2. Add your `GoogleService-Info.plist` to `ios/PT-Helper/PT-Helper/`
3. Build and run on a simulator

## Project Structure

```
ios/PT-Helper/PT-Helper/
├── Models/          # Data models (22 files)
├── Services/        # API, validation, logging, caching (27 files)
├── ViewModels/      # Business logic, state management (15 files)
├── Views/           # SwiftUI views (79 files)
│   ├── Components/  # Reusable UI components
│   ├── Dashboard/   # Dashboard widgets and charts
│   └── OnboardingSteps/
├── Resources/       # Exercise images (1364 start+end frames), JSON mappings
└── DesignSystem.swift  # Design tokens and shared components
```

## Code Style

### Design System
Use the design tokens from `DesignSystem.swift` — never hardcode values:

- **Spacing**: `AppSpacing.xs/sm/md/lg/xl/xxl/xxxl` (4-40pt)
- **Colors**: `AppColors.accent/success/warning/danger/cardBackground/inputBackground`
- **Corner radius**: `AppCorners.small/medium/card/large/xl/pill`
- **Typography**: `AppFonts.heroTitle/sectionTitle/cardTitle/statNumber/badge`
- **Animations**: `AppAnimations.springy/smooth/bouncy`

### Card-based UI
Use `CardSection` for form sections and `.cardStyle()` modifier for card elevation:

```swift
CardSection(icon: "heart.fill", color: .red, title: "Medical") {
    // Content
}
```

### Reusable Components
- `ChipButton` — Selectable tag/chip
- `FlowLayout` — Wrapping horizontal layout
- `StyledTextField` — Consistent text input
- `EmptyStateView` — Empty state placeholder
- `QuickActionCard` / `QuickActionButton` — Navigation cards

### SwiftUI Patterns
- Views use `@ObservedObject` or `@StateObject` for view models
- Navigation uses `NavigationStack` with programmatic navigation
- Screen tracking: `.trackScreen("ScreenName")` modifier

## Adding a New Feature

### New Model
1. Create a `Codable` struct in `Models/`
2. Add Firestore serialization if persisted (see `UserProfile.from(firestoreData:)`)
3. Xcode 16 auto-discovers new files — no pbxproj edits needed

### New View
1. Create in `Views/` (or `Views/Components/` for reusable components)
2. Use `DesignSystem.swift` tokens
3. Add `.trackScreen()` for session logging

### New Service
1. Create in `Services/`
2. Use singleton pattern for shared services (`static let shared`)

### New Exercise
1. Add to `scripts/exercise_list.json` with metadata
2. Generate image: `python scripts/generate_exercise_images.py --exercise "exercise-name"`
3. Run QA: `python scripts/qa_exercise_images.py`
4. Copy to `ios/PT-Helper/PT-Helper/Resources/`
5. Update `exercise_image_mapping.json`

## Testing

### Running Tests
```bash
# All tests
xcodebuild test -project ios/PT-Helper/PT-Helper.xcodeproj \
  -scheme PT-Helper -destination 'platform=iOS Simulator,name=iPhone 16'

# Or use Cmd+U in Xcode
```

### Test Organization
Tests mirror the source structure:
- `Models/` — Data model tests (encoding, enums, validation)
- `Services/` — Service tests (API, prompts, filtering)
- `ViewModels/` — ViewModel tests (state, navigation)

### Writing Tests
- Name test files `<ClassName>Tests.swift`
- Use descriptive test names: `test_classifySurgery_sameRegion_recentWithRestrictions`
- Test edge cases: empty arrays, nil optionals, boundary values
- Mock external services (API calls, Firebase)

## Git Workflow

### Branches
- `main` — Production-ready code
- Feature branches from `main`

### Commits
Write descriptive commit messages:
```
Add "Apply to All Regions" button for multi-region pain assessment
```

### Before Submitting
1. All tests pass (`Cmd+U`)
2. Build succeeds with no warnings in your code
3. New features have tests
4. Design system tokens used (no hardcoded colors/spacing)

## Cloud Functions

### Local Development
```bash
cd functions
npm install
npm run build    # Compile TypeScript
npm run serve    # Local emulator
```

### Deployment
```bash
firebase deploy --only functions
```

### Adding a New Request Type
1. Add system prompt to `SYSTEM_PROMPTS` in `functions/src/index.ts`
2. Add model config to `MODEL_CONFIG`
3. Add corresponding `AIRequestType` case in iOS `ClaudeAPIService.swift`
4. Add response parsing in the appropriate ViewModel
