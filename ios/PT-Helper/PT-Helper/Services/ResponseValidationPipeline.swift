import Foundation
import os

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let warnings: [ValidationWarning]
    let appliedFixes: [String]

    var hasWarnings: Bool { !warnings.isEmpty }
}

struct ValidationWarning {
    enum Severity {
        case info        // Minor issue, informational
        case caution     // Should be noted to the user
        case urgent      // Requires immediate user attention (red flag)
    }

    let severity: Severity
    let message: String
}

// MARK: - Confidence Calibration

enum MatchStrength: String {
    case strong = "Strong Match"
    case moderate = "Possible Match"
    case weak = "Less Likely"

    var color: String {
        switch self {
        case .strong: return "green"
        case .moderate: return "orange"
        case .weak: return "gray"
        }
    }
}

struct ConfidenceCalibrator {
    /// Maximum confidence we display — even expert doctors are ~70-80% accurate.
    static let maxDisplayConfidence: Double = 85.0

    /// Clamp and calibrate a raw AI confidence score.
    static func calibrate(_ rawConfidence: Double) -> Double {
        min(max(rawConfidence, 0), maxDisplayConfidence)
    }

    /// Convert numeric confidence to a human-friendly strength label.
    static func matchStrength(for confidence: Double) -> MatchStrength {
        let calibrated = calibrate(confidence)
        switch calibrated {
        case 65...: return .strong
        case 35...: return .moderate
        default:    return .weak
        }
    }
}

// MARK: - Analysis Content Validator

struct AnalysisContentValidator {

    static func validate(_ result: AnalysisResult) -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var fixes: [String] = []

        // 1. Condition count: should be 1-3
        if result.conditions.isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "No possible explanations were identified. Consider consulting a healthcare provider for an in-person assessment."))
        }
        if result.conditions.count > 3 {
            fixes.append("Trimmed conditions from \(result.conditions.count) to 3")
        }

        // 2. Confidence score validation
        for condition in result.conditions {
            if condition.confidence < 0 || condition.confidence > 100 {
                fixes.append("Clamped out-of-range confidence for \(condition.commonName)")
            }
            if condition.confidence >= 95 {
                warnings.append(ValidationWarning(severity: .info, message: "Very high match scores should be interpreted with caution. Even healthcare professionals may not reach this level of certainty without imaging or lab tests."))
            }
        }

        // 3. Red flag consistency: if isRedFlag, must have a message
        for condition in result.conditions {
            if condition.isRedFlag && (condition.redFlagMessage == nil || condition.redFlagMessage?.isEmpty == true) {
                warnings.append(ValidationWarning(severity: .urgent, message: "\(condition.commonName) was flagged as potentially serious. Please consult a healthcare provider promptly."))
            }
        }

        // 4. Duplicate detection
        let names = result.conditions.map { $0.conditionName.lowercased() }
        if Set(names).count < names.count {
            fixes.append("Duplicate conditions detected and would be removed")
        }

        // 5. Summary present and non-empty
        if result.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "The analysis summary was empty."))
        }

        let isValid = warnings.filter({ $0.severity == .urgent }).isEmpty
        return ValidationResult(isValid: isValid, warnings: warnings, appliedFixes: fixes)
    }
}

// MARK: - Medical Red Flag Detector

struct MedicalRedFlagDetector {

    struct RedFlagResult {
        let triggered: Bool
        let alerts: [ValidationWarning]
    }

