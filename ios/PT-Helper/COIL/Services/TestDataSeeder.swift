import Foundation

/// Populates deterministic mock data for UI testing.
/// Only activated when `--uitesting` and `--seed-mock-data` launch arguments are present.
/// Writes to UserDefaults / in-memory stores — never touches Firestore.
enum TestDataSeeder {

    // Test/UI-automation launch flags. Gated to DEBUG builds so the
    // `--uitesting` auth bypass (and the rest of the test affordances) cannot
    // be activated in a shipped release binary via re-signed/jailbroken launch
    // arguments. In release these all read `false`, so the production auth and
    // onboarding paths always run. Mirrors the existing `virtualUserToken` gate.
    static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--uitesting")
        #else
        false
        #endif
    }

    static var shouldSeedMockData: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--seed-mock-data")
        #else
        false
        #endif
    }

    static var shouldSkipOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
        #else
        false
        #endif
    }

    static var shouldSimulateOffline: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--simulate-offline")
        #else
        false
        #endif
    }

    static var shouldClearCoachMark: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--clear-coach-mark")
        #else
        false
        #endif
    }

    static var shouldClearWorkoutCheckpoint: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--clear-workout-checkpoint")
        #else
        false
        #endif
    }

    static var shouldPrefillWeight: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--prefill-weight")
        #else
        false
        #endif
    }

    static var showIntroCarousel: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--show-intro")
        #else
        false
        #endif
    }

    /// Virtual user mode: `--virtual-user-token <token>` signs into Firebase Auth
    /// with a custom token and follows the real production path (real Firestore
    /// writes, SessionLogger, Analytics). DEBUG builds only. Mutually exclusive
    /// with `--uitesting` — virtual user mode takes precedence.
    static var virtualUserToken: String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--virtual-user-token"), idx + 1 < args.count else {
            return nil
        }
        return args[idx + 1]
        #else
        return nil
        #endif
    }

    // MARK: - Seed All Data

    @MainActor
    static func seedIfNeeded() {
        guard isUITesting else { return }

        if shouldClearCoachMark {
            UserDefaults.standard.set(false, forKey: AppStorageKeys.hasSeenBodyMapCoach)
        }

        if shouldClearWorkoutCheckpoint {
            // Clears the file-protected checkpoint (P2-08), the legacy UserDefaults
            // copy, and per-exercise completion counters — so the launch arg truly
            // guarantees a checkpoint-free state after the store moved to a file.
            GuidedWorkoutViewModel.clearAllLocalWorkoutState()
        }

        if shouldSimulateOffline {
            NetworkMonitor.shared.isConnected = false
        }

        guard shouldSeedMockData else { return }

        seedProfile()
        seedAnalysisResult()
        seedStreakData()
    }

    // MARK: - Profile

    @MainActor
    private static func seedProfile() {
        let dob = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
        let profile = UserProfile(
            userId: "test-uid-001",
            firstName: "Test",
            lastName: "User",
            dateOfBirth: dob,
            sex: "Male",
            heightFeet: 5,
            heightInches: 10,
            weight: 170,
            medicalConditions: [],
            surgeries: [],
            injuries: [],
            activityLevel: "Moderate"
        )
        UserProfileService.shared.profile = profile
        UserProfileService.shared.isLoaded = true
    }

    // MARK: - Analysis Result

    @MainActor
    private static func seedAnalysisResult() {
        let region = BodyRegion(
            name: "Right Knee",
            zoneKey: "right_knee",
            sides: [.front],
            frontPosition: CGPoint(x: 0.55, y: 0.72),
            backPosition: nil
        )

        let assessment = PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painTypes: ["Aching"],
            customPainDescription: nil,
            painIntensity: 5,
            painDurations: ["Over a Month"],
            painFrequencies: ["Intermittent"],
            painOnsets: ["Gradual"],
            aggravatingFactors: ["Walking", "Stairs"],
            relievingFactors: ["Rest", "Ice"],
            additionalNotes: nil,
            currentTreatment: nil
        )

        let conditions = [
            ConditionResult(
                id: UUID(),
                conditionName: "Patellofemoral Pain Syndrome",
                commonName: "Runner's Knee",
                confidence: 78,
                explanation: "Pain behind the kneecap consistent with PFPS.",
                whatItMeans: "The kneecap is not tracking properly in its groove.",
                howToManage: "Strengthen the quad and hip muscles.",
                isRedFlag: false,
                redFlagMessage: nil,
                nextSteps: ["See a physical therapist"]
            ),
            ConditionResult(
                id: UUID(),
                conditionName: "IT Band Syndrome",
                commonName: "IT Band Syndrome",
                confidence: 62,
                explanation: "Lateral knee pain during activity.",
                whatItMeans: "The iliotibial band is irritated.",
                howToManage: "Foam rolling and stretching.",
                isRedFlag: false,
                redFlagMessage: nil,
                nextSteps: ["Rest and stretch"]
            ),
            ConditionResult(
                id: UUID(),
                conditionName: "Meniscal Tear",
                commonName: "Torn Meniscus",
                confidence: 45,
                explanation: "Possible cartilage damage.",
                whatItMeans: "The cushioning cartilage in the knee may be damaged.",
                howToManage: "Medical evaluation recommended.",
                isRedFlag: false,
                redFlagMessage: nil,
                nextSteps: ["Get an MRI"]
            )
        ]

        let result = AnalysisResult(
            id: UUID(),
            assessments: [assessment],
            conditions: conditions,
            overallSummary: "Knee pain pattern most consistent with patellofemoral dysfunction.",
            disclaimerText: "This is not medical advice. Consult a healthcare professional.",
            generatedDate: Date(),
            userProfileSnapshot: UserProfileService.shared.profile!
        )

        AnalysisResultStore.shared.save(result)
    }

    // MARK: - Streak Data

    @MainActor
    private static func seedStreakData() {
        StreakService.shared.streakData = StreakData(
            currentStreak: 3,
            longestStreak: 7,
            lastWorkoutDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())
        )
    }

    // MARK: - Mock Plans

    static func makeMockPlans() -> [RehabPlan] {
        let exercises1 = [
            RehabExercise(
                id: UUID(), name: "Wall Sits", targetArea: "Knee",
                description: "Stand with back against wall, slide down to 90 degrees.",
                sets: 3, reps: "30 seconds", restSeconds: 30,
                difficulty: .beginner, demonstrationIcon: "figure.cooldown",
                tips: ["Keep knees behind toes"], contraindications: ["Avoid if acute knee pain"]
            ),
            RehabExercise(
                id: UUID(), name: "Straight Leg Raises", targetArea: "Knee",
                description: "Lie on back, raise leg to 45 degrees.",
                sets: 3, reps: "12", restSeconds: 30,
                difficulty: .beginner, demonstrationIcon: "figure.strengthtraining.traditional",
                tips: ["Keep leg straight"], contraindications: ["Stop if sharp pain"]
            ),
            RehabExercise(
                id: UUID(), name: "Clamshells", targetArea: "Hip",
                description: "Lie on side, open top knee like a clamshell.",
                sets: 3, reps: "15", restSeconds: 30,
                difficulty: .beginner, demonstrationIcon: "figure.cooldown",
                tips: ["Keep feet together"], contraindications: []
            )
        ]

        let plan1 = RehabPlan(
            id: UUID(), planName: "Knee Rehab Plan",
            conditions: ["Patellofemoral Pain Syndrome"],
            exercises: exercises1,
            weeklySchedule: [["Wall Sits", "Straight Leg Raises"], [], ["Clamshells"], [], ["Wall Sits"], [], []],
            totalWeeks: 6, createdDate: Date(), notes: "Progress gradually",
            startDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())
        )

        let exercises2 = [
            RehabExercise(
                id: UUID(), name: "Pendulum Swings", targetArea: "Shoulder",
                description: "Lean forward, let arm hang and swing gently.",
                sets: 2, reps: "20", restSeconds: 20,
                difficulty: .beginner, demonstrationIcon: "figure.cooldown",
                tips: ["Use body weight momentum"], contraindications: []
            )
        ]

        let plan2 = RehabPlan(
            id: UUID(), planName: "Shoulder Mobility Plan",
            conditions: ["Rotator Cuff Tendinopathy"],
            exercises: exercises2,
            weeklySchedule: Array(repeating: ["Pendulum Swings"], count: 7),
            totalWeeks: 4, createdDate: Calendar.current.date(byAdding: .day, value: -20, to: Date())!,
            notes: nil
        )

        return [plan1, plan2]
    }

    // MARK: - Mock Sessions

    static func makeMockSessions(planId: UUID) -> [WorkoutSession] {
        [
            WorkoutSession(
                id: UUID(),
                date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
                duration: 1800, painLevel: 4.0, isCompleted: true,
                exercisesPerformed: ["Wall Sits", "Straight Leg Raises", "Clamshells"],
                planId: planId
            ),
            WorkoutSession(
                id: UUID(),
                date: Calendar.current.date(byAdding: .day, value: -3, to: Date())!,
                duration: 1500, painLevel: 5.0, isCompleted: true,
                exercisesPerformed: ["Wall Sits", "Clamshells"],
                planId: planId
            ),
            WorkoutSession(
                id: UUID(),
                date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
                duration: 2100, painLevel: 6.0, isCompleted: true,
                exercisesPerformed: ["Wall Sits", "Straight Leg Raises"],
                planId: planId
            )
        ]
    }
}
