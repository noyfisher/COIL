import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PT-Helper", category: "WellnessAnalyzer")

// MARK: - Intermediate Decodable Types for AI Response

private struct AIWellnessResponse: Decodable {
    let recommendations: [AIWellnessRecommendation]
    let overallSummary: String
    let disclaimerText: String
}

private struct AIWellnessRecommendation: Decodable {
    let goalCategory: String
    let title: String
    let currentStateAssessment: String
    let rootCauses: [String]
    let expectedTimeline: String
    let keyInsight: String
    let priorityLevel: String
    let relatedGoals: [String]
}

// MARK: - AI-Powered Wellness Analyzer

class WellnessAnalyzer {

    /// Result of a validated wellness analysis.
    struct ValidatedWellnessAnalysis {
        let result: WellnessAnalysisResult
    }

    /// Analyze wellness assessments using a two-call AI pipeline.
    ///
    /// Call 1 (Primary Analysis): Personalized wellness recommendations.
    /// Call 2 (Verification): Feasibility, personalization, and safety review.
    /// If Call 2 fails, gracefully falls back to Call 1's result.
    static func analyze(assessments: [WellnessAssessment], profile: UserProfile, apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) async throws -> ValidatedWellnessAnalysis {

        // --- Call 1: Primary Analysis ---
        logger.info("Building primary wellness analysis prompt for \(assessments.count) goal(s)")
        let userMessage = buildUserMessage(assessments: assessments, profile: profile)
        logger.debug("Prompt length: \(userMessage.count) characters")

        logger.info("Sending primary wellness analysis request to Claude API...")
        let primaryResponseText = try await apiService.sendMessage(
            requestType: .wellness_analysis,
            userMessage: userMessage
        )
        logger.info("Primary response: \(primaryResponseText.count) characters")

        logger.info("Parsing primary wellness response...")
        let primaryResult = try parseWellnessResponse(primaryResponseText, assessments: assessments, profile: profile)
        logger.info("Primary analysis: \(primaryResult.recommendations.count) recommendations")

        // --- Call 2: Verification (graceful degradation on failure) ---
        let synthesizedResult: WellnessAnalysisResult
        do {
            let verificationMessage = buildVerificationMessage(
                originalUserMessage: userMessage,
                primaryResponseJSON: primaryResponseText
            )
            logger.debug("Verification message length: \(verificationMessage.count) characters")

            logger.info("Sending wellness verification request to Claude API...")
            let verifyResponseText = try await apiService.sendMessage(
                requestType: .wellness_verify,
                userMessage: verificationMessage
            )
            logger.info("Verification response: \(verifyResponseText.count) characters")

            logger.info("Parsing wellness verification response...")
            let verifyResult = try parseWellnessResponse(verifyResponseText, assessments: assessments, profile: profile)
            logger.info("Verification: \(verifyResult.recommendations.count) recommendations")

            // Use verification result as it had the most context
            synthesizedResult = verifyResult
            logger.info("Using verified wellness recommendations")
        } catch {
            // Graceful degradation: if verification fails, use primary result
            logger.warning("Wellness verification failed: \(error.localizedDescription). Falling back to primary analysis.")
            Task { @MainActor in
                SessionLogger.shared.log(.stateUpdated, category: .api, message: "Wellness verification fallback to primary",
                                          metadata: ["error": error.localizedDescription])
            }
            synthesizedResult = primaryResult
        }

        return ValidatedWellnessAnalysis(result: synthesizedResult)
    }

    // MARK: - User Message Construction

