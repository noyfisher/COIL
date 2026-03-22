# iOS App Layout

```
ios/PT-Helper/PT-Helper/
  PT_HelperApp.swift              # App entry point, Firebase init
  ContentView.swift               # HomeTab + OnboardingEditView
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
    MainTabView.swift             # 4-tab navigation + shared state injection
    BodyMap3DView.swift           # RealityKit 3D body map + coach marks
    PainDetailView.swift          # Per-region pain form (collapsible sections)
    AnalyzingView.swift           # AI analysis loading screen
    AnalysisResultView.swift      # Results display + preferences sheet
    RehabPlanView.swift           # Plan display, edit, swap, guided workout entry
    GuidedWorkoutView.swift       # Exercise execution with resume support
    GuidedWorkoutSummaryView.swift # Post-workout stats + pain input
    ProgressChartView.swift       # Pain trend charts + recovery insights
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

ios/PT-Helper/PT-HelperTests/
  TestFixtures.swift              # Factory methods for test data
  BodyMap3D/                      # Collision tests (FullPlan only)
  Models/                         # Model unit tests
  ViewModels/                     # ViewModel unit tests
  Services/                       # Service unit tests
```
