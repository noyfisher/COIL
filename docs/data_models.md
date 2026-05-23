# Data Model & Firestore Schema

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
    currentTreatment: {             // optional per-assessment treatment context
      hasSeenDoctor: boolean
      imagingDone: string[]         // ["X-ray", "MRI", "CT Scan", "Ultrasound"]
      hasDiagnosis: boolean
      diagnosisText: string?
      currentlyReceivingTreatment: boolean
      treatmentDetails: string?
    }?
  }]
  conditions: [{                    // AI-returned possible conditions
    id: string
    conditionName: string           // medical name
    commonName: string              // plain English
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
  conditions: string[]              // condition names this plan addresses
  createdDate: Timestamp
  startDate: Timestamp?             // when user started following
  lastModifiedDate: Timestamp?      // last user edit
  totalWeeks: number                // 4-8 typical
  notes: string?
  exercises: [{
    id: string
    name: string                    // "Quad Sets"
    targetArea: string              // "Quadriceps"
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
    exerciseCategory: string?       // "stretch" | "strength" | "balance" | etc.
    imageFileName: string?          // "quad-sets" (maps to exercise image)
  }]
  weeklySchedule: string[][]        // 7 arrays (Mon-Sun), each with exercise names
}
```

### `users/{userId}/workoutSessions/{sessionId}`
Completed workout session records.

```
{
  id: string
  planId: string                    // reference to rehabPlan
  completedDate: Timestamp
  duration: number                  // seconds
  painLevel: number                 // 0-10 overall pain rating
  exercisesPerformed: string[]      // exercise names completed
  exercisesCompleted: [{
    exerciseId: string
    setsCompleted: number
    repsCompleted: string
    painDuring: number?             // 0-10
    notes: string?
  }]
}
```

### `users/{userId}/notes/{noteId}`
User notes attached to plans or exercises.

```
{
  id: string
  planId: string?
  exerciseId: string?
  content: string
  createdDate: Timestamp
}
```

### `users/{userId}/wellnessPlans/{planId}`
Wellness exercise + habit plans generated from wellness goals.

```
{
  id: string
  planName: string
  goals: string[]                   // wellness goals selected by user
  createdDate: Timestamp
  exercises: [...]                  // same structure as rehab plan exercises
  habits: [{                        // daily micro-practices
    name: string
    description: string
    frequency: string               // "daily", "3x/week", etc.
    category: string                // "stretch", "breathing", "positioning", etc.
  }]
  totalWeeks: number
  notes: string?
}
```

### `users/{userId}/streakData/current`
Single document tracking workout streak.

```
{
  currentStreak: number             // consecutive days
  longestStreak: number
  lastWorkoutDate: Timestamp
  totalWorkouts: number
}
```

### `missingExerciseImages/{docId}`
Shared collection for logging missing exercise images (any authenticated user).

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

All user data is scoped to the authenticated user. No cross-user access is possible.

## iOS Data Models

| Swift Type | File | Firestore Location |
|-----------|------|-------------------|
| `UserProfile` | `Models/UserProfile.swift` | `users/{uid}/profile/health` |
| `PainAssessment` | `Models/PainAssessment.swift` | Embedded in assessments |
| `CurrentTreatment` | `Models/PainAssessment.swift` | Embedded in assessments |
| `ConditionResult` | `Models/PainAssessment.swift` | Embedded in assessments |
| `AnalysisResult` | `Models/PainAssessment.swift` | `users/{uid}/assessments/{id}` |
| `RehabPlan` | `Models/RehabPlan.swift` | `users/{uid}/rehabPlans/{id}` |
| `RehabExercise` | `Models/RehabPlan.swift` | Embedded in rehabPlans |
| `WorkoutSession` | `Models/WorkoutSession.swift` | `users/{uid}/workoutSessions/{id}` |
| `Note` | `Models/Note.swift` | `users/{uid}/notes/{id}` |
| `WellnessAssessment` | `Models/WellnessAssessment.swift` | In-memory (wellness flow input) |
| `WellnessAnalysisResult` | `Models/WellnessAnalysisResult.swift` | In-memory (wellness flow output) |
| `RecoveryInsight` | `Models/RecoveryInsight.swift` | In-memory (cached in ViewModel) |
| `FormAnalysis` | `Models/FormAnalysis.swift` | In-memory (form feedback output) |
| `Achievement` | `Models/Achievement.swift` | In-memory (streak-derived) |
| `AssessmentSnapshot` | `Models/AssessmentSnapshot.swift` | Embedded in assessments |
| `BodyRegion` | `Models/BodyRegion.swift` | In-memory (body map selection) |
| `BodyZone` | `Models/BodyZone.swift` | In-memory (zone mapping) |
| `SessionEvent` | `Models/SessionEvent.swift` | Uploaded via SessionLogger |
| `AdaptiveProgressionAnalyzer` | `Models/AdaptiveProgressionAnalyzer.swift` | In-memory (progression logic) |
| `ProgressionRule` | `Models/ProgressionRule.swift` | In-memory (progression rules) |
| `Timer` | `Models/Timer.swift` | In-memory (rest timer state) |
| `OutcomeFeedback` | `Models/OutcomeFeedback.swift` | In-memory (post-session outcome feedback) |

## Backward Compatibility

All new fields added to existing models use `Optional` types. Existing Firestore documents from earlier app versions decode without issues — missing fields default to `nil`.
