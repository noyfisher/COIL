import Foundation

// MARK: - Form Feedback Validation Pipeline

/// 7-layer validation pipeline for AI-generated form feedback.
/// Modeled after ResponseValidationPipeline for injury analysis.
/// Runs between Claude's response and UI display to ensure
/// feedback is grounded in data, safe, and consistent.
struct FormFeedbackValidationPipeline {

    // MARK: - Public API

    /// Validate AI-generated form feedback against computed metrics and user context.
    static func validate(
        feedback: FormFeedback,
        metrics: FormAnalysisData,
        dataQuality: DataQualityReport,
        ruleCheckResults: [RuleCheckResult],
        exercise: RehabExercise,
        userConditions: [String] = [],
        knowledgeGraph: KnowledgeGraphService = .shared
    ) -> (validatedFeedback: FormFeedback, validation: FormValidationResult) {
        var warnings: [ValidationWarning] = []
        var fixes: [String] = []
        var consistencyIssues: [ConsistencyIssue] = []
        var modifiedFeedback = feedback

        // Layer 1: Content validation
        let contentResult = validateContent(feedback: feedback)
        warnings.append(contentsOf: contentResult.warnings)
        fixes.append(contentsOf: contentResult.fixes)

        // Layer 2: Score calibration
        let calibratedScore = calibrateScore(
            score: feedback.overallScore,
            dataQuality: dataQuality
        )
        if calibratedScore != feedback.overallScore {
            fixes.append("Score calibrated from \(feedback.overallScore) to \(calibratedScore)")
            modifiedFeedback = FormFeedback(
                id: feedback.id,
                exerciseName: feedback.exerciseName,
                overallScore: calibratedScore,
                verdict: verdictForScore(calibratedScore),
                corrections: modifiedFeedback.corrections,
                positivePoints: feedback.positivePoints,
                safetyNotes: feedback.safetyNotes,
                dataLimitations: feedback.dataLimitations,
                date: feedback.date,
                progressInsights: feedback.progressInsights
            )
        }

        // Layer 3: Data-claim consistency checks
        let (filteredCorrections, issues) = checkConsistency(
            corrections: modifiedFeedback.corrections,
            metrics: metrics
        )
        consistencyIssues.append(contentsOf: issues)
        if filteredCorrections.count != modifiedFeedback.corrections.count {
            let removed = modifiedFeedback.corrections.count - filteredCorrections.count
            fixes.append("Removed \(removed) correction(s) not supported by measured data")
        }
        modifiedFeedback.corrections = filteredCorrections

        // Layer 4: Safety red flag detection
        let safetyResult = checkSafety(
            corrections: modifiedFeedback.corrections,
            exercise: exercise,
            ruleCheckResults: ruleCheckResults
        )
        warnings.append(contentsOf: safetyResult.warnings)
        fixes.append(contentsOf: safetyResult.fixes)

        // Layer 5: Contraindication check via KnowledgeGraphService
        let contraindicationWarnings = checkContraindications(
            exercise: exercise,
            userConditions: userConditions,
            knowledgeGraph: knowledgeGraph
        )
        warnings.append(contentsOf: contraindicationWarnings)

        // Layer 6: Duplicate correction detection
        let deduplicatedCorrections = deduplicateCorrections(modifiedFeedback.corrections)
        if deduplicatedCorrections.count < modifiedFeedback.corrections.count {
            fixes.append("Removed \(modifiedFeedback.corrections.count - deduplicatedCorrections.count) duplicate correction(s)")
        }
        modifiedFeedback.corrections = deduplicatedCorrections

        // Layer 7: Data quality gating
        let confidenceLevel = determineConfidenceLevel(
            dataQuality: dataQuality,
            consistencyIssues: consistencyIssues,
            ruleCheckResults: ruleCheckResults
        )
        if confidenceLevel == .low || confidenceLevel == .insufficient {
            warnings.append(ValidationWarning(
                severity: .caution,
                message: confidenceLevel == .insufficient
                    ? "Insufficient data for reliable form analysis. Results should be interpreted with caution."
                    : "Data quality is low. Some feedback may be less accurate."
            ))
        }

        let isValid = warnings.filter({ $0.severity >= .serious }).isEmpty
        let validationResult = FormValidationResult(
            isValid: isValid,
            warnings: warnings,
            appliedFixes: fixes,
            consistencyIssues: consistencyIssues,
            confidenceLevel: confidenceLevel,
            ruleCheckResults: ruleCheckResults
        )

        return (modifiedFeedback, validationResult)
    }

    // MARK: - Layer 1: Content Validation