    static func buildUserMessage(assessments: [WellnessAssessment], profile: UserProfile) -> String {
        var message = """
        PATIENT PROFILE:
        - Age: \(profile.age) years old
        - Sex: \(profile.sex)
        - Height: \(profile.heightFeet)'\(profile.heightInches)"
        - Weight: \(Int(profile.weight)) lbs
        - Activity Level: \(profile.activityLevel)
        """

        if let sport = profile.primarySport, !sport.isEmpty {
            message += "\n- Primary Sport/Activity: \(sport)"
        }

        if !profile.medicalConditions.isEmpty {
            message += "\n- Medical Conditions: \(profile.medicalConditions.joined(separator: ", "))"
        }

        if let other = profile.otherMedicalConditions, !other.isEmpty {
            message += "\n- Other Medical Conditions: \(InputSanitizer.sanitize(other))"
        }

        if let side = profile.dominantSide {
            message += "\n- Dominant Side: \(side)"
        }

        if let meds = profile.medications, !meds.isEmpty {
            message += "\n- Current Medications: \(meds.joined(separator: ", "))"
        }

        // Medication change history
        if let history = profile.medicationHistory, !history.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let recentChanges = history.suffix(10)
            message += "\n\nMEDICATION HISTORY:"
            for change in recentChanges {
                message += "\n- \(change.action.capitalized) \(change.medication) on \(dateFormatter.string(from: change.date))"
            }
        }

        // Include ALL surgical history (no region filtering for wellness)
        if !profile.surgeries.isEmpty {
            message += "\n\nSURGICAL HISTORY:"
            for s in profile.surgeries {
                var line = "\n- \(InputSanitizer.sanitize(s.name)) (\(s.year))"
                if let area = s.bodyArea, !area.isEmpty { line += ", \(area)" }
                if let surgeryType = s.surgeryType, !surgeryType.isEmpty { line += " [Type: \(InputSanitizer.sanitize(surgeryType))]" }
                if let status = s.recoveryStatus { line += " — \(status)" }
                if let restrictions = s.restrictions, !restrictions.isEmpty { line += " [Restrictions: \(InputSanitizer.sanitize(restrictions))]" }
                if let hasHardware = s.hasHardware {
                    if hasHardware {
                        let details = s.hardwareDetails.flatMap { !$0.isEmpty && $0 != "__not_sure__" ? InputSanitizer.sanitize($0) : nil } ?? "details unknown"
                        line += " [Hardware present: \(details)]"
                    }
                }
                message += line
            }
        }

        // Include ALL injury history
        if !profile.injuries.isEmpty {
            message += "\n\nINJURY HISTORY:"
            for i in profile.injuries {
                let status = i.isCurrent ? "current" : "past"
                var line = "\n- \(InputSanitizer.sanitize(i.bodyArea)): \(InputSanitizer.sanitize(i.description)) (\(status))"
                if let year = i.year { line += ", \(year)" }
                if let recovery = i.recoveryStatus { line += " — \(recovery)" }
                message += line
            }
        }

        message += "\n\nWELLNESS GOALS:\n"

        for (index, assessment) in assessments.enumerated() {
            message += "\n--- Goal \(index + 1): \(assessment.goalCategory.displayName) ---"

            if let customText = assessment.customGoalText, !customText.isEmpty {
                message += "\n- Custom Description: \(InputSanitizer.sanitize(customText))"
            }

            message += """

            - Impact on Daily Life: \(assessment.impactLevel.displayName)
            - Motivation Level: \(assessment.motivationLevel)/10
            - How Long This Has Been an Issue: \(assessment.duration.displayName)
            - Worst Times of Day: \(assessment.timeOfDay.map { $0.displayName }.joined(separator: ", "))
            """

            if !assessment.dailyActivitiesAffected.isEmpty {
                message += "\n- Daily Activities Affected: \(assessment.dailyActivitiesAffected.joined(separator: ", "))"
            }

            if !assessment.currentHabits.isEmpty {
                message += "\n- Current Habits: \(assessment.currentHabits.joined(separator: ", "))"
            }

            if !assessment.priorAttempts.isEmpty {
                message += "\n- Prior Attempts: \(assessment.priorAttempts.map { $0.displayName }.joined(separator: ", "))"
            }

            message += "\n- Daily Time Commitment: \(assessment.commitmentLevel.displayName)"

            if let context = assessment.specificContext, !context.isEmpty {
                message += "\n- Additional Context: \(InputSanitizer.sanitize(context))"
            }

            if let notes = assessment.additionalNotes, !notes.isEmpty {
                message += "\n- Additional Notes: \(InputSanitizer.sanitize(notes))"
            }
        }

