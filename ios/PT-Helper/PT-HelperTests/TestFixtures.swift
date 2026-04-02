import Foundation
@testable import PT_Helper

/// Shared factory methods for test data, eliminating duplication across test files.
enum TestFixtures {

    // MARK: - Body Region

    static func makeRegion(
        name: String = "Right Knee",
        zoneKey: String = "right_knee",
        sides: [BodySide] = [.front],
        frontPosition: CGPoint = CGPoint(x: 0.5, y: 0.7)
    ) -> BodyRegion {
        BodyRegion(
            name: name, zoneKey: zoneKey,
            sides: sides,
            frontPosition: frontPosition,
            backPosition: nil
        )
    }

    // MARK: - User Profile

    static func makeProfile(
        age: Int = 30,
        sex: String = "Male",
        activityLevel: String = "Moderate",
        medicalConditions: [String] = [],
        medications: [String]? = nil,
        dominantSide: String? = nil,
        medicationHistory: [UserProfile.MedicationChange]? = nil,
        surgeries: [UserProfile.Surgery] = [],
        injuries: [UserProfile.Injury] = []
    ) -> UserProfile {
        let dob = Calendar.current.date(byAdding: .year, value: -age, to: Date())!
        var profile = UserProfile(
            userId: "test-uid", firstName: "Test", lastName: "User",
            dateOfBirth: dob, sex: sex,
            heightFeet: 5, heightInches: 10, weight: 170,
            medicalConditions: medicalConditions,
            surgeries: surgeries, injuries: injuries,
            activityLevel: activityLevel
        )
        profile.medications = medications
        profile.dominantSide = dominantSide
        profile.medicationHistory = medicationHistory
        return profile
    }

    // MARK: - Surgery

    static func makeSurgery(
        name: String = "ACL Reconstruction",
        year: Int = 2023,
        bodyArea: String? = "Right Knee",
        recoveryStatus: String? = "Still recovering",
        restrictions: String? = nil,
        surgeryType: String? = nil,
        causingInjury: String? = nil,
        hasHardware: Bool? = nil,
        hardwareDetails: String? = nil
    ) -> UserProfile.Surgery {
        UserProfile.Surgery(
            name: name, year: year, bodyArea: bodyArea,
            recoveryStatus: recoveryStatus, restrictions: restrictions,
            surgeryType: surgeryType, causingInjury: causingInjury,
            hasHardware: hasHardware, hardwareDetails: hardwareDetails
        )
    }

    // MARK: - Medication Change

    static func makeMedicationChange(
        medication: String = "Ibuprofen",
        action: String = "started",
        date: Date = Date()
    ) -> UserProfile.MedicationChange {
        UserProfile.MedicationChange(medication: medication, action: action, date: date)
    }

    // MARK: - Pain Assessment

    static func makeAssessment(
        region: BodyRegion? = nil,
        painTypes: [String] = ["Aching"],
        painIntensity: Int = 5,
        painDurations: [String] = ["Over a Month"],
        painFrequencies: [String] = ["Intermittent"],
        painOnsets: [String] = ["Gradual"],
        aggravatingFactors: [String] = [],
        relievingFactors: [String] = []
    ) -> PainAssessment {
        PainAssessment(
            id: UUID(),
            selectedRegion: region ?? makeRegion(),
            painTypes: painTypes,
            customPainDescription: nil,
            painIntensity: painIntensity,
            painDurations: painDurations,
            painFrequencies: painFrequencies,
            painOnsets: painOnsets,
            aggravatingFactors: aggravatingFactors,
            relievingFactors: relievingFactors,
            additionalNotes: nil,
            currentTreatment: nil
        )
    }

    // MARK: - Condition Result

    static func makeCondition(
        name: String = "Patellofemoral Pain Syndrome",
        commonName: String = "Runner's Knee",
        confidence: Double = 75,
        isRedFlag: Bool = false
    ) -> ConditionResult {
        ConditionResult(
            id: UUID(),
            conditionName: name,
            commonName: commonName,
            confidence: confidence,
            explanation: "Test explanation",
            whatItMeans: "Test meaning",
            howToManage: "Test management",
            isRedFlag: isRedFlag,
            redFlagMessage: isRedFlag ? "Seek immediate medical attention" : nil,
            nextSteps: ["See a doctor"]
        )
    }

    // MARK: - Analysis Result