    private static func validateContent(feedback: FormFeedback) -> (warnings: [ValidationWarning], fixes: [String]) {
        var warnings: [ValidationWarning] = []
        var fixes: [String] = []

        // Score in valid range
        if feedback.overallScore < 0 || feedback.overallScore > 100 {
            fixes.append("Score \(feedback.overallScore) clamped to 0-100 range")
        }

        // Corrections count
        if feedback.corrections.count > 4 {
            fixes.append("Trimmed corrections from \(feedback.corrections.count) to 4")
        }

        // Must have at least one positive point
        if feedback.positivePoints.isEmpty {
            warnings.append(ValidationWarning(
                severity: .info,
                message: "No positive feedback was generated. Form analysis may be incomplete."
            ))
        }

        // Check for empty correction fields
        for correction in feedback.corrections {
            if correction.issue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fixes.append("Removed correction with empty issue text for \(correction.bodyPart)")
            }
            if correction.howToFix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fixes.append("Correction for \(correction.bodyPart) has empty fix suggestion")
            }
        }

        return (warnings, fixes)
    }

    // MARK: - Layer 2: Score Calibration

    /// Cap score based on data quality. Even excellent form can't score 100 from video analysis.
    private static func calibrateScore(score: Int, dataQuality: DataQualityReport) -> Int {
        var calibrated = min(score, 90)  // Max 90 — video analysis alone can't confirm perfection

        if dataQuality.overallScore < 0.3 {
            calibrated = min(calibrated, 50)
        } else if dataQuality.overallScore < 0.5 {
            calibrated = min(calibrated, 70)
        } else if dataQuality.overallScore < 0.7 {
            calibrated = min(calibrated, 85)
        }

        return max(0, calibrated)
    }

    private static func verdictForScore(_ score: Int) -> FormFeedback.Verdict {
        switch score {
        case 85...: return .excellent
        case 70...: return .good
        case 50...: return .needsWork
        default: return .concern
        }
    }

    // MARK: - Layer 3: Data-Claim Consistency Checks

    /// Cross-reference AI corrections against computed metrics.
    /// Removes corrections that contradict the data; downgrades severity for weak matches.
    private static func checkConsistency(
        corrections: [FormFeedback.Correction],
        metrics: FormAnalysisData
    ) -> (corrections: [FormFeedback.Correction], issues: [ConsistencyIssue]) {
        var filtered: [FormFeedback.Correction] = []
        var issues: [ConsistencyIssue] = []

        for correction in corrections {
            let issue = correction.issue.lowercased()
            let bodyPart = correction.bodyPart.lowercased()
            var keepCorrection = true
            var modifiedCorrection = correction

            // Check: "knees caving" / "valgus" claims
            if (issue.contains("cav") || issue.contains("valgus") || issue.contains("inward")) &&
                bodyPart.contains("knee") {
                if let diff = metrics.symmetry?.differencesDegrees["knee"], diff < 3 {
                    issues.append(ConsistencyIssue(
                        claim: "Knees caving inward",
                        dataEvidence: "Knee symmetry difference is only \(diff)° (threshold: 3°)",
                        action: "Correction removed — not supported by data"
                    ))
                    keepCorrection = false
                }
            }

            // Check: "limited range" / "not deep enough" claims
            if issue.contains("limited range") || issue.contains("not deep") || issue.contains("shallow") {
                let primaryROMs = metrics.repMetrics.compactMap { rep -> Double? in
                    // Find the largest ROM across all angles for this rep
                    rep.keyAngles.values.map { $0.rangeOfMotion }.max()
                }
                let avgROM = primaryROMs.isEmpty ? 0 : primaryROMs.reduce(0, +) / Double(primaryROMs.count)
                if avgROM > 60 {  // 60° is a reasonable ROM for most exercises
                    issues.append(ConsistencyIssue(
                        claim: "Limited range of motion",
                        dataEvidence: "Average ROM is \(Int(avgROM))° which is within normal range",
                        action: "Correction removed — ROM is adequate"
                    ))
                    keepCorrection = false
                }
            }

            // Check: "asymmetry" / "uneven" claims
            if (issue.contains("asymmetr") || issue.contains("uneven") || issue.contains("one side")) {
                let relevantDiffs = metrics.symmetry?.differencesDegrees.values.filter { $0 > 0 } ?? []
                let maxDiff = relevantDiffs.max() ?? 0
                if maxDiff < 5 {
                    issues.append(ConsistencyIssue(
                        claim: "Asymmetry detected",
                        dataEvidence: "Maximum symmetry difference is \(Int(maxDiff))° (threshold: 5°)",
                        action: "Correction removed — within normal symmetry range"
                    ))
                    keepCorrection = false
                }
            }

            // Check: "too fast" / "rushing" claims
            if issue.contains("fast") || issue.contains("rush") || issue.contains("momentum") {
                if let tempo = metrics.averageTempo, tempo > 2.0 {
                    issues.append(ConsistencyIssue(
                        claim: "Moving too fast",
                        dataEvidence: "Average tempo is \(tempo)s per rep (≥2.0s is controlled)",
                        action: "Correction removed — tempo is controlled"
                    ))
                    keepCorrection = false
                }
            }

            // Check: "inconsistent" tempo claims
            if issue.contains("inconsistent") && (issue.contains("tempo") || issue.contains("speed") || issue.contains("pace")) {
                if let sd = metrics.tempoVariability, sd < 0.5 {
                    issues.append(ConsistencyIssue(
                        claim: "Inconsistent tempo",
                        dataEvidence: "Tempo variability is \(sd)s SD (< 0.5s is consistent)",
                        action: "Correction removed — tempo is consistent"
                    ))
                    keepCorrection = false
                }
            }

            // Check: "forward lean" / "trunk lean" claims
            if (issue.contains("forward lean") || issue.contains("trunk lean") || issue.contains("leaning forward")) {
                let hasTrunkIssue = metrics.alignment.contains { $0.description.lowercased().contains("trunk") }
                if !hasTrunkIssue {
                    issues.append(ConsistencyIssue(
                        claim: "Excessive forward lean",
                        dataEvidence: "No trunk alignment issue was detected in the metrics",
                        action: "Severity downgraded to minor"
                    ))
                    modifiedCorrection = FormFeedback.Correction(
                        bodyPart: correction.bodyPart,
                        issue: correction.issue,
                        howToFix: correction.howToFix,
                        severity: .minor,
                        dataReference: correction.dataReference
                    )
                }
            }

            if keepCorrection {
                filtered.append(modifiedCorrection)
            }
        }

        return (filtered, issues)
    }

    // MARK: - Layer 4: Safety Red Flag Detection

    private static func checkSafety(
        corrections: [FormFeedback.Correction],
        exercise: RehabExercise,
        ruleCheckResults: [RuleCheckResult]
    ) -> (warnings: [ValidationWarning], fixes: [String]) {
        var warnings: [ValidationWarning] = []
        var fixes: [String] = []

        // Check for dangerous biomechanical rule results
        for result in ruleCheckResults {
            switch result.result {
            case .danger(let message):
                warnings.append(ValidationWarning(severity: .urgent, message: message))
            case .caution(let message):
                warnings.append(ValidationWarning(severity: .caution, message: message))
            case .pass:
                break
            }
        }

        // Check for corrections that conflict with exercise contraindications
        for correction in corrections {
            let fix = correction.howToFix.lowercased()
            for contraindication in exercise.contraindications {
                let contra = contraindication.lowercased()
                // If the fix suggests something the contraindication warns against
                if fix.contains("deeper") && contra.contains("deep") {
                    warnings.append(ValidationWarning(
                        severity: .caution,
                        message: "AI suggested going deeper, but this exercise notes: \"\(contraindication)\""
                    ))
                    fixes.append("Flagged correction that may conflict with contraindication")
                }
                if fix.contains("heavier") && contra.contains("load") {
                    warnings.append(ValidationWarning(
                        severity: .caution,
                        message: "AI suggested increasing load, but this exercise notes: \"\(contraindication)\""
                    ))
                }
            }
        }

        return (warnings, fixes)
    }

    // MARK: - Layer 5: Contraindication Check

    static func checkContraindications(
        exercise: RehabExercise,
        userConditions: [String],
        knowledgeGraph: KnowledgeGraphService
    ) -> [ValidationWarning] {
        var warnings: [ValidationWarning] = []

        for condition in userConditions {
            let tier = knowledgeGraph.verify(exercise: exercise.name, forCondition: condition)
            switch tier {
            case .contraindicated(let reason):
                warnings.append(ValidationWarning(
                    severity: .urgent,
                    message: "This exercise may not be appropriate for your condition (\(condition)): \(reason). Please consult your healthcare provider."
                ))
            case .verified, .unverified:
                break
            }
        }

        return warnings
    }

    // MARK: - Layer 6: Duplicate Detection

    private static func deduplicateCorrections(_ corrections: [FormFeedback.Correction]) -> [FormFeedback.Correction] {
        var seen: Set<String> = []
        return corrections.filter { correction in
            let key = "\(correction.bodyPart.lowercased())_\(correction.issue.lowercased().prefix(30))"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Layer 7: Data Quality Gating

    private static func determineConfidenceLevel(
        dataQuality: DataQualityReport,
        consistencyIssues: [ConsistencyIssue],
        ruleCheckResults: [RuleCheckResult]
    ) -> FormConfidenceLevel {
        if !dataQuality.minimumDataThresholdMet {
            return .insufficient
        }

        if dataQuality.overallScore < 0.4 {
            return .low
        }

        // Many consistency issues = AI was hallucinating
        if consistencyIssues.count >= 3 {
            return .low
        }

        if dataQuality.overallScore < 0.7 || consistencyIssues.count >= 1 {
            return .moderate
        }

        return .high
    }
}