    /// Symptom combination patterns that ALWAYS require urgent care referral,
    /// regardless of what the AI returns.
    private static let symptomPatterns: [(keywords: [String], region: String?, message: String)] = [
        // Cardiac
        (["chest pain", "shortness of breath"],
         "chest",
         "Chest pain with difficulty breathing may indicate a cardiac emergency. Please call 911 or go to the ER immediately."),

        // Stroke
        (["sudden weakness", "numbness", "one side"],
         nil,
         "Sudden weakness or numbness on one side could be signs of a stroke. Please call 911 immediately."),

        // Meningitis (keywords are specific enough — trigger regardless of selected region)
        (["severe headache", "stiff neck", "fever"],
         nil,
         "A severe headache with neck stiffness and fever could indicate meningitis. Seek emergency medical care."),

        // Cauda Equina Syndrome
        (["loss of bladder", "back pain", "leg weakness"],
         "lower_back",
         "Loss of bladder or bowel control with back pain and leg weakness may indicate cauda equina syndrome. This is a medical emergency — go to the ER immediately."),

        (["saddle numbness", "back pain"],
         "lower_back",
         "Numbness in the saddle area with back pain may indicate cauda equina syndrome. This is a medical emergency."),

        // DVT
        (["calf pain", "swelling", "redness"],
         nil,
         "Calf pain with swelling and redness could indicate a blood clot (DVT). Please seek medical attention promptly."),

        // Fracture indicators
        (["deformity", "unable to bear weight"],
         nil,
         "Visible deformity or inability to bear weight may indicate a fracture. Please seek medical evaluation."),
    ]

    /// Conditions that should NEVER be self-managed with home exercises alone.
    static let noSelfManageKeywords: Set<String> = [
        "fracture", "dislocation", "cauda equina", "spinal cord",
        "infection", "septic", "tumor", "cancer", "dvt", "embolism",
        "compartment syndrome", "avascular necrosis", "osteomyelitis"
    ]

    /// Check assessments for hardcoded red flag patterns.
    static func check(assessments: [PainAssessment]) -> RedFlagResult {
        var alerts: [ValidationWarning] = []

        // High pain intensity check
        for assessment in assessments {
            if assessment.painIntensity >= 9 && assessment.painOnset == .sudden {
                alerts.append(ValidationWarning(
                    severity: .urgent,
                    message: "You reported very severe (\(assessment.painIntensity)/10) pain in your \(assessment.selectedRegion.name) with sudden onset. With pain this severe, we strongly recommend seeing a healthcare provider before starting any exercise program."
                ))
            } else if assessment.painIntensity >= 9 {
                alerts.append(ValidationWarning(
                    severity: .caution,
                    message: "You reported very severe pain (\(assessment.painIntensity)/10) in your \(assessment.selectedRegion.name). Please consult a healthcare provider if this pain does not improve."
                ))
            }
        }

        // Symptom pattern matching from aggravating factors, notes, and custom descriptions
        let allText = assessments.flatMap { assessment in
            var texts = assessment.aggravatingFactors + assessment.relievingFactors
            if let notes = assessment.additionalNotes { texts.append(notes) }
            if let custom = assessment.customPainDescription { texts.append(custom) }
            return texts
        }.joined(separator: " ").lowercased()

        let regionKeys = assessments.map { $0.selectedRegion.zoneKey }

        for pattern in symptomPatterns {
            let allKeywordsMatch = pattern.keywords.allSatisfy { allText.contains($0) }
            let regionMatches = pattern.region == nil || regionKeys.contains(where: { $0.contains(pattern.region!) })

            if allKeywordsMatch && regionMatches {
                alerts.append(ValidationWarning(severity: .urgent, message: pattern.message))
            }
        }

        // Night pain + weight loss pattern (from assessment notes/custom description)
        if allText.contains("night pain") && allText.contains("weight loss") {
            alerts.append(ValidationWarning(
                severity: .urgent,
                message: "Persistent night pain combined with unexplained weight loss needs medical evaluation to rule out serious conditions. Please see a doctor."
            ))
        }

        return RedFlagResult(triggered: !alerts.isEmpty, alerts: alerts)
    }