    static func makeAnalysisResult(
        profile: UserProfile? = nil,
        conditions: [ConditionResult]? = nil,
        assessments: [PainAssessment]? = nil
    ) -> AnalysisResult {
        let prof = profile ?? makeProfile()
        let conds = conditions ?? [makeCondition()]
        let assess = assessments ?? [makeAssessment()]

        return AnalysisResult(
            id: UUID(),
            assessments: assess,
            conditions: conds,
            overallSummary: "Test summary",
            disclaimerText: "Not medical advice",
            generatedDate: Date(),
            userProfileSnapshot: prof
        )
    }

    // MARK: - Rehab Exercise

    static func makeExercise(
        name: String = "Wall Sits",
        targetArea: String = "Knee",
        difficulty: RehabExercise.Difficulty = .beginner
    ) -> RehabExercise {
        RehabExercise(
            id: UUID(),
            name: name,
            targetArea: targetArea,
            description: "Test exercise",
            sets: 3,
            reps: "10-12",
            restSeconds: 30,
            difficulty: difficulty,
            demonstrationIcon: "figure.cooldown",
            tips: ["Tip 1"],
            contraindications: ["Stop if pain."]
        )
    }

    // MARK: - Rehab Plan

    static func makePlan(
        name: String = "Test Plan",
        conditions: [String] = ["Test Condition"],
        exercises: [RehabExercise]? = nil,
        totalWeeks: Int = 4
    ) -> RehabPlan {
        let exs = exercises ?? [makeExercise()]
        return RehabPlan(
            id: UUID(),
            planName: name,
            conditions: conditions,
            exercises: exs,
            weeklySchedule: Array(repeating: [], count: 7),
            totalWeeks: totalWeeks,
            createdDate: Date(),
            notes: nil
        )
    }

    // MARK: - AI Response JSON

    /// Returns a valid JSON string with multiple conditions for testing the two-call pipeline.
    /// Each tuple is (conditionName, commonName, confidence, isRedFlag).
    static func makeMultiConditionResponseJSON(
        conditions: [(name: String, commonName: String, confidence: Double, isRedFlag: Bool)],
        summary: String = "Multi-condition test summary"
    ) -> String {
        let conditionsJSON = conditions.map { cond in
            """
            {
                "conditionName": "\(cond.name)",
                "commonName": "\(cond.commonName)",
                "confidence": \(cond.confidence),
                "explanation": "Test explanation for \(cond.commonName)",
                "whatItMeans": "Test meaning for \(cond.commonName)",
                "howToManage": "Test management for \(cond.commonName)",
                "isRedFlag": \(cond.isRedFlag),
                "redFlagMessage": \(cond.isRedFlag ? "\"Seek immediate care for \(cond.commonName)\"" : "null"),
                "nextSteps": ["See a specialist"]
            }
            """
        }.joined(separator: ",\n")

        return """
        {
            "conditions": [\(conditionsJSON)],
            "overallSummary": "\(summary)",
            "disclaimerText": "This is not medical advice."
        }
        """
    }

    /// Returns a valid JSON string matching the expected AI analysis response format.
    static func makeAnalysisResponseJSON(
        conditionName: String = "Patellofemoral Pain Syndrome",
        confidence: Double = 75,
        isRedFlag: Bool = false
    ) -> String {
        """
        {
            "conditions": [{
                "conditionName": "\(conditionName)",
                "commonName": "Runner's Knee",
                "confidence": \(confidence),
                "explanation": "Classic knee pain pattern",
                "whatItMeans": "Kneecap tracking issue",
                "howToManage": "Strengthen quads and glutes",
                "isRedFlag": \(isRedFlag),
                "redFlagMessage": \(isRedFlag ? "\"Seek immediate care\"" : "null"),
                "nextSteps": ["See a physical therapist"]
            }],
            "overallSummary": "Knee pain consistent with PFPS",
            "disclaimerText": "This is not medical advice."
        }
        """
    }

    /// Returns a valid JSON string matching the expected AI rehab plan response format.
    static func makeRehabPlanResponseJSON(
        planName: String = "Knee Rehab Plan",
        exerciseCount: Int = 2
    ) -> String {
        let exercises = (0..<exerciseCount).map { i in
            """
            {
                "name": "Exercise \(i + 1)",
                "targetArea": "Knee",
                "description": "Test exercise \(i + 1)",
                "sets": 3,
                "reps": "10-12",
                "restSeconds": 30,
                "difficulty": "beginner",
                "demonstrationIcon": "figure.cooldown",
                "tips": ["Tip"],
                "contraindications": ["None"],
                "startPosition": "Stand upright",
                "movement": "Move slowly",
                "endPosition": "Return to start",
                "exerciseCategory": "strength",
                "imageFileName": "exercise-\(i + 1)"
            }
            """
        }.joined(separator: ",\n")

        return """
        {
            "planName": "\(planName)",
            "exercises": [\(exercises)],
            "totalWeeks": 4,
            "notes": "Progress gradually"
        }
        """
    }

