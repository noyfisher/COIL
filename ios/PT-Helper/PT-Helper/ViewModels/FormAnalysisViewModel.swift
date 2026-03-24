import Foundation

// MARK: - AI Response Type

/// Decodable wrapper for the Claude form analysis JSON response.
private struct AIFormFeedbackResponse: Decodable {
    let overallScore: Int
    let verdict: String
    let corrections: [AICorrection]
    let positivePoints: [String]
    let safetyNotes: [String]
    let dataLimitations: [String]?

    struct AICorrection: Decodable {
        let bodyPart: String
        let issue: String
        let howToFix: String
        let severity: String
        let dataReference: String?
    }
}

// MARK: - ViewModel

@MainActor
class FormAnalysisViewModel: ObservableObject {

    // MARK: - Published State

    @Published var state: FormAnalysisState = .idle
    @Published var processingProgress: Double = 0

    // MARK: - Dependencies

    private let apiService: ClaudeAPIServiceProtocol
    private let poseDetector: PoseDetectionService
    private let analysisEngine: PoseAnalysisEngine
    private let qualityScorer: DataQualityScorer
    private let ruleEngine: BiomechanicalRuleEngine

    /// User's medical conditions for contraindication checking.
    var userConditions: [String] = []

    init(
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared,
        poseDetector: PoseDetectionService = .shared,
        analysisEngine: PoseAnalysisEngine = .shared,
        qualityScorer: DataQualityScorer = .shared,
        ruleEngine: BiomechanicalRuleEngine = .shared
    ) {
        self.apiService = apiService
        self.poseDetector = poseDetector
        self.analysisEngine = analysisEngine
        self.qualityScorer = qualityScorer
        self.ruleEngine = ruleEngine
    }

    // MARK: - Main Pipeline

    /// Run the full form analysis pipeline: video → pose detection → metrics → AI feedback.
    func analyzeVideo(url: URL, exercise: RehabExercise) async {
        state = .processing(progress: 0)
        processingProgress = 0

        SessionLogger.shared.log(.buttonTapped, category: .userAction,
                                  message: "Form analysis started",
                                  metadata: ["exercise": exercise.name])

        do {
            // Step 1: Get video metadata
            let fps = try await poseDetector.getVideoFPS(from: url)
            let duration = try await poseDetector.getVideoDuration(from: url)

            // Step 2: Detect 3D poses
            let poses = try await poseDetector.detectPoses(from: url) { [weak self] progress in
                self?.processingProgress = progress * 0.7  // 70% of progress is pose detection
                self?.state = .processing(progress: progress * 0.7)
            }

            state = .processing(progress: 0.70)
            processingProgress = 0.70

            // Step 3: Score data quality
            let totalFrames = Int(duration * fps) / 2  // subsample rate of 2
            let dataQuality = qualityScorer.score(
                poses: poses,
                totalVideoFrames: totalFrames,
                exercise: exercise
            )

            state = .processing(progress: 0.75)
            processingProgress = 0.75

            // Step 4: Analyze poses (compute metrics)
            let analysisData = analysisEngine.analyze(
                poses: poses,
                exercise: exercise,
                videoFPS: fps,
                videoDuration: duration
            )

            // Step 5: Run biomechanical rule checks
            let ruleCheckResults = ruleEngine.check(metrics: analysisData, exercise: exercise)

            state = .processing(progress: 0.85)
            processingProgress = 0.85

            // Step 6: Build message and send to Claude (include data quality)
            state = .analyzing
            let userMessage = buildUserMessage(metrics: analysisData, exercise: exercise, dataQuality: dataQuality)

            let response = try await apiService.sendMessage(
                requestType: .form_analysis,
                userMessage: userMessage
            )

            // Step 7: Parse AI response
            let feedback = try parseFormFeedback(from: response, exerciseName: exercise.name)

            // Step 8: Run validation pipeline (7 layers)
            let (validatedFeedback, validationResult) = FormFeedbackValidationPipeline.validate(
                feedback: feedback,
                metrics: analysisData,
                dataQuality: dataQuality,
                ruleCheckResults: ruleCheckResults,
                exercise: exercise,
                userConditions: userConditions
            )

            let result = ValidatedFormFeedback(
                feedback: validatedFeedback,
                validation: validationResult,
                dataQuality: dataQuality
            )

            state = .complete(result)

            AnalyticsService.shared.log(.formAnalysisCompleted, parameters: [
                "exercise": exercise.name,
                "score": validatedFeedback.overallScore,
                "verdict": validatedFeedback.verdict.rawValue,
                "corrections_count": validatedFeedback.corrections.count,
                "reps_detected": analysisData.detectedRepCount,
                "confidence_level": validationResult.confidenceLevel.rawValue,
                "consistency_issues": validationResult.consistencyIssues.count,
                "data_quality": String(format: "%.2f", dataQuality.overallScore),
            ])

            SessionLogger.shared.log(.stateUpdated, category: .lifecycle,
                                      message: "Form analysis completed",
                                      metadata: [
                                          "exercise": exercise.name,
                                          "score": "\(validatedFeedback.overallScore)",
                                          "verdict": validatedFeedback.verdict.rawValue,
                                          "repsDetected": "\(analysisData.detectedRepCount)",
                                          "confidenceLevel": validationResult.confidenceLevel.rawValue,
                                          "dataQuality": String(format: "%.2f", dataQuality.overallScore),
                                          "fixes": "\(validationResult.appliedFixes.count)",
                                      ])

        } catch {
            state = .error(error.localizedDescription)

            SessionLogger.shared.log(.errorOccurred, category: .error,
                                      message: "Form analysis failed",
                                      metadata: ["error": error.localizedDescription])
        }
    }

