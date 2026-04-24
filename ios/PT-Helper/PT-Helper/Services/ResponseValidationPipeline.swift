import Foundation
import os

// MARK: - Validation Severity (top-level, Comparable)

/// Severity of a validation finding. Ordered: info < caution < serious < urgent < emergency.
///
/// Tier 1 meaning:
/// - `.info`     — purely informational (e.g. "very high AI confidence, interpret with caution").
/// - `.caution`  — advisory; shown inline. Examples: age ≥ 65 + advanced exercise, unverified-by-KG.
/// - `.serious`  — contraindication requiring explicit user acknowledgement before plan display.
///                 Examples: osteoporosis + impact, blood-thinners + balance, KG-contraindicated substitute.
/// - `.urgent`   — condition-level red flag (AI-flagged red-flag condition without a message, etc.).
/// - `.emergency`— symptom-level red flag requiring immediate medical referral.
///                 Examples: cardiac pattern, cauda equina, stroke signs, DVT signs.
///
/// UI treatment (`AnalyzingView` / `RehabPlanView`):
/// - `.emergency` → redirect to `EmergencyRedirectView` (no normal result shown).
/// - `.serious`   → `SeriousWarningModal` acknowledgement gate (gated behind feature flag).
/// - `.urgent`    → inline warning banner (existing behavior).
/// - `.caution`   → inline badge.
/// - `.info`      → inline badge.
enum ValidationSeverity: Int, Comparable {
    case info = 0
    case caution = 1
    case serious = 2
    case urgent = 3
    case emergency = 4

    static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Validation Result

struct ValidationResult {
    let isValid: Bool
    let warnings: [ValidationWarning]
    let appliedFixes: [String]

    var hasWarnings: Bool { !warnings.isEmpty }

    /// Highest severity across all warnings, or `.info` if no warnings.
    /// Used to drive navigation routing (emergency redirect vs. serious modal vs. inline display).
    var worstSeverity: ValidationSeverity {
        warnings.map(\.severity).max() ?? .info
    }
}

struct ValidationWarning {
    /// Source-compat alias so existing `ValidationWarning.Severity` references keep working.
    typealias Severity = ValidationSeverity

    let severity: ValidationSeverity
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