        message += "\n\nPlease analyze these wellness goals and provide personalized recommendations."

        return message
    }

    // MARK: - Verification Message Construction

    static func buildVerificationMessage(originalUserMessage: String, primaryResponseJSON: String) -> String {
        return """
        ORIGINAL PATIENT DATA:
        \(originalUserMessage)

        PRIMARY WELLNESS ANALYSIS (from initial review):
        \(primaryResponseJSON)

        Please review the above wellness analysis against the patient data. Check feasibility (realistic given their time and activity level), personalization (truly specific to this person, not generic), and safety (safe given their medical history, surgeries, and medications). Return your refined recommendations.
        """
    }

    // MARK: - Response Parsing

    static func parseWellnessResponse(_ text: String, assessments: [WellnessAssessment], profile: UserProfile) throws -> WellnessAnalysisResult {
        guard let jsonData = text.data(using: .utf8) else {
            logger.error("Response text could not be converted to UTF-8 data")
            throw ClaudeAPIError.decodingError(NSError(domain: "WellnessAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response text encoding"]))
        }

        let aiResponse: AIWellnessResponse
        do {
            aiResponse = try JSONDecoder().decode(AIWellnessResponse.self, from: jsonData)
            logger.info("Direct JSON decode succeeded")
        } catch let directError {
            logger.warning("Direct JSON decode failed: \(directError.localizedDescription). Attempting fallback extraction...")
            // Try to extract JSON between first { and last }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex {
                let jsonSubstring = String(text[startIndex...endIndex])
                logger.info("Extracted JSON substring: \(jsonSubstring.count) chars")
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    do {
                        aiResponse = try JSONDecoder().decode(AIWellnessResponse.self, from: fallbackData)
                        logger.info("Fallback JSON decode succeeded")
                        Task { @MainActor in
                            SessionLogger.shared.log(.stateUpdated, category: .api, message: "Wellness analysis used fallback JSON extraction",
                                                      metadata: ["trimmedChars": "\(text.count - jsonSubstring.count)"])
                        }
                    } catch let fallbackError {
                        logger.error("Fallback JSON decode also failed: \(fallbackError.localizedDescription)")
                        let preview = String(jsonSubstring.prefix(200))
                        logger.error("Response preview: \(preview)")
                        throw ClaudeAPIError.decodingError(fallbackError)
                    }
                } else {
                    logger.error("Fallback JSON substring could not be converted to UTF-8")
                    throw ClaudeAPIError.decodingError(directError)
                }
            } else {
                logger.error("No JSON object found in response")
                let preview = String(text.prefix(200))
                logger.error("Response preview: \(preview)")
                throw ClaudeAPIError.decodingError(directError)
            }
        }

        // Map AI response to our model types
        let recommendations = aiResponse.recommendations.map { aiRec in
            WellnessRecommendation(
                id: UUID(),
                goalCategory: aiRec.goalCategory,
                title: aiRec.title,
                currentStateAssessment: aiRec.currentStateAssessment,
                rootCauses: aiRec.rootCauses,
                expectedTimeline: aiRec.expectedTimeline,
                keyInsight: aiRec.keyInsight,
                priorityLevel: aiRec.priorityLevel,
                relatedGoals: aiRec.relatedGoals
            )
        }

        return WellnessAnalysisResult(
            id: UUID(),
            assessments: assessments,
            recommendations: recommendations,
            overallSummary: aiResponse.overallSummary,
            disclaimerText: aiResponse.disclaimerText,
            generatedDate: Date(),
            userProfileSnapshot: profile
        )
    }
}
