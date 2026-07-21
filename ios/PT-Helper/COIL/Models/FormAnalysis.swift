import Foundation

// MARK: - 3D Joint Point

/// A single joint's 3D position in meters, relative to the root (pelvis) joint.
struct JointPoint3D: Codable, Equatable {
    let x: Double  // meters
    let y: Double  // meters
    let z: Double  // meters
    let confidence: Double  // 0.0–1.0
}

// MARK: - Pose Frame

/// All detected joints for a single video frame.
struct PoseFrame: Codable {
    let timestamp: Double  // seconds from video start
    let joints: [String: JointPoint3D]  // joint name → 3D position
    let bodyHeight: Double?  // estimated body height in meters (if available)
}

// MARK: - Joint Angle

/// A computed angle at a specific joint.
struct JointAngle: Codable {
    let jointName: String
    let angleDegrees: Double
    let confidence: Double  // min confidence of the three points used
}

// MARK: - Rep Metrics

/// Metrics computed for a single repetition of an exercise.
struct RepMetrics: Codable {
    let repNumber: Int
    let keyAngles: [String: AngleRange]  // joint name → angle range during this rep
    let durationSeconds: Double
    let startTimestamp: Double
    let endTimestamp: Double

    struct AngleRange: Codable {
        let minDegrees: Double
        let maxDegrees: Double
        let rangeOfMotion: Double  // max - min
        let atStart: Double  // angle at start of rep
        let atMid: Double    // angle at midpoint
        let atEnd: Double    // angle at end of rep
    }
}

// MARK: - Data Quality Report

/// Pre-analysis assessment of pose detection data quality.
struct DataQualityReport: Codable {
    let overallScore: Double           // 0.0–1.0
    let frameCoverage: Double          // frames with pose / total frames
    let averageJointCount: Double      // avg joints per frame (out of 17)
    let linkLengthConsistency: Double  // 0.0–1.0 (bone lengths stable across frames)
    let temporalOutlierCount: Int      // frames with sudden joint jumps
    let totalVideoFrames: Int
    let framesWithPose: Int
    let minimumDataThresholdMet: Bool  // enough frames + joints for reliable analysis
    let warnings: [String]
}

// MARK: - Form Analysis Data

/// Per-rep symmetry data: left/right differences at key phases within a rep.
struct RepSymmetryData: Codable {
    let repNumber: Int
    /// Joint name → left-right difference at the minimum angle phase
    let atMinAngle: [String: Double]
    /// Joint name → left-right difference at the midpoint phase
    let atMidAngle: [String: Double]
    /// Joint name → left-right difference at the maximum angle phase
    let atMaxAngle: [String: Double]
}

/// Aggregated metrics from pose analysis of a recorded exercise.
struct FormAnalysisData: Codable {
    let exerciseName: String
    let exerciseCategory: String?
    let targetArea: String
    let totalFramesProcessed: Int
    let videoFPS: Double
    let videoDurationSeconds: Double
    let detectedRepCount: Int
    let repMetrics: [RepMetrics]
    let symmetry: SymmetryData?
    let perRepSymmetry: [RepSymmetryData]?
    let alignment: [AlignmentIssue]
    let averageTempo: Double?  // seconds per rep
    let tempoVariability: Double?  // standard deviation
    let bodyHeight: Double?  // estimated height in meters

    struct SymmetryData: Codable {
        let leftAvgAngles: [String: Double]   // joint name → avg angle
        let rightAvgAngles: [String: Double]
        let differencesDegrees: [String: Double]  // joint name → |left - right|
    }

    struct AlignmentIssue: Codable {
        let description: String
        let affectedReps: Int
        let totalReps: Int
    }

    enum CodingKeys: String, CodingKey {
        case exerciseName, exerciseCategory, targetArea, totalFramesProcessed
        case videoFPS, videoDurationSeconds, detectedRepCount, repMetrics
        case symmetry, perRepSymmetry, alignment, averageTempo, tempoVariability, bodyHeight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        exerciseCategory = try container.decodeIfPresent(String.self, forKey: .exerciseCategory)
        targetArea = try container.decode(String.self, forKey: .targetArea)
        totalFramesProcessed = try container.decode(Int.self, forKey: .totalFramesProcessed)
        videoFPS = try container.decode(Double.self, forKey: .videoFPS)
        videoDurationSeconds = try container.decode(Double.self, forKey: .videoDurationSeconds)
        detectedRepCount = try container.decode(Int.self, forKey: .detectedRepCount)
        repMetrics = try container.decode([RepMetrics].self, forKey: .repMetrics)
        symmetry = try container.decodeIfPresent(SymmetryData.self, forKey: .symmetry)
        perRepSymmetry = try container.decodeIfPresent([RepSymmetryData].self, forKey: .perRepSymmetry)
        alignment = try container.decode([AlignmentIssue].self, forKey: .alignment)
        averageTempo = try container.decodeIfPresent(Double.self, forKey: .averageTempo)
        tempoVariability = try container.decodeIfPresent(Double.self, forKey: .tempoVariability)
        bodyHeight = try container.decodeIfPresent(Double.self, forKey: .bodyHeight)
    }