    /// Check AI-returned conditions for dangerous self-management scenarios.
    static func checkConditions(_ conditions: [ConditionResult]) -> [ValidationWarning] {
        var alerts: [ValidationWarning] = []

        for condition in conditions {
            let nameLower = condition.conditionName.lowercased()
            let commonLower = condition.commonName.lowercased()

            for keyword in noSelfManageKeywords {
                if nameLower.contains(keyword) || commonLower.contains(keyword) {
                    // Ensure this is flagged as a red flag even if AI didn't do so
                    if !condition.isRedFlag {
                        alerts.append(ValidationWarning(
                            severity: .urgent,
                            message: "\(condition.commonName) is a condition that requires professional medical treatment. Please do not attempt to self-manage this with exercises alone."
                        ))
                    }
                    break
                }
            }
        }

        return alerts
    }
}

// MARK: - Exercise Contraindication Checker

struct ExerciseContraindicationChecker {

    /// Exercises that should NEVER be recommended for certain conditions.
    /// Key: lowercased keyword in condition name. Value: lowercased keywords in exercise name.
    private static let contraindicatedExercises: [String: Set<String>] = [
        "herniated disc": ["deadlift", "sit-up", "crunch", "good morning", "toe touch", "leg press"],
        "disc": ["deadlift", "sit-up", "crunch", "good morning"],
        "acl": ["deep squat", "plyometric", "cutting", "pivot", "jump squat", "box jump"],
        "rotator cuff": ["overhead press", "behind neck", "upright row", "behind-the-neck", "military press"],
        "impingement": ["overhead press", "behind neck", "upright row", "lateral raise above shoulder"],
        "frozen shoulder": ["forced stretch", "aggressive", "overhead press"],
        "fracture": ["impact", "jumping", "running", "plyometric", "heavy"],
        "osteoporosis": ["high impact", "jumping", "plyometric", "heavy deadlift", "twisting under load"],
        "spinal stenosis": ["extension", "back bend", "cobra", "overhead"],
        "sciatica": ["sit-up", "crunch", "toe touch", "seated forward fold"],
        "plantar fasciitis": ["jumping", "plyometric", "box jump", "running"],
        "carpal tunnel": ["wrist curl", "heavy grip"],
        "tennis elbow": ["wrist curl", "heavy grip", "pull-up"],
        "golfers elbow": ["wrist curl", "heavy grip", "chin-up"],
    ]

    /// Validate that no exercises are contraindicated for the diagnosed conditions.
    static func validate(exercises: [RehabExercise], conditions: [String]) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        let conditionsLower = conditions.map { $0.lowercased() }

        for exercise in exercises {
            let exerciseLower = exercise.name.lowercased()

            for (conditionKeyword, blockedExercises) in contraindicatedExercises {
                let conditionMatches = conditionsLower.contains(where: { $0.contains(conditionKeyword) })
                guard conditionMatches else { continue }

                let exerciseBlocked = blockedExercises.contains(where: { exerciseLower.contains($0) })
                if exerciseBlocked {
                    warnings.append(ValidationWarning(
                        severity: .caution,
                        message: "\"\(exercise.name)\" may not be appropriate given your condition. Please consult a physical therapist before attempting this exercise."
                    ))
                }
            }
        }

        return warnings
    }

    /// Validate exercise parameter ranges are reasonable.
    static func validateParameters(_ exercises: [RehabExercise]) -> [String] {
        var fixes: [String] = []

        for exercise in exercises {
            if exercise.sets < 1 || exercise.sets > 10 {
                fixes.append("Exercise \"\(exercise.name)\" has unusual sets count: \(exercise.sets)")
            }
            if exercise.restSeconds < 0 || exercise.restSeconds > 300 {
                fixes.append("Exercise \"\(exercise.name)\" has unusual rest period: \(exercise.restSeconds)s")
            }
        }

        return fixes
    }
}

// MARK: - Anatomical Relevance Checker

struct AnatomicalRelevanceChecker {