        let isValid = warnings.filter({ $0.severity >= .serious }).isEmpty
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
    ///
    /// Severity classification (Tier 1):
    /// - `.emergency` — 911-level: cardiac, stroke, meningitis, cauda equina, DVT. These trigger
    ///                  `EmergencyRedirectView` and the normal analysis result is NOT shown.
    /// - `.urgent`    — ER/provider visit but not 911-level: suspected fracture. Shown as a banner.
    private static let symptomPatterns: [(keywords: [String], region: String?, severity: ValidationSeverity, message: String)] = [
        // Cardiac — 911
        (["chest pain", "shortness of breath"],
         "chest",
         .emergency,
         "Chest pain with difficulty breathing may indicate a cardiac emergency. Please call 911 or go to the ER immediately."),

        // Stroke — 911
        (["sudden weakness", "numbness", "one side"],
         nil,
         .emergency,
         "Sudden weakness or numbness on one side could be signs of a stroke. Please call 911 immediately."),

        // Meningitis — ER
        (["severe headache", "stiff neck", "fever"],
         nil,
         .emergency,
         "A severe headache with neck stiffness and fever could indicate meningitis. Seek emergency medical care."),

        // Cauda Equina Syndrome — ER
        (["loss of bladder", "back pain", "leg weakness"],
         "lower_back",
         .emergency,
         "Loss of bladder or bowel control with back pain and leg weakness may indicate cauda equina syndrome. This is a medical emergency — go to the ER immediately."),

        (["saddle numbness", "back pain"],
         "lower_back",
         .emergency,
         "Numbness in the saddle area with back pain may indicate cauda equina syndrome. This is a medical emergency."),

        // DVT — ER (blood clot risk)
        (["calf pain", "swelling", "redness"],
         nil,
         .emergency,
         "Calf pain with swelling and redness could indicate a blood clot (DVT). Please seek immediate medical attention."),

        // Fracture indicators — urgent provider visit, not 911
        (["deformity", "unable to bear weight"],
         nil,
         .urgent,
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
            if assessment.painIntensity >= 9 && assessment.painOnsets.contains("Sudden") {
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
            let regionMatches: Bool
            if let region = pattern.region {
                regionMatches = regionKeys.contains(where: { $0.contains(region) })
            } else {
                regionMatches = true
            }

            if allKeywordsMatch && regionMatches {
                alerts.append(ValidationWarning(severity: pattern.severity, message: pattern.message))
            }
        }

        // Night pain + weight loss — suspicious for tumor/infection workup. Urgent provider visit
        // (not 911-level emergency).
        if allText.contains("night pain") && allText.contains("weight loss") {
            alerts.append(ValidationWarning(
                severity: .urgent,
                message: "Persistent night pain combined with unexplained weight loss needs medical evaluation to rule out serious conditions. Please see a doctor."
            ))
        }

        return RedFlagResult(triggered: !alerts.isEmpty, alerts: alerts)
    }

    /// Overload for the wellness flow: run the same 7-pattern symptom match on free-form
    /// strings (user goal descriptions, stated concerns, custom fields). The injury flow
    /// extracts these from `PainAssessment.aggravatingFactors` / `.relievingFactors` /
    /// `.additionalNotes`; the wellness flow has no such structure, so we accept the
    /// strings directly.
    ///
    /// Note: region-scoped patterns (e.g. cauda equina requires `"lower_back"` region)
    /// cannot fire from this entry point because wellness has no region data. That's the
    /// intended behavior — if a user types symptoms that match a region-bound pattern,
    /// they should be in the injury flow, not the wellness flow.
    static func check(symptomStrings: [String]) -> RedFlagResult {
        var alerts: [ValidationWarning] = []
        let allText = symptomStrings.joined(separator: " ").lowercased()

        for pattern in symptomPatterns where pattern.region == nil {
            let allKeywordsMatch = pattern.keywords.allSatisfy { allText.contains($0) }
            if allKeywordsMatch {
                alerts.append(ValidationWarning(severity: pattern.severity, message: pattern.message))
            }
        }

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
                    // Tier 1 severity: contraindicated exercises against a user's condition are
                    // `.serious` — the user must acknowledge the risk before the plan is shown,
                    // OR request a safer plan. Previously this was `.caution` and silently passed
                    // through as an inline note.
                    warnings.append(ValidationWarning(
                        severity: .serious,
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

// MARK: - Knowledge Graph Validator

struct KnowledgeGraphValidator {

    /// Validate exercises against the medical knowledge graph.
    /// Returns warnings for contraindicated exercises and the full verification result.
    static func validate(
        exercises: [RehabExercise],
        conditions: [String],
        knowledgeGraph: KnowledgeGraphService = .shared
    ) -> (warnings: [ValidationWarning], verification: PlanVerificationResult) {
        let plan = RehabPlan(
            id: UUID(),
            planName: "",
            conditions: conditions,
            exercises: exercises,
            weeklySchedule: [],
            totalWeeks: 0,
            createdDate: Date(),
            notes: nil
        )

        let verification = knowledgeGraph.verifyPlan(plan, conditions: conditions)
        var warnings: [ValidationWarning] = []

        // Add warnings for contraindicated exercises.
        // Tier 1 severity: knowledge-graph-contraindicated → `.serious` (modal gate required).
        // The `exercise` variable is intentionally unused: the `reason` string already names
        // the exercise and condition.
        for (_, reason) in verification.contraindicatedExercises {
            warnings.append(ValidationWarning(
                severity: .serious,
                message: reason
            ))
        }

        // Add warnings for conditions with red flags from the knowledge graph
        for condition in conditions {
            if let redFlags = knowledgeGraph.redFlags(forCondition: condition) {
                for flag in redFlags {
                    warnings.append(ValidationWarning(
                        severity: .info,
                        message: "Knowledge base note for your condition: \(flag)"
                    ))
                }
            }
        }

        return (warnings, verification)
    }
}

// MARK: - Wellness Validators

/// Validates a wellness analysis result (the "what's going on" recommendations stage —
/// before any exercise plan is generated).
///
/// Scope: bounds + red-flag scan of user-supplied strings + confidence cap. The
/// `WellnessRecommendation` model carries no exercises, so per-exercise contraindication
/// checks happen later in `WellnessPlanValidator`.
struct WellnessAnalysisValidator {

    /// Collect free-text strings from a wellness assessment to feed into the red-flag
    /// detector. Covers: custom goal text, specific context, additional notes.
    private static func symptomStrings(from assessments: [WellnessAssessment]) -> [String] {
        var out: [String] = []
        for a in assessments {
            if let s = a.customGoalText, !s.isEmpty { out.append(s) }
            if let s = a.specificContext, !s.isEmpty { out.append(s) }
            if let s = a.additionalNotes, !s.isEmpty { out.append(s) }
        }
        return out
    }

    /// Run the full wellness analysis validation pipeline.
    /// Returns the (unchanged) result + a `ValidationResult` carrying any warnings.
    static func validate(
        _ result: WellnessAnalysisResult,
        assessments: [WellnessAssessment]
    ) -> (result: WellnessAnalysisResult, validation: ValidationResult) {

        var warnings: [ValidationWarning] = []
        var fixes: [String] = []

        // 1. Content bounds: recommendations 1–5, each non-empty title + assessment.
        if result.recommendations.isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "No wellness recommendations were generated."))
        }
        if result.recommendations.count > 5 {
            fixes.append("Trimmed wellness recommendations from \(result.recommendations.count) to 5")
        }
        for rec in result.recommendations {
            if rec.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(ValidationWarning(severity: .info, message: "A wellness recommendation was missing a title."))
            }
            if rec.currentStateAssessment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(ValidationWarning(severity: .info, message: "A wellness recommendation was missing a state assessment."))
            }
        }

        // 2. Summary must be non-empty.
        if result.overallSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append(ValidationWarning(severity: .caution, message: "The wellness summary was empty."))
        }