    /// Reset to idle state for a new analysis.
    func reset() {
        state = .idle
        processingProgress = 0
    }

    // MARK: - Message Construction

    /// Build the structured user message for Claude with exercise context + computed metrics + data quality.
    func buildUserMessage(metrics: FormAnalysisData, exercise: RehabExercise, dataQuality: DataQualityReport? = nil) -> String {
        var message = """
        EXERCISE BEING ANALYZED:
        - Name: \(exercise.name)
        - Target Area: \(exercise.targetArea)
        - Category: \(exercise.exerciseCategory ?? "unknown")
        - Difficulty: \(exercise.difficulty.rawValue)
        - Sets: \(exercise.sets), Reps: \(exercise.reps)
        """

        if let start = exercise.startPosition {
            message += "\n- Start Position: \(start)"
        }
        if let movement = exercise.movement {
            message += "\n- Movement: \(movement)"
        }
        if let end = exercise.endPosition {
            message += "\n- End Position: \(end)"
        }
        if !exercise.tips.isEmpty {
            message += "\n- Tips: \(exercise.tips.joined(separator: "; "))"
        }
        if !exercise.contraindications.isEmpty {
            message += "\n- Contraindications: \(exercise.contraindications.joined(separator: "; "))"
        }

        message += "\n\nVIDEO INFO:"
        message += "\n- Duration: \(String(format: "%.1f", metrics.videoDurationSeconds))s"
        message += "\n- FPS: \(String(format: "%.0f", metrics.videoFPS))"
        message += "\n- Frames processed: \(metrics.totalFramesProcessed)"
        if let height = metrics.bodyHeight {
            message += "\n- Estimated body height: \(String(format: "%.2f", height))m"
        }

        message += "\n\nFORM METRICS (\(metrics.detectedRepCount) reps detected):"

        if metrics.repMetrics.isEmpty {
            message += "\nNo repetitions were detected. The user may have performed a static hold, or the movement range was too small to detect."
        } else {
            for rep in metrics.repMetrics {
                message += "\nRep \(rep.repNumber) (duration: \(rep.durationSeconds)s):"
                for (angleName, range) in rep.keyAngles.sorted(by: { $0.key < $1.key }) {
                    message += "\n  \(angleName): min=\(range.minDegrees)° max=\(range.maxDegrees)° ROM=\(range.rangeOfMotion)°"
                }
            }
        }

        if let symmetry = metrics.symmetry, !symmetry.differencesDegrees.isEmpty {
            message += "\n\nSYMMETRY:"
            for (joint, diff) in symmetry.differencesDegrees.sorted(by: { $0.key < $1.key }) {
                let leftVal = symmetry.leftAvgAngles["left_\(joint)"] ?? 0
                let rightVal = symmetry.rightAvgAngles["right_\(joint)"] ?? 0
                message += "\n  \(joint): left_avg=\(leftVal)° right_avg=\(rightVal)° diff=\(diff)°"
            }
        }

        if !metrics.alignment.isEmpty {
            message += "\n\nALIGNMENT ISSUES:"
            for issue in metrics.alignment {
                message += "\n  \(issue.description) (\(issue.affectedReps)/\(issue.totalReps) reps)"
            }
        }

        if let tempo = metrics.averageTempo {
            message += "\n\nTEMPO:"
            message += "\n  Average: \(tempo)s per rep"
            if let sd = metrics.tempoVariability {
                message += "\n  Variability (SD): \(sd)s"
            }
        }

        if let dq = dataQuality {
            message += "\n\nDATA QUALITY:"
            message += "\n  Overall quality: \(String(format: "%.2f", dq.overallScore)) / 1.00"
            message += "\n  Frame coverage: \(String(format: "%.0f", dq.frameCoverage * 100))%"
            message += "\n  Avg joints per frame: \(String(format: "%.1f", dq.averageJointCount)) / 17"
            message += "\n  Link-length consistency: \(String(format: "%.2f", dq.linkLengthConsistency))"
            message += "\n  Temporal outliers: \(dq.temporalOutlierCount)"
            message += "\n  Minimum data threshold met: \(dq.minimumDataThresholdMet ? "yes" : "NO")"
            if !dq.warnings.isEmpty {
                message += "\n  Warnings: \(dq.warnings.joined(separator: "; "))"
            }
        }

        message += "\n\nAnalyze the user's exercise form based on the metrics above. Provide specific, actionable feedback. For each correction, include a dataReference citing the specific metric."

        return message
    }