    /// Maps body region zone keys to conditions that could reasonably occur there.
    private static let regionConditions: [String: Set<String>] = [
        // ── Head & Neck (separate regions) ───────────────────────
        "head": ["headache", "migraine", "tension", "concussion", "tmj", "jaw", "temporal", "occipital"],
        "neck": ["cervical", "neck", "whiplash", "cervicogenic", "radiculopathy", "stinger", "torticollis", "disc"],

        // ── Torso (front) ────────────────────────────────────────
        "chest": ["costochondritis", "chest wall", "rib", "thoracic", "pectoral", "intercostal", "sternum"],
        "abdomen": ["abdominal", "core", "hernia", "oblique", "rectus", "diastasis"],

        // ── Torso (back) ─────────────────────────────────────────
        "upper_back": ["thoracic", "upper back", "scapular", "trapezius", "rhomboid", "postural", "kyphosis", "latissimus"],
        "lower_back": ["lumbar", "lower back", "disc", "sciatica", "stenosis", "spondyl", "sacroiliac", "si joint", "piriformis", "erector"],

        // ── Shoulders ────────────────────────────────────────────
        "left_shoulder": ["shoulder", "rotator cuff", "impingement", "frozen", "labral", "ac joint", "bicep tendon", "deltoid"],
        "right_shoulder": ["shoulder", "rotator cuff", "impingement", "frozen", "labral", "ac joint", "bicep tendon", "deltoid"],

        // ── Upper Arms ───────────────────────────────────────────
        "left_upper_arm": ["bicep", "tricep", "upper arm", "humerus", "brachial"],
        "right_upper_arm": ["bicep", "tricep", "upper arm", "humerus", "brachial"],

        // ── Elbows ───────────────────────────────────────────────
        "left_elbow": ["elbow", "tennis", "golfer", "epicondylitis", "ulnar", "olecranon", "bursitis"],
        "right_elbow": ["elbow", "tennis", "golfer", "epicondylitis", "ulnar", "olecranon", "bursitis"],

        // ── Forearms ─────────────────────────────────────────────
        "left_forearm": ["forearm", "radial", "ulnar", "pronator", "supinator", "compartment"],
        "right_forearm": ["forearm", "radial", "ulnar", "pronator", "supinator", "compartment"],

        // ── Wrists & Hands ───────────────────────────────────────
        "left_wrist_hand": ["wrist", "carpal tunnel", "de quervain", "ganglion", "hand", "finger", "trigger", "scaphoid"],
        "right_wrist_hand": ["wrist", "carpal tunnel", "de quervain", "ganglion", "hand", "finger", "trigger", "scaphoid"],

        // ── Glutes ───────────────────────────────────────────────
        "left_glute": ["glute", "gluteal", "piriformis", "sciatica", "buttock", "deep gluteal"],
        "right_glute": ["glute", "gluteal", "piriformis", "sciatica", "buttock", "deep gluteal"],

        // ── Hips ─────────────────────────────────────────────────
        "left_hip": ["hip", "labral", "bursitis", "groin", "flexor", "impingement", "snapping hip"],
        "right_hip": ["hip", "labral", "bursitis", "groin", "flexor", "impingement", "snapping hip"],

        // ── Thighs ───────────────────────────────────────────────
        "left_thigh": ["quad", "thigh", "adductor", "it band", "femoral", "vastus", "sartorius", "groin"],
        "right_thigh": ["quad", "thigh", "adductor", "it band", "femoral", "vastus", "sartorius", "groin"],

        // ── Hamstrings ───────────────────────────────────────────
        "left_hamstring": ["hamstring", "posterior thigh", "biceps femoris", "strain", "pull", "tear"],
        "right_hamstring": ["hamstring", "posterior thigh", "biceps femoris", "strain", "pull", "tear"],

        // ── Knees ────────────────────────────────────────────────
        "left_knee": ["knee", "patellofemoral", "meniscus", "acl", "pcl", "mcl", "lcl", "patellar", "baker", "chondromalacia"],
        "right_knee": ["knee", "patellofemoral", "meniscus", "acl", "pcl", "mcl", "lcl", "patellar", "baker", "chondromalacia"],

        // ── Calves & Shins ───────────────────────────────────────
        "left_calf_shin": ["calf", "shin", "achilles", "gastrocnemius", "soleus", "tibial", "compartment", "shin splint", "fibular"],
        "right_calf_shin": ["calf", "shin", "achilles", "gastrocnemius", "soleus", "tibial", "compartment", "shin splint", "fibular"],

        // ── Ankles & Feet ────────────────────────────────────────
        "left_ankle_foot": ["ankle", "foot", "plantar", "sprain", "peroneal", "metatarsal", "bunion", "tarsal"],
        "right_ankle_foot": ["ankle", "foot", "plantar", "sprain", "peroneal", "metatarsal", "bunion", "tarsal"],
    ]