        // 3. Red-flag scan over user-supplied strings. Emergency hits surface via
        //    `redFlags` return (parallel to the injury flow) so the caller can route
        //    to `EmergencyRedirectView`.
        let redFlags = MedicalRedFlagDetector.check(symptomStrings: symptomStrings(from: assessments))
        warnings.append(contentsOf: redFlags.alerts)

        let isValid = warnings.filter({ $0.severity >= .serious }).isEmpty
        let validation = ValidationResult(isValid: isValid, warnings: warnings, appliedFixes: fixes)
        return (result, validation)
    }
}

/// Validates a generated wellness plan — the stage after recommendations, once concrete
/// exercises exist. Runs KG-based contraindication check against the user's medical
/// conditions (same pattern as `ExerciseSwapViewModel.verifySubstitutes`).
struct WellnessPlanValidator {

    /// Run KG-based contraindication check on each exercise against every condition.
    /// Worst tier wins. `.contraindicated` → `.serious` severity.
    static func validate(
        exercises: [RehabExercise],
        conditions: [String],
        knowledgeGraph: KnowledgeGraphService = .shared
    ) -> [ValidationWarning] {

        // Empty conditions array = nothing to check against. Return cleanly — this is
        // the common case for wellness users (they haven't declared medical conditions).
        guard !conditions.isEmpty else { return [] }

        var warnings: [ValidationWarning] = []

        for exercise in exercises {
            for condition in conditions {
                let tier = knowledgeGraph.verify(exercise: exercise.name, forCondition: condition)
                if case .contraindicated(let reason) = tier {
                    warnings.append(ValidationWarning(severity: .serious, message: reason))
                    break  // first hit per exercise is enough
                }
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

        logger.info("Starting analysis validation pipeline for \(result.conditions.count) condition(s), \(assessments.count) assessment(s)")

        // 1. Content validation
        logger.debug("[1/6] Running content validation...")
        let contentValidation = AnalysisContentValidator.validate(result)
        allWarnings.append(contentsOf: contentValidation.warnings)
        allFixes.append(contentsOf: contentValidation.appliedFixes)
        logger.debug("[1/6] Content validation: \(contentValidation.warnings.count) warnings, \(contentValidation.appliedFixes.count) fixes")

        // 2. Red flag detection from symptoms
        logger.debug("[2/6] Checking symptom red flags...")
        let symptomRedFlags = MedicalRedFlagDetector.check(assessments: assessments)
        var redFlagAlerts = symptomRedFlags.alerts
        logger.debug("[2/6] Symptom red flags: \(symptomRedFlags.alerts.count)")

        // 3. Red flag detection from conditions
        logger.debug("[3/6] Checking condition red flags...")
        let conditionRedFlags = MedicalRedFlagDetector.checkConditions(result.conditions)
        redFlagAlerts.append(contentsOf: conditionRedFlags)
        logger.debug("[3/6] Condition red flags: \(conditionRedFlags.count)")

        // 4. Anatomical relevance check
        logger.debug("[4/6] Checking anatomical relevance...")
        let regions = assessments.map { $0.selectedRegion }
        let anatomicalWarnings = AnatomicalRelevanceChecker.validate(conditions: result.conditions, assessedRegions: regions)
        allWarnings.append(contentsOf: anatomicalWarnings)
        logger.debug("[4/6] Anatomical warnings: \(anatomicalWarnings.count)")

        // 5. Calibrate confidence scores and cap at maximum
        logger.debug("[5/6] Calibrating confidence scores...")
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
        logger.debug("[6/6] Deduplicating conditions...")
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
            isValid: allWarnings.filter({ $0.severity >= .serious }).isEmpty,
            warnings: allWarnings,
            appliedFixes: allFixes
        )

        return (validatedResult, validation, redFlagAlerts)
    }

    /// Run validation on a rehab plan.
    /// Returns the plan, warnings, and an optional knowledge graph verification result.
    static func validateRehabPlan(
        _ plan: RehabPlan,
        conditions: [String],
        userProfile: UserProfile
    ) -> (plan: RehabPlan, warnings: [ValidationWarning], graphVerification: PlanVerificationResult?) {

        var warnings: [ValidationWarning] = []
        var graphVerification: PlanVerificationResult?

        logger.info("Starting rehab plan validation: \(plan.exercises.count) exercises, \(conditions.count) conditions")

        // 1. Exercise contraindication check (hardcoded rules — safety net)
        logger.debug("[Rehab 1/7] Checking hardcoded contraindications...")
        let contraindicationWarnings = ExerciseContraindicationChecker.validate(
            exercises: plan.exercises,
            conditions: conditions
        )
        warnings.append(contentsOf: contraindicationWarnings)
        logger.debug("[Rehab 1/7] Contraindication warnings: \(contraindicationWarnings.count)")

        // 1.5. Knowledge graph validation (comprehensive, deterministic)
        logger.debug("[Rehab 1.5/7] Running knowledge graph validation...")
        let graphResult = KnowledgeGraphValidator.validate(
            exercises: plan.exercises,
            conditions: conditions
        )
        warnings.append(contentsOf: graphResult.warnings)
        graphVerification = graphResult.verification
        let verified = graphResult.verification.exerciseResults.filter { $0.tier == .verified }.count
        let unverified = graphResult.verification.unverifiedExercises.count
        let contraindicated = graphResult.verification.contraindicatedExercises.count
        logger.debug("[Rehab 1.5/7] Knowledge graph: \(verified) verified, \(contraindicated) contraindicated, \(unverified) unverified")

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
                // Tier 1 severity: osteoporosis + impact is a well-documented contraindication
                // (fracture risk). Route through `SeriousWarningModal` — user acknowledges or
                // requests a safer plan.
                warnings.append(ValidationWarning(
                    severity: .serious,
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

        // 7. Medication-aware safety checks
        let meds = userProfile.medications ?? []
        let medsLower = Set(meds.map { $0.lowercased() })

        if medsLower.contains("blood thinners") {
            let hasImpactOrFall = plan.exercises.contains(where: {
                let n = $0.name.lowercased()
                return n.contains("jump") || n.contains("plyometric") || n.contains("balance") || n.contains("single-leg")
            })
            if hasImpactOrFall {
                // Tier 1 severity: blood-thinners + fall-risk exercises → `.serious`
                // (bleeding risk from any fall). Acknowledgement required.
                warnings.append(ValidationWarning(
                    severity: .serious,
                    message: "You take blood thinners. Be extra cautious with balance and impact exercises to avoid falls or bruising. Consider performing these near a wall or support."
                ))
            }
        }

        if medsLower.contains("corticosteroids") {
            warnings.append(ValidationWarning(
                severity: .info,
                message: "Long-term corticosteroid use can weaken tendons. Start with lower resistance and increase gradually."
            ))
        }

        if medsLower.contains("beta blockers") {
            warnings.append(ValidationWarning(
                severity: .info,
                message: "Beta blockers affect heart rate response. Use how you feel (perceived exertion) rather than heart rate to gauge exercise intensity."
            ))
        }

        // 8. Post-surgical restriction checks
        let activeSurgeries = userProfile.surgeries.filter {
            $0.recoveryStatus == "Still recovering" || $0.recoveryStatus == "Have restrictions"
        }
        if !activeSurgeries.isEmpty {
            let surgeryNames = activeSurgeries.map { $0.name }.joined(separator: ", ")
            warnings.append(ValidationWarning(
                severity: .caution,
                message: "You have active surgical recovery (\(surgeryNames)). Follow your surgeon's guidelines and avoid exercises that conflict with your restrictions."
            ))
        }

        logger.info("Rehab plan validation: \(warnings.count) warnings for \(plan.exercises.count) exercises")

        return (plan, warnings, graphVerification)
    }
}
