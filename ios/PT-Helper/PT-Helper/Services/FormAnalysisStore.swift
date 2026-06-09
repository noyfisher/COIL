import Foundation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Form Analysis Record

/// Compact summary of one completed form-analysis session, persisted to
/// `users/{uid}/formAnalyses/{id}` so the cross-session form agent can compare
/// the user's form across sessions of the same exercise.
///
/// Deliberately small (~2-5KB): per-rep key angles (min/max/ROM only), symmetry
/// differences, alignment summaries, tempo, data quality, and the final
/// feedback (score/verdict/corrections WITHOUT howToFix). No raw pose frames,
/// no per-rep phase symmetry.
///
/// Server-side consumer: `fetchFormHistoryData` in functions/src/firestore-queries.ts —
/// keep field names in sync.
struct FormAnalysisRecord {
    let id: UUID
    let exerciseName: String
    let exerciseCategory: String?
    let targetArea: String
    let createdAt: Date
    let repCount: Int
    let reps: [RepSummary]
    let symmetryDifferences: [String: Double]?
    let alignmentIssues: [String]
    let averageTempo: Double?
    let tempoVariability: Double?
    let dataQualityScore: Double
    let score: Int
    let verdict: String
    let corrections: [CorrectionSummary]
    /// "agent" or "single_call" — which AI path produced the feedback.
    let source: String

    struct RepSummary {
        let repNumber: Int
        let durationSeconds: Double
        /// Joint name → {min, max, rom} in degrees.
        let angles: [String: AngleSummary]

        struct AngleSummary {
            let min: Double
            let max: Double
            let rom: Double
        }
    }

    struct CorrectionSummary {
        let bodyPart: String
        let issue: String
        let severity: String
        let dataReference: String?
    }
}

// MARK: - Record Construction

extension FormAnalysisRecord {
    /// Build a compact record from the analysis pipeline outputs.
    /// Pure — unit-testable without Firestore.
    static func makeRecord(
        metrics: FormAnalysisData,
        feedback: FormFeedback,
        dataQuality: DataQualityReport,
        source: String
    ) -> FormAnalysisRecord {
        let reps = metrics.repMetrics.map { rep in
            RepSummary(
                repNumber: rep.repNumber,
                durationSeconds: rep.durationSeconds,
                angles: rep.keyAngles.mapValues { range in
                    RepSummary.AngleSummary(
                        min: range.minDegrees,
                        max: range.maxDegrees,
                        rom: range.rangeOfMotion
                    )
                }
            )
        }

        let alignmentIssues = metrics.alignment.map {
            "\($0.description) (\($0.affectedReps)/\($0.totalReps) reps)"
        }

        let corrections = feedback.corrections.map {
            CorrectionSummary(
                bodyPart: $0.bodyPart,
                issue: $0.issue,
                severity: $0.severity.rawValue,
                dataReference: $0.dataReference
            )
        }

        return FormAnalysisRecord(
            id: feedback.id,
            exerciseName: metrics.exerciseName,
            exerciseCategory: metrics.exerciseCategory,
            targetArea: metrics.targetArea,
            createdAt: feedback.date,
            repCount: metrics.detectedRepCount,
            reps: reps,
            symmetryDifferences: metrics.symmetry?.differencesDegrees,
            alignmentIssues: alignmentIssues,
            averageTempo: metrics.averageTempo,
            tempoVariability: metrics.tempoVariability,
            dataQualityScore: dataQuality.overallScore,
            score: feedback.overallScore,
            verdict: feedback.verdict.rawValue,
            corrections: corrections,
            source: source
        )
    }

    /// Firestore document representation. Field names consumed server-side by
    /// fetchFormHistoryData — keep in sync.
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "exerciseName": exerciseName,
            "targetArea": targetArea,
            "createdAt": Timestamp(date: createdAt),
            "repCount": repCount,
            "reps": reps.map { rep -> [String: Any] in
                [
                    "repNumber": rep.repNumber,
                    "durationSeconds": rep.durationSeconds,
                    "angles": rep.angles.mapValues { angle -> [String: Any] in
                        ["min": angle.min, "max": angle.max, "rom": angle.rom]
                    },
                ]
            },
            "alignmentIssues": alignmentIssues,
            "dataQualityScore": dataQualityScore,
            "score": score,
            "verdict": verdict,
            "corrections": corrections.map { c -> [String: Any] in
                var dict: [String: Any] = [
                    "bodyPart": c.bodyPart,
                    "issue": c.issue,
                    "severity": c.severity,
                ]
                if let ref = c.dataReference { dict["dataReference"] = ref }
                return dict
            },
            "source": source,
        ]
        if let exerciseCategory { data["exerciseCategory"] = exerciseCategory }
        if let symmetryDifferences, !symmetryDifferences.isEmpty {
            data["symmetryDifferences"] = symmetryDifferences
        }
        if let averageTempo { data["averageTempo"] = averageTempo }
        if let tempoVariability { data["tempoVariability"] = tempoVariability }
        return data
    }
}

// MARK: - Store Protocol

/// Persistence for form-analysis sessions. Protocol-based for test injection.
protocol FormAnalysisStoreProtocol {
    /// Persist a completed analysis. Errors are swallowed and logged —
    /// persistence failure must never break the analysis UX.
    func save(_ record: FormAnalysisRecord) async

    /// Number of PRIOR persisted sessions for this exercise.
    /// Returns 0 on any error (safe default → single-call Haiku path).
    func priorSessionCount(exerciseName: String) async -> Int
}

// MARK: - Firestore Store

/// Firestore-backed store at `users/{uid}/formAnalyses/{id}`.
/// (Unlike `AnalysisResultStore`, which is UserDefaults-only.)
final class FormAnalysisStore: FormAnalysisStoreProtocol {
    static let shared = FormAnalysisStore()

    private let db = Firestore.firestore()

    private init() {}

    func save(_ record: FormAnalysisRecord) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.data.error("FormAnalysisStore.save: no authenticated user")
            return
        }

        await MainActor.run {
            SessionLogger.shared.log(.firestoreWrite, category: .data, message: "Form analysis saved",
                                      metadata: ["analysisId": record.id.uuidString,
                                                  "exercise": record.exerciseName,
                                                  "source": record.source])
        }

        do {
            try await db.collection("users").document(uid).collection("formAnalyses")
                .document(record.id.uuidString)
                .setData(record.firestoreData)
        } catch {
            AppLogger.data.error("Error saving form analysis: \(error.localizedDescription)")
        }
    }

    func priorSessionCount(exerciseName: String) async -> Int {
        guard let uid = Auth.auth().currentUser?.uid else { return 0 }

        do {
            // Equality-only count aggregation — no composite index needed
            // (the server's equality+orderBy history query is what requires one).
            let query = db.collection("users").document(uid).collection("formAnalyses")
                .whereField("exerciseName", isEqualTo: exerciseName)
            let snapshot = try await query.count.getAggregation(source: .server)
            return snapshot.count.intValue
        } catch {
            AppLogger.data.error("Error counting form analyses: \(error.localizedDescription)")
            return 0
        }
    }
}