    // MARK: - Exercise Substitute Response

    /// Returns a valid JSON string matching the expected AI exercise substitute response format.
    static func makeSubstituteResponseJSON(count: Int = 2) -> String {
        let subs = (0..<count).map { i in
            """
            {
                "name": "Substitute Exercise \(i + 1)",
                "targetArea": "Knee",
                "description": "Alternative exercise \(i + 1) for knee rehab",
                "sets": 3,
                "reps": "10-12",
                "restSeconds": 30,
                "difficulty": "beginner",
                "demonstrationIcon": "figure.cooldown",
                "tips": ["Keep proper form", "Move slowly"],
                "contraindications": ["Stop if pain increases"],
                "startPosition": "Stand upright with feet shoulder-width apart",
                "movement": "Slowly bend and straighten your knee",
                "endPosition": "Return to standing position",
                "exerciseCategory": "strength",
                "imageFileName": "substitute-exercise-\(i + 1)",
                "whyItHelps": "This targets the same muscles with less joint stress"
            }
            """
        }.joined(separator: ",\n")

        return """
        {
            "substitutes": [\(subs)]
        }
        """
    }

    // MARK: - Knowledge Graph Test Data

    /// Creates a minimal KnowledgeGraph for unit tests.
    static func makeKnowledgeGraph() -> KnowledgeGraph {
        KnowledgeGraph(
            version: "test",
            conditions: [
                "test-knee-pain": KnownCondition(
                    names: ["test knee pain", "test knee syndrome"],
                    icd10: "T99.0",
                    bodyRegions: ["knee"],
                    safeExercises: ["quad-sets", "straight-leg-raises"],
                    unsafeExercises: ["deep-squat"],
                    redFlags: ["test red flag"],
                    referIfPresent: ["persistent symptoms"]
                ),
                "test-shoulder-issue": KnownCondition(
                    names: ["test shoulder issue"],
                    icd10: "T99.1",
                    bodyRegions: ["shoulder"],
                    safeExercises: ["pendulum-swings"],
                    unsafeExercises: ["overhead-press"],
                    redFlags: [],
                    referIfPresent: []
                )
            ],
            exercises: [
                "quad-sets": KnownExercise(
                    names: ["quad sets", "quadricep sets"],
                    targetRegions: ["knee"],
                    category: "strength",
                    safeForConditions: ["test-knee-pain"],
                    unsafeForConditions: []
                ),
                "straight-leg-raises": KnownExercise(
                    names: ["straight leg raises", "slr"],
                    targetRegions: ["knee"],
                    category: "strength",
                    safeForConditions: ["test-knee-pain"],
                    unsafeForConditions: []
                ),
                "deep-squat": KnownExercise(
                    names: ["deep squat", "full squat"],
                    targetRegions: ["knee"],
                    category: "strength",
                    safeForConditions: [],
                    unsafeForConditions: ["test-knee-pain"]
                ),
                "pendulum-swings": KnownExercise(
                    names: ["pendulum swings"],
                    targetRegions: ["shoulder"],
                    category: "mobility",
                    safeForConditions: ["test-shoulder-issue"],
                    unsafeForConditions: []
                )
            ]
        )
    }

    // MARK: - Workout Session

