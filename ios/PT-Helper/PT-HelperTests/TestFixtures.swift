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
        difficulty: RehabExercise.Difficulty = .beginner,
        exerciseCategory: String? = nil
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
            contraindications: ["Stop if pain."],
            exerciseCategory: exerciseCategory
        )
    }

    // MARK: - Rehab Plan

    static func makePlan(
        name: String = "Test Plan",
        conditions: [String] = ["Test Condition"],
        exercises: [RehabExercise]? = nil,
        totalWeeks: Int = 4,
        startDate: Date? = nil,
        weeklySchedule: [[String]]? = nil
    ) -> RehabPlan {
        let exs = exercises ?? [makeExercise()]
        return RehabPlan(
            id: UUID(),
            planName: name,
            conditions: conditions,
            exercises: exs,
            weeklySchedule: weeklySchedule ?? Array(repeating: [], count: 7),
            totalWeeks: totalWeeks,
            createdDate: Date(),
            notes: nil,
            startDate: startDate
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

    // MARK: - Wellness Goal Selection

    static func makeGoalSelection(
        category: GoalCategory = .improvePosture,
        customDescription: String? = nil
    ) -> GoalSelection {
        GoalSelection(category: category, customDescription: customDescription)
    }

    // MARK: - Wellness Assessment

    static func makeWellnessAssessment(
        goalCategory: GoalCategory = .improvePosture,
        impactLevel: WellnessAssessment.ImpactLevel = .moderate,
        motivationLevel: Int = 7,
        duration: WellnessAssessment.Duration = .fewMonths,
        commitmentLevel: WellnessAssessment.CommitmentLevel = .fifteenMin
    ) -> WellnessAssessment {
        WellnessAssessment(
            id: UUID(),
            goalCategory: goalCategory,
            customGoalText: nil,
            impactLevel: impactLevel,
            motivationLevel: motivationLevel,
            duration: duration,
            timeOfDay: [.morning],
            dailyActivitiesAffected: ["Sitting at desk"],
            currentHabits: ["Walking"],
            priorAttempts: [.stretching],
            commitmentLevel: commitmentLevel,
            specificContext: nil,
            additionalNotes: nil
        )
    }

    // MARK: - Wellness Recommendation

    static func makeWellnessRecommendation(
        goalCategory: String = "improve_posture",
        title: String = "Posture Improvement"
    ) -> WellnessRecommendation {
        WellnessRecommendation(
            id: UUID(),
            goalCategory: goalCategory,
            title: title,
            currentStateAssessment: "Test assessment",
            rootCauses: ["Prolonged sitting"],
            expectedTimeline: "4-6 weeks",
            keyInsight: "Focus on core strengthening",
            priorityLevel: "high",
            relatedGoals: []
        )
    }

    // MARK: - Wellness Analysis Result

    static func makeWellnessAnalysisResult(
        assessments: [WellnessAssessment]? = nil,
        recommendations: [WellnessRecommendation]? = nil,
        profile: UserProfile? = nil
    ) -> WellnessAnalysisResult {
        WellnessAnalysisResult(
            id: UUID(),
            assessments: assessments ?? [makeWellnessAssessment()],
            recommendations: recommendations ?? [makeWellnessRecommendation()],
            overallSummary: "Test wellness summary",
            disclaimerText: "This is not medical advice.",
            generatedDate: Date(),
            userProfileSnapshot: profile ?? makeProfile()
        )
    }

    // MARK: - Wellness Analysis Response

    /// Returns a valid JSON string matching the AI wellness analysis response format
    /// (`AIWellnessResponse`). Benign by default so validation produces no red flags.
    static func makeWellnessAnalysisResponseJSON(
        goalCategory: String = "improve_posture",
        title: String = "Posture Improvement Plan"
    ) -> String {
        """
        {
            "recommendations": [
                {
                    "goalCategory": "\(goalCategory)",
                    "title": "\(title)",
                    "currentStateAssessment": "You have mild postural fatigue from desk work.",
                    "rootCauses": ["Prolonged sitting", "Weak core"],
                    "expectedTimeline": "4-6 weeks",
                    "keyInsight": "Frequent movement breaks help more than any single stretch.",
                    "priorityLevel": "high",
                    "relatedGoals": []
                }
            ],
            "overallSummary": "Small daily habits will steadily improve your posture over the next several weeks.",
            "disclaimerText": "This is educational wellness guidance, not medical advice."
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

    // MARK: - Pose Frame

    /// Creates a PoseFrame with all 17 joints at uniform positions and confidence.
    static func makePoseFrame(
        timestamp: Double = 0,
        jointCount: Int = 17,
        confidence: Double = 0.9,
        bodyHeight: Double? = 1.75
    ) -> PoseFrame {
        var joints: [String: JointPoint3D] = [:]
        let allJoints = BodyJoint3D.allCases
        for i in 0..<min(jointCount, allJoints.count) {
            let joint = allJoints[i]
            // Place joints at distinct positions so bone lengths are realistic
            let y = Double(i) * 0.1
            joints[joint.rawValue] = JointPoint3D(x: 0, y: y, z: 0, confidence: confidence)
        }
        return PoseFrame(timestamp: timestamp, joints: joints, bodyHeight: bodyHeight)
    }

    /// Creates a PoseFrame with explicit joints dictionary.
    static func makePoseFrame(
        timestamp: Double = 0,
        joints: [String: JointPoint3D],
        bodyHeight: Double? = nil
    ) -> PoseFrame {
        PoseFrame(timestamp: timestamp, joints: joints, bodyHeight: bodyHeight)
    }

    // MARK: - Rep Metrics

    static func makeRepMetrics(
        repNumber: Int = 1,
        kneeAngle: RepMetrics.AngleRange? = nil,
        durationSeconds: Double = 2.5
    ) -> RepMetrics {
        let angle = kneeAngle ?? RepMetrics.AngleRange(
            minDegrees: 85, maxDegrees: 170, rangeOfMotion: 85,
            atStart: 170, atMid: 85, atEnd: 170
        )
        return RepMetrics(
            repNumber: repNumber,
            keyAngles: ["left_knee": angle],
            durationSeconds: durationSeconds,
            startTimestamp: Double(repNumber - 1) * durationSeconds,
            endTimestamp: Double(repNumber) * durationSeconds
        )
    }

    // MARK: - Form Analysis Data

    static func makeFormAnalysisData(
        exerciseName: String = "Squat",
        repCount: Int = 3,
        repMetrics: [RepMetrics]? = nil,
        symmetry: FormAnalysisData.SymmetryData? = nil,
        alignment: [FormAnalysisData.AlignmentIssue] = [],
        averageTempo: Double? = 2.5,
        tempoVariability: Double? = 0.3
    ) -> FormAnalysisData {
        let reps = repMetrics ?? (1...repCount).map { makeRepMetrics(repNumber: $0) }
        return FormAnalysisData(
            exerciseName: exerciseName,
            exerciseCategory: "strength",
            targetArea: "Quadriceps",
            totalFramesProcessed: 100,
            videoFPS: 30.0,
            videoDurationSeconds: 10.0,
            detectedRepCount: reps.count,
            repMetrics: reps,
            symmetry: symmetry,
            alignment: alignment,
            averageTempo: averageTempo,
            tempoVariability: tempoVariability,
            bodyHeight: 1.75
        )
    }

    // MARK: - Data Quality Report

    static func makeDataQualityReport(
        overallScore: Double = 0.8,
        frameCoverage: Double = 0.9,
        averageJointCount: Double = 16.0,
        linkLengthConsistency: Double = 0.9,
        temporalOutlierCount: Int = 0,
        totalVideoFrames: Int = 300,
        framesWithPose: Int = 270,
        minimumDataThresholdMet: Bool = true,
        warnings: [String] = []
    ) -> DataQualityReport {
        DataQualityReport(
            overallScore: overallScore,
            frameCoverage: frameCoverage,
            averageJointCount: averageJointCount,
            linkLengthConsistency: linkLengthConsistency,
            temporalOutlierCount: temporalOutlierCount,
            totalVideoFrames: totalVideoFrames,
            framesWithPose: framesWithPose,
            minimumDataThresholdMet: minimumDataThresholdMet,
            warnings: warnings
        )
    }

    // MARK: - Form Feedback

    static func makeFormFeedback(
        score: Int = 75,
        verdict: FormFeedback.Verdict = .good,
        corrections: [FormFeedback.Correction] = [],
        positivePoints: [String] = ["Good depth"],
        safetyNotes: [String] = [],
        dataLimitations: [String] = []
    ) -> FormFeedback {
        FormFeedback(
            exerciseName: "Squat",
            overallScore: score,
            verdict: verdict,
            corrections: corrections,
            positivePoints: positivePoints,
            safetyNotes: safetyNotes,
            dataLimitations: dataLimitations
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
}
