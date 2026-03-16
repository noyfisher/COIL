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
