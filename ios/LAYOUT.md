# iOS App Layout

```
ios/PT-Helper/PT-Helper/
  PT_HelperApp.swift              # App entry point, Firebase init
  RootView.swift                  # Navigation root (auth check, onboarding gate)
  DesignSystem.swift              # Tokens: AppColors, AppSpacing, AppFonts, AppCorners, AppAnimations + reusable components

  Models/ (21 files)
    UserProfile.swift             # User health profile (Codable)
    PainAssessment.swift          # Per-region pain data + AnalysisResult + ConditionResult
    RehabPlan.swift               # Exercise plan with weekly schedule + RehabExercise
    BodyRegion.swift              # Body map region model
    BodyZone.swift                # Extended zone system
    BodyMapConstants.swift        # 3D model config (colors, scales, proxy geometry)
    InjuryAnalyzer.swift          # Builds AI injury analysis prompts
    WellnessAnalyzer.swift        # Builds AI wellness analysis prompts
    WellnessAnalysisResult.swift  # Wellness analysis output
    WellnessAssessment.swift      # Wellness goal assessment input
    RecoveryInsight.swift         # AI-generated weekly recovery digest
    FormAnalysis.swift            # Exercise form feedback data model
    AdaptiveProgressionAnalyzer.swift  # Pain trend analysis for plan adjustments
    ProgressionRule.swift         # Rules for difficulty scaling
    WorkoutSession.swift          # Completed workout session data
    Achievement.swift             # Progress milestones and gamification
    AssessmentSnapshot.swift      # Historical assessment comparison
    Timer.swift                   # Rest timer state
    SessionEvent.swift            # Session logging events
    Note.swift                    # User observation notes
    LegalContent.swift            # Privacy policy, terms of service

  ViewModels/ (15 files)
    InjuryAnalysisViewModel.swift # Pain assessment + two-call AI pipeline
    RehabPlanViewModel.swift      # Plan generation, preferences, verification, Firestore save
    GuidedWorkoutViewModel.swift  # Step-by-step workout with checkpointing + progressive learning
    SavedPlansViewModel.swift     # Real-time Firestore plan listener
    WorkoutViewModel.swift        # Workout session tracking
    WellnessAnalysisViewModel.swift  # Two-call wellness analysis pipeline
    WellnessPlanViewModel.swift   # Wellness exercise + habit plan generation
    RecoveryInsightsViewModel.swift  # Managed Agent recovery insights + caching
    FormAnalysisViewModel.swift   # Pose detection + form feedback orchestration
    ExerciseSwapViewModel.swift   # AI-powered exercise substitution
    ReAssessmentViewModel.swift   # Pain re-assessment + comparison
    BodyMapViewModel.swift        # 3D body map state management
    OnboardingViewModel.swift     # 6-step profile wizard
    TimerViewModel.swift          # Rest timer management
    NotesViewModel.swift          # User notes CRUD

  Views/ (69 files)
    ThreeTabView.swift            # 3-tab navigation container (Assess / My Plan / Progress)
    MainTabView.swift             # Legacy 4-tab wrapper (--use-legacy-ui)
    AssessTab.swift               # Dual gateway: pain analysis or wellness goals
    MyPlanTab.swift               # Active plan hero + saved plans list
    ProgressTab.swift             # Charts, insights, settings, session history

    BodyMap3DView.swift           # RealityKit 3D body map + coach marks
    BodyMapView.swift             # 2D body map fallback
    ZoneSelectionPanel.swift      # Zone selection UI
    PainDetailView.swift          # Per-region pain form (collapsible sections)
    AnalyzingView.swift           # AI analysis loading screen
    AnalysisResultView.swift      # Results display + preferences sheet

    RehabPlanView.swift           # Plan display, edit, swap, guided workout entry
    EditRehabPlanView.swift       # Plan editing sheet
    EditExerciseView.swift        # Exercise editing
    ExerciseDetailView.swift      # Full exercise detail view
    ExerciseSwapSheet.swift       # Exercise substitution modal

    GuidedWorkoutView.swift       # Exercise execution with resume support
    GuidedWorkoutSummaryView.swift  # Post-workout stats + pain input
    WorkoutSessionView.swift      # Workout session record view
    TimerView.swift               # Rest timer display

    FormAnalysisView.swift        # Exercise form feedback display
    FormCheckTab.swift            # Form check entry point

    WellnessGoalPickerView.swift  # Wellness goal selection
    WellnessDetailView.swift      # Wellness questionnaire
    WellnessAnalyzingView.swift   # Wellness analysis loading
    WellnessResultView.swift      # Wellness analysis results
    WellnessPlanView.swift        # Wellness plan display

    RecoveryInsightsCardView.swift  # Recovery digest teaser card
    RecoveryInsightsDetailView.swift  # Full recovery insights view
    AdaptiveProgressionBannerView.swift  # Progression recommendation banner

    ReAssessmentPromptView.swift  # Re-assessment prompt
    ReAssessmentComparisonView.swift  # Current vs. previous comparison
    QuickHealthUpdateView.swift   # Quick health profile update
    HealthCheckPromptView.swift   # Returning user health check

    ProgressChartView.swift       # Pain trend charts
    AchievementsView.swift        # Achievements display
    PlansTab.swift                # Legacy plans tab

    OnboardingView.swift          # Onboarding container
    SettingsView.swift            # App settings
    NotesView.swift               # User notes
    DisclaimerView.swift          # Legal disclaimer
    LegalDocumentView.swift       # Privacy policy / terms viewer

    Components/ (10 files)
      ExercisePhaseStepperView.swift  # 3-phase instruction stepper (Start → Move → Return)
      ExerciseImageView.swift     # Exercise image with SF Symbol fallback
      ExerciseIllustration.swift  # Exercise illustration wrapper
      ExerciseIconMapper.swift    # SF Symbol mapping for exercises
      AnimatedExerciseView.swift  # Animated exercise display (pilot)
      BodySilhouette.swift        # 2D body outline component
      RegionPainInputView.swift   # Per-region pain slider
      VideoRecorderView.swift     # Video capture for form analysis
      StreakBadgeView.swift        # Workout streak badge
      ShareSheet.swift            # Share sheet wrapper

    Dashboard/ (11 files)
      DashboardMainTabView.swift  # Dashboard container
      AnalysisDashboardView.swift # Analysis results dashboard
      DashPainTrendChart.swift    # Pain trend line chart
      DashConfidenceChart.swift   # Condition confidence chart
      DashDifferentialsTable.swift  # Conditions differential table
      DashExercisePerformanceTable.swift  # Exercise performance table
      DashSessionHistoryList.swift  # Recent workout sessions list
      DashActivePlansList.swift   # Active plans widget
      DashProfileView.swift       # Profile summary widget
      DashboardComponents.swift   # Shared dashboard UI components
      RehabMetricsView.swift      # Rehab metrics display

    OnboardingSteps/ (6 files)
      BasicInfoStepView.swift     # Name, DOB, sex, height/weight
      MedicalHistoryStepView.swift  # Medical conditions, medications
      SurgicalHistoryStepView.swift  # Surgical history
      InjuryHistoryStepView.swift # Injury history
      ActivityLevelStepView.swift # Activity level selection
      ProfileReviewStepView.swift # Profile review before submit

  Services/ (24 files)
    ClaudeAPIService.swift        # Firebase proxy → Claude API (9 request types)
    APIConfig.swift               # API endpoint configuration
    ResponseValidationPipeline.swift  # Analysis (6-step) + rehab plan (9-step) validation
    BiomechanicalRuleEngine.swift # Exercise-specific form rules
    FormFeedbackValidationPipeline.swift  # Form feedback safety validation
    KnowledgeGraphService.swift   # Exercise-condition knowledge graph
    CrossModelVerificationService.swift  # Cross-model rehab plan verification
    DataQualityScorer.swift       # Video quality assessment
    InputSanitizer.swift          # Prompt injection stripping
    PoseDetectionService.swift    # MLKit pose detection from video
    PoseAnalysisEngine.swift      # Joint angle + symmetry analysis
    UserProfileService.swift      # Profile read/write + caching
    ExerciseImageService.swift    # 7-layer fuzzy image matching + caching
    BodyModelCache.swift          # 3D body model caching
    AnalysisResultStore.swift     # Persisted analysis results
    HistoryRelevanceFilter.swift  # Kinetic chain health history classification
    SessionLogger.swift           # Navigation, API, error tracking
    AppLogger.swift               # General app logging
    AnalyticsService.swift        # Firebase Analytics events
    NetworkMonitor.swift          # Connectivity status monitoring
    NotificationService.swift     # Push notification handling
    StreakService.swift            # Workout streak tracking
    PDFExportService.swift        # Rehab plan PDF export
    TestDataSeeder.swift          # UI test mock data population

  Resources/
    exercise_image_mapping.json   # Exercise name → image filename mapping
    *.png                         # ~190 AI-generated exercise illustrations

ios/PT-Helper/PT-HelperTests/
  TestFixtures.swift              # Factory methods for test data
  BodyMap3D/                      # Collision tests (FullPlan only)
  Models/                         # Model unit tests
  ViewModels/                     # ViewModel unit tests
  Services/                       # Service unit tests

ios/PT-Helper/PT-HelperUITests/
  DashboardUITests.swift          # Dashboard layout tests
  GuidedWorkoutUITests.swift      # Workout flow tests
  PlansTabUITests.swift           # Plans display tests
  SettingsUITests.swift           # Settings navigation tests
  + more UI test files
```