    // MARK: - Response Parsing

    private func parseFormFeedback(from text: String, exerciseName: String) throws -> FormFeedback {
        guard let jsonData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(
                NSError(domain: "FormAnalysisViewModel", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid response encoding"]))
        }

        let aiResponse: AIFormFeedbackResponse
        do {
            aiResponse = try JSONDecoder().decode(AIFormFeedbackResponse.self, from: jsonData)
        } catch let directError {
            // Fallback: extract JSON between first { and last }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex {
                let jsonSubstring = String(text[startIndex...endIndex])
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    aiResponse = try JSONDecoder().decode(AIFormFeedbackResponse.self, from: fallbackData)
                } else {
                    throw ClaudeAPIError.decodingError(directError)
                }
            } else {
                throw ClaudeAPIError.decodingError(directError)
            }
        }

        let verdict: FormFeedback.Verdict = {
            switch aiResponse.verdict.lowercased() {
            case "excellent": return .excellent
            case "good": return .good
            case "concern": return .concern
            default: return .needsWork
            }
        }()

        let corrections = aiResponse.corrections.map { correction in
            let severity: FormFeedback.Correction.Severity = {
                switch correction.severity.lowercased() {
                case "minor": return .minor
                case "major": return .major
                default: return .moderate
                }
            }()

            return FormFeedback.Correction(
                bodyPart: correction.bodyPart,
                issue: correction.issue,
                howToFix: correction.howToFix,
                severity: severity,
                dataReference: correction.dataReference
            )
        }

        return FormFeedback(
            exerciseName: exerciseName,
            overallScore: max(0, min(100, aiResponse.overallScore)),
            verdict: verdict,
            corrections: corrections,
            positivePoints: aiResponse.positivePoints,
            safetyNotes: aiResponse.safetyNotes,
            dataLimitations: aiResponse.dataLimitations ?? []
        )
    }
}