    init(exerciseName: String, exerciseCategory: String?, targetArea: String,
         totalFramesProcessed: Int, videoFPS: Double, videoDurationSeconds: Double,
         detectedRepCount: Int, repMetrics: [RepMetrics], symmetry: SymmetryData?,
         perRepSymmetry: [RepSymmetryData]? = nil, alignment: [AlignmentIssue],
         averageTempo: Double?, tempoVariability: Double?, bodyHeight: Double?) {
        self.exerciseName = exerciseName
        self.exerciseCategory = exerciseCategory
        self.targetArea = targetArea
        self.totalFramesProcessed = totalFramesProcessed
        self.videoFPS = videoFPS
        self.videoDurationSeconds = videoDurationSeconds
        self.detectedRepCount = detectedRepCount
        self.repMetrics = repMetrics
        self.symmetry = symmetry
        self.perRepSymmetry = perRepSymmetry
        self.alignment = alignment
        self.averageTempo = averageTempo
        self.tempoVariability = tempoVariability
        self.bodyHeight = bodyHeight
    }
}

// MARK: - Form Progress Insights (Cross-Session)

/// Cross-session insights produced by the form analysis Managed Agent.
/// Present only when the agent path ran (≥2 prior sessions of the exercise);
/// nil on the single-call fallback path.
struct FormProgressInsights: Codable, Equatable {
    let progressTrends: [ProgressTrend]
    let recurringIssues: [RecurringIssue]
    let sessionComparison: String

    struct ProgressTrend: Codable, Equatable {
        let metric: String
        let direction: Direction
        let description: String

        enum Direction: String, Codable {
            case improving
            case stable
            case declining
        }
    }

    struct RecurringIssue: Codable, Equatable {
        let issue: String
        let sessionsObserved: Int
        let description: String
    }
}

// MARK: - Form Feedback (AI Response)

/// The structured feedback returned by Claude after analyzing form metrics.
struct FormFeedback: Codable, Identifiable {
    let id: UUID
    let exerciseName: String
    let overallScore: Int  // 0–100
    let verdict: Verdict
    var corrections: [Correction]
    let positivePoints: [String]
    let safetyNotes: [String]
    let dataLimitations: [String]  // defaults to [] if not present in JSON
    let date: Date
    /// Cross-session insights from the agent path; nil on the single-call path.
    var progressInsights: FormProgressInsights?

    // Custom decoder to handle missing dataLimitations / progressInsights in older JSON
    enum CodingKeys: String, CodingKey {
        case id, exerciseName, overallScore, verdict, corrections, positivePoints, safetyNotes, dataLimitations, date, progressInsights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseName = try container.decode(String.self, forKey: .exerciseName)
        overallScore = try container.decode(Int.self, forKey: .overallScore)
        verdict = try container.decode(Verdict.self, forKey: .verdict)
        corrections = try container.decode([Correction].self, forKey: .corrections)
        positivePoints = try container.decode([String].self, forKey: .positivePoints)
        safetyNotes = try container.decode([String].self, forKey: .safetyNotes)
        dataLimitations = try container.decodeIfPresent([String].self, forKey: .dataLimitations) ?? []
        date = try container.decode(Date.self, forKey: .date)
        progressInsights = try container.decodeIfPresent(FormProgressInsights.self, forKey: .progressInsights)
    }

    enum Verdict: String, Codable {
        case excellent
        case good
        case needsWork = "needs_work"
        case concern
    }

    struct Correction: Codable {
        let bodyPart: String
        let issue: String
        let howToFix: String
        var severity: Severity
        var dataReference: String?  // metric that supports this correction

        enum Severity: String, Codable {
            case minor
            case moderate
            case major
        }