    /// Check whether the AI-returned conditions are anatomically relevant to the assessed body regions.
    static func validate(conditions: [ConditionResult], assessedRegions: [BodyRegion]) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        let regionKeys = assessedRegions.map { $0.zoneKey }
        let allowedKeywords: Set<String> = Set(regionKeys.flatMap { regionConditions[$0] ?? [] })

        // If we have no mapping for the regions, skip this check
        guard !allowedKeywords.isEmpty else { return [] }

        for condition in conditions {
            let condNameLower = condition.conditionName.lowercased()
            let commonNameLower = condition.commonName.lowercased()

            let isRelevant = allowedKeywords.contains(where: { keyword in
                condNameLower.contains(keyword) || commonNameLower.contains(keyword)
            })

            if !isRelevant {
                warnings.append(ValidationWarning(
                    severity: .info,
                    message: "\"\(condition.commonName)\" may not be directly related to the body areas you reported pain in. This could be a referred pain pattern, or you may want to discuss this with a healthcare provider."
                ))
            }
        }

        return warnings
    }
}

// MARK: - Full Validation Pipeline

struct ResponseValidationPipeline {

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper", category: "validation")

    /// Run the full validation pipeline on an analysis result.
    /// Returns the (potentially modified) result along with validation info.
    static func validateAnalysis(
        _ result: AnalysisResult,
        assessments: [PainAssessment]
    ) -> (result: AnalysisResult, validation: ValidationResult, redFlags: [ValidationWarning]) {

        var allWarnings: [ValidationWarning] = []
        var allFixes: [String] = []

        // 1. Content validation
        let contentValidation = AnalysisContentValidator.validate(result)
        allWarnings.append(contentsOf: contentValidation.warnings)
        allFixes.append(contentsOf: contentValidation.appliedFixes)

        // 2. Red flag detection from symptoms
        let symptomRedFlags = MedicalRedFlagDetector.check(assessments: assessments)
        var redFlagAlerts = symptomRedFlags.alerts

        // 3. Red flag detection from conditions
        let conditionRedFlags = MedicalRedFlagDetector.checkConditions(result.conditions)
        redFlagAlerts.append(contentsOf: conditionRedFlags)

        // 4. Anatomical relevance check
        let regions = assessments.map { $0.selectedRegion }
        let anatomicalWarnings = AnatomicalRelevanceChecker.validate(conditions: result.conditions, assessedRegions: regions)
        allWarnings.append(contentsOf: anatomicalWarnings)

        // 5. Calibrate confidence scores and cap at maximum
        let calibratedConditions = result.conditions.prefix(3).map { condition in
            ConditionResult(
                id: condition.id,
                conditionName: condition.conditionName,
                commonName: condition.commonName,
                confidence: ConfidenceCalibrator.calibrate(condition.confidence),
                explanation: condition.explanation,
                whatItMeans: condition.whatItMeans,
                howToManage: condition.howToManage,
                isRedFlag: condition.isRedFlag,
                redFlagMessage: condition.redFlagMessage,
                nextSteps: condition.nextSteps
            )
        }

        // 6. Deduplicate conditions
        var seen = Set<String>()
        let uniqueConditions = calibratedConditions.filter { condition in
            let key = condition.conditionName.lowercased()
            if seen.contains(key) {
                allFixes.append("Removed duplicate condition: \(condition.commonName)")
                return false
            }
            seen.insert(key)
            return true
        }

        // Build validated result
        let validatedResult = AnalysisResult(
            id: result.id,
            assessments: result.assessments,
            conditions: Array(uniqueConditions),
            overallSummary: result.overallSummary,
            disclaimerText: result.disclaimerText,
            generatedDate: result.generatedDate,
            userProfileSnapshot: result.userProfileSnapshot
        )

        // Log validation
        logger.info("Validation complete: \(allWarnings.count) warnings, \(allFixes.count) fixes, \(redFlagAlerts.count) red flags")
        Task { @MainActor in
            SessionLogger.shared.log(.stateUpdated, category: .stateChange, message: "Validation pipeline completed",
                                      metadata: ["warnings": "\(allWarnings.count)",
                                                  "fixes": "\(allFixes.count)",
                                                  "redFlags": "\(redFlagAlerts.count)"])
            if !redFlagAlerts.isEmpty {
                // Auto-upload on red flags — this is a high-value flow to capture
                await SessionLogger.shared.uploadToFirestore()
            }
        }
        for fix in allFixes {
            logger.debug("Fix applied: \(fix)")
        }

        let validation = ValidationResult(
            isValid: allWarnings.filter({ $0.severity == .urgent }).isEmpty,
            warnings: allWarnings,
            appliedFixes: allFixes
        )

        return (validatedResult, validation, redFlagAlerts)
    }