    static func makeSession(
        planId: UUID? = nil,
        daysAgo: Int = 0,
        painLevel: Double = 4.0,
        exercisesPerformed: [String] = ["Wall Sits", "Quad Sets"],
        isCompleted: Bool = true
    ) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!,
            duration: 1800,
            painLevel: painLevel,
            isCompleted: isCompleted,
            exercisesPerformed: exercisesPerformed,
            planId: planId
        )
    }

    // MARK: - Recovery Insights Response

    /// Returns a valid JSON string matching the expected AI recovery insights response format.
    static func makeRecoveryInsightsResponseJSON(
        headline: String = "Great Progress This Week",
        trendDirection: String = "improving"
    ) -> String {
        """
        {
            "headline": "\(headline)",
            "summary": "Your recovery is on track. Pain levels have decreased and you're maintaining good consistency.",
            "painAnalysis": {
                "trendDirection": "\(trendDirection)",
                "trendDescription": "Pain dropped from 5.2 to 3.8 over the past 2 weeks",
                "averagePain": 4.2,
                "regionBreakdown": [
                    {"region": "right_knee", "trend": "improving", "averagePain": 3.5}
                ]
            },
            "adherenceAnalysis": {
                "score": 85,
                "sessionsCompleted": 5,
                "sessionsExpected": 6,
                "description": "You completed 5 of 6 expected sessions this period"
            },
            "keyWins": [
                "Completed all exercises in 3 of 5 sessions",
                "Pain decreased by 1.4 points on average"
            ],
            "focusAreas": [
                "Try to maintain more consistent rest days between sessions"
            ],
            "recommendations": [
                {
                    "icon": "figure.cooldown",
                    "title": "Add Cool-Down Stretches",
                    "description": "Spending 5 minutes stretching after workouts can help reduce soreness"
                },
                {
                    "icon": "drop.fill",
                    "title": "Stay Hydrated",
                    "description": "Drink water before, during, and after your sessions"
                }
            ]
        }
        """
    }

    /// Creates a mock cross-model verification response JSON string.
    static func makeCrossModelResponseJSON(safe: Bool = true, confidence: Double = 0.85) -> String {
        """
        {
            "results": [{
                "safe": \(safe),
                "confidence": \(confidence),
                "reasoning": "Test reasoning",
                "concerns": \(safe ? "[]" : "[\"Test concern\"]")
            }]
        }
        """
    }

    // MARK: - Body Risk Assessment

    static func makeBodyRiskAssessment(
        primaryActivity: PrimaryActivity = .deskWork,
        hoursSeatedPerDay: Double = 8.0,
        dominantSportOrHobby: String? = "Running"
    ) -> BodyRiskAssessment {
        BodyRiskAssessment(
            primaryActivity: primaryActivity,
            hoursSeatedPerDay: hoursSeatedPerDay,
            dominantSportOrHobby: dominantSportOrHobby
        )
    }

    // MARK: - Preventative Streak

    // MARK: - Weakness Insight

    static func makeWeaknessInsight(
        muscleGroup: String = "Hip Flexors",
        targetAreaKey: String = "Hip Flexors",
        skipRate: Double = 0.6,
        sessionsAnalyzed: Int = 8,
        linkedRisk: String = "Lower back strain and anterior hip pain",
        recommendation: String = "Add a daily hip flexor stretch to your routine."
    ) -> WeaknessInsight {
        WeaknessInsight(
            muscleGroup: muscleGroup,
            targetAreaKey: targetAreaKey,
            skipRate: skipRate,
            sessionsAnalyzed: sessionsAnalyzed,
            linkedRisk: linkedRisk,
            recommendation: recommendation
        )
    }

    // MARK: - Posture Check Result

    static func makePostureCheckResult(
        context: PostureContext = .atDesk,
        score: Int = 72,
        observations: [String] = [
            "Right shoulder appears slightly elevated compared to the left.",
            "Head position is forward of the shoulder midline."
        ],
        correctiveCues: [String] = [
            "Slide shoulder blades down and back.",
            "Tuck chin gently and lift the crown of your head."
        ]
    ) -> PostureCheckResult {
        PostureCheckResult(
            context: context,
            score: score,
            observations: observations,
            correctiveCues: correctiveCues
        )
    }

    static func makePreventativeStreak(
        currentStreak: Int = 5,
        longestStreak: Int = 14,
        goalLabel: String = "Posture Maintenance",
        daysActiveThisWeek: Int = 3
    ) -> PreventativeStreak {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        var activityDays: [String] = []
        for offset in 0..<min(daysActiveThisWeek, 7) {
            if let day = Calendar.current.date(byAdding: .day, value: -offset, to: today) {
                activityDays.append(formatter.string(from: day))
            }
        }
        var streak = PreventativeStreak()
        streak.currentStreak = currentStreak
        streak.longestStreak = longestStreak
        streak.lastActivityDate = today
        streak.activityDays = activityDays
        streak.goalLabel = goalLabel
        streak.restDaysUsedThisWeek = 0
        return streak
    }

    static func makeBodyRiskResult(
        regions: [(name: String, level: RiskLevel, rationale: String)]? = nil
    ) -> BodyRiskResult {
        let defaultRegions: [(name: String, level: RiskLevel, rationale: String)] = [
            ("Lower Back", .elevated, "Prolonged sitting compresses lumbar discs and weakens the posterior chain."),
            ("Neck/Cervical", .moderate, "Forward head posture from desk work places extra load on cervical vertebrae.")
        ]
        let regionData = regions ?? defaultRegions
        let riskRegions = regionData.map {
            RiskRegion(id: UUID(), regionName: $0.name, riskLevel: $0.level, rationale: $0.rationale)
        }
        return BodyRiskResult(
            id: UUID(),
            riskRegions: riskRegions,
            generatedDate: Date(),
            assessmentSnapshot: makeBodyRiskAssessment()
        )
    }
}