        init(bodyPart: String, issue: String, howToFix: String, severity: Severity, dataReference: String? = nil) {
            self.bodyPart = bodyPart
            self.issue = issue
            self.howToFix = howToFix
            self.severity = severity
            self.dataReference = dataReference
        }
    }

    init(id: UUID = UUID(), exerciseName: String, overallScore: Int, verdict: Verdict, corrections: [Correction], positivePoints: [String], safetyNotes: [String], dataLimitations: [String] = [], date: Date = Date(), progressInsights: FormProgressInsights? = nil) {
        self.id = id
        self.exerciseName = exerciseName
        self.overallScore = overallScore
        self.verdict = verdict
        self.corrections = corrections
        self.positivePoints = positivePoints
        self.safetyNotes = safetyNotes
        self.dataLimitations = dataLimitations
        self.date = date
        self.progressInsights = progressInsights
    }
}

// MARK: - Validation Types

/// How confident we are in the form feedback after validation.
enum FormConfidenceLevel: String, Codable {
    case high          // good data quality, rules pass, AI consistent with data
    case moderate      // some data quality issues or minor inconsistencies
    case low           // poor data quality or AI claims don't match data
    case insufficient  // not enough data to validate
}

/// A mismatch between what the AI claimed and what the data shows.
struct ConsistencyIssue: Codable {
    let claim: String           // what AI said
    let dataEvidence: String    // what the data shows
    let action: String          // what we did about it (removed, downgraded, etc.)
}

/// Result of running the FormFeedbackValidationPipeline.
struct FormValidationResult {
    let isValid: Bool
    let warnings: [ValidationWarning]
    let appliedFixes: [String]
    let consistencyIssues: [ConsistencyIssue]
    let confidenceLevel: FormConfidenceLevel
    let ruleCheckResults: [RuleCheckResult]
}

/// Result of a single biomechanical rule check.
struct RuleCheckResult {
    let ruleName: String
    let result: SafetyCheckResult
}

/// Outcome of a deterministic safety check.
enum SafetyCheckResult {
    case pass
    case caution(String)
    case danger(String)
}

/// Wrapper combining AI feedback with validation results and data quality.
struct ValidatedFormFeedback {
    let feedback: FormFeedback
    let validation: FormValidationResult
    let dataQuality: DataQualityReport

    /// Convenience: the feedback's ID for state comparison.
    var id: UUID { feedback.id }
}

// MARK: - Form Analysis State

/// Tracks the current state of the form analysis pipeline.
enum FormAnalysisState: Equatable {
    case idle
    case recording
    case processing(progress: Double)
    case analyzing
    case complete(ValidatedFormFeedback)
    case error(String)

    static func == (lhs: FormAnalysisState, rhs: FormAnalysisState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.analyzing, .analyzing):
            return true
        case let (.processing(a), .processing(b)):
            return a == b
        case let (.complete(a), .complete(b)):
            return a.id == b.id
        case let (.error(a), .error(b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - H36M-Style Joint Names for Vision 3D

/// Maps Apple Vision 3D body pose joint names to human-readable identifiers.
enum BodyJoint3D: String, CaseIterable {
    case root          // pelvis center
    case head
    case neck
    case spine         // mid-spine
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
    case topHead

    /// Joint pairs for symmetry analysis
    static let symmetryPairs: [(left: BodyJoint3D, right: BodyJoint3D)] = [
        (.leftShoulder, .rightShoulder),
        (.leftElbow, .rightElbow),
        (.leftWrist, .rightWrist),
        (.leftHip, .rightHip),
        (.leftKnee, .rightKnee),
        (.leftAnkle, .rightAnkle),
    ]

    /// Common angle definitions: (proximal, vertex, distal) joints
    static let commonAngles: [(name: String, proximal: BodyJoint3D, vertex: BodyJoint3D, distal: BodyJoint3D)] = [
        ("left_knee", .leftHip, .leftKnee, .leftAnkle),
        ("right_knee", .rightHip, .rightKnee, .rightAnkle),
        ("left_hip", .leftShoulder, .leftHip, .leftKnee),
        ("right_hip", .rightShoulder, .rightHip, .rightKnee),
        ("left_elbow", .leftShoulder, .leftElbow, .leftWrist),
        ("right_elbow", .rightShoulder, .rightElbow, .rightWrist),
        ("left_shoulder", .leftHip, .leftShoulder, .leftElbow),
        ("right_shoulder", .rightHip, .rightShoulder, .rightElbow),
        ("trunk", .neck, .spine, .root),
    ]
}