    /// Run validation on a rehab plan.
    static func validateRehabPlan(
        _ plan: RehabPlan,
        conditions: [String],
        userProfile: UserProfile
    ) -> (plan: RehabPlan, warnings: [ValidationWarning]) {

        var warnings: [ValidationWarning] = []

        // 1. Exercise contraindication check
        let contraindicationWarnings = ExerciseContraindicationChecker.validate(
            exercises: plan.exercises,
            conditions: conditions
        )
        warnings.append(contentsOf: contraindicationWarnings)

        // 2. Parameter range validation
        let paramFixes = ExerciseContraindicationChecker.validateParameters(plan.exercises)
        for fix in paramFixes {
            warnings.append(ValidationWarning(severity: .info, message: fix))
        }

        // 3. Exercise count check
        if plan.exercises.isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "No exercises were generated. The fallback exercise database will be used."))
        }

        // 4. Plan duration check
        if plan.totalWeeks < 1 || plan.totalWeeks > 24 {
            warnings.append(ValidationWarning(severity: .info, message: "Plan duration of \(plan.totalWeeks) weeks is unusual. Typical plans are 4-12 weeks."))
        }

        // 5. Age-based safety checks
        if userProfile.age >= 65 {
            let hasHighIntensity = plan.exercises.contains(where: { $0.difficulty == .advanced })
            if hasHighIntensity {
                warnings.append(ValidationWarning(
                    severity: .caution,
                    message: "Some exercises are marked as advanced. Given your age, please start slowly and consult a healthcare provider before attempting advanced exercises."
                ))
            }
        }

        // 6. Medical condition safety checks
        let medConditionsLower = userProfile.medicalConditions.map { $0.lowercased() }

        if medConditionsLower.contains(where: { $0.contains("osteoporosis") }) {
            let hasImpact = plan.exercises.contains(where: {
                let nameLower = $0.name.lowercased()
                return nameLower.contains("jump") || nameLower.contains("plyometric") || nameLower.contains("impact") || nameLower.contains("running")
            })
            if hasImpact {
                warnings.append(ValidationWarning(
                    severity: .urgent,
                    message: "High-impact exercises are not recommended with osteoporosis. Please consult your doctor before performing any impact-based exercises."
                ))
            }
        }

        if medConditionsLower.contains(where: { $0.contains("heart") || $0.contains("cardiac") }) {
            warnings.append(ValidationWarning(
                severity: .caution,
                message: "With your cardiac history, please monitor your heart rate during exercises and stop if you experience chest pain, dizziness, or shortness of breath."
            ))
        }

        logger.info("Rehab plan validation: \(warnings.count) warnings for \(plan.exercises.count) exercises")

        return (plan, warnings)
    }
}
