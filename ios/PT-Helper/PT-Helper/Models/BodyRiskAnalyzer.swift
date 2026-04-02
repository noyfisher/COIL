import Foundation
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PT-Helper", category: "BodyRiskAnalyzer")

// MARK: - Intermediate Decodable Types for AI Response

private struct AIBodyRiskResponse: Decodable {
    let riskRegions: [AIRiskRegion]
}

private struct AIRiskRegion: Decodable {
    let region: String
    let riskLevel: String
    let rationale: String
}

// MARK: - AI-Powered Body Risk Analyzer

class BodyRiskAnalyzer {

    struct ValidatedBodyRiskAnalysis {
        let result: BodyRiskResult
    }

    /// Analyze body risk using a two-call AI pipeline.
    ///
    /// Call 1 (Primary): Identifies 2–3 at-risk body regions based on lifestyle and history.
    /// Call 2 (Verification): Devil's advocate review to refine and validate risk regions.
    /// If Call 2 fails, gracefully falls back to Call 1's result.
    static func analyze(
        assessment: BodyRiskAssessment,
        profile: UserProfile,
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared
    ) async throws -> ValidatedBodyRiskAnalysis {

        // --- Call 1: Primary Analysis ---
        logger.info("Building body risk assessment prompt")
        let userMessage = buildUserMessage(assessment: assessment, profile: profile)
        logger.debug("Prompt length: \(userMessage.count) characters")

        logger.info("Sending primary body risk request to Claude API...")
        let primaryResponseText = try await apiService.sendMessage(
            requestType: .body_risk_assessment,
            userMessage: userMessage
        )
        logger.info("Primary response: \(primaryResponseText.count) characters")

        let primaryResult = try parseBodyRiskResponse(primaryResponseText, assessment: assessment)
        logger.info("Primary analysis: \(primaryResult.riskRegions.count) risk regions")

        // --- Call 2: Verification (graceful degradation on failure) ---
        let synthesizedResult: BodyRiskResult
        do {
            let verificationMessage = buildVerificationMessage(
                originalUserMessage: userMessage,
                primaryResponseJSON: primaryResponseText
            )

            logger.info("Sending body risk verification request to Claude API...")
            let verifyResponseText = try await apiService.sendMessage(
                requestType: .body_risk_assessment_verify,
                userMessage: verificationMessage
            )
            logger.info("Verification response: \(verifyResponseText.count) characters")

            let verifyResult = try parseBodyRiskResponse(verifyResponseText, assessment: assessment)
            logger.info("Verification: \(verifyResult.riskRegions.count) risk regions")

            synthesizedResult = verifyResult
            logger.info("Using verified body risk regions")
        } catch {
            logger.warning("Body risk verification failed: \(error.localizedDescription). Falling back to primary.")
            Task { @MainActor in
                SessionLogger.shared.log(.stateUpdated, category: .api, message: "Body risk verification fallback to primary",
                                          metadata: ["error": error.localizedDescription])
            }
            synthesizedResult = primaryResult
        }

        return ValidatedBodyRiskAnalysis(result: synthesizedResult)
    }

    // MARK: - User Message Construction

    static func buildUserMessage(assessment: BodyRiskAssessment, profile: UserProfile) -> String {
        var message = """
        PATIENT PROFILE:
        - Age: \(profile.age) years old
        - Sex: \(profile.sex)
        - Activity Level: \(profile.activityLevel)
        - Primary Daily Activity: \(assessment.primaryActivity.displayName) — \(assessment.primaryActivity.description)
        - Hours Seated Per Day: \(Int(assessment.hoursSeatedPerDay)) hours
        """

        if let sport = assessment.dominantSportOrHobby, !sport.isEmpty {
            message += "\n- Dominant Sport or Hobby: \(InputSanitizer.sanitize(sport))"
        } else if let sport = profile.primarySport, !sport.isEmpty {
            message += "\n- Primary Sport/Activity: \(sport)"
        }

        if !profile.medicalConditions.isEmpty {
            message += "\n- Medical Conditions: \(profile.medicalConditions.joined(separator: ", "))"
        }

        if let side = profile.dominantSide {
            message += "\n- Dominant Side: \(side)"
        }

        if let meds = profile.medications, !meds.isEmpty {
            message += "\n- Current Medications: \(meds.joined(separator: ", "))"
        }

        // Include relevant surgical and injury history
        let classifiedSurgeries = HistoryRelevanceFilter.classify(surgeries: profile.surgeries, assessedRegions: [])
        let relevantSurgeries = classifiedSurgeries.filter { $0.relevance >= .possiblyRelevant }

        if !relevantSurgeries.isEmpty {
            message += "\n\nSURGICAL HISTORY:"
            for cs in relevantSurgeries {
                let s = cs.surgery
                var line = "\n- \(InputSanitizer.sanitize(s.name)) (\(s.year))"
                if let area = s.bodyArea, !area.isEmpty { line += ", \(area)" }
                if let status = s.recoveryStatus { line += " — \(status)" }
                if let restrictions = s.restrictions, !restrictions.isEmpty {
                    line += " [Restrictions: \(InputSanitizer.sanitize(restrictions))]"
                }
                message += line
            }
        }

        let classifiedInjuries = HistoryRelevanceFilter.classify(injuries: profile.injuries, assessedRegions: [])
        let relevantInjuries = classifiedInjuries.filter { $0.relevance >= .possiblyRelevant }

        if !relevantInjuries.isEmpty {
            message += "\n\nINJURY HISTORY:"
            for ci in relevantInjuries {
                let i = ci.injury
                let status = i.isCurrent ? "current" : "past"
                var line = "\n- \(InputSanitizer.sanitize(i.bodyArea)): \(InputSanitizer.sanitize(i.description)) (\(status))"
                if let year = i.year { line += ", \(year)" }
                if let recovery = i.recoveryStatus { line += " — \(recovery)" }
                message += line
            }
        }

        message += "\n\nPlease identify 2–3 body regions at elevated risk for this patient based on their lifestyle, daily activity, and history. Focus on prevention — what areas are most vulnerable to developing problems if not addressed proactively?"

        return message
    }

    // MARK: - Verification Message Construction

    static func buildVerificationMessage(originalUserMessage: String, primaryResponseJSON: String) -> String {
        return """
        ORIGINAL PATIENT DATA:
        \(originalUserMessage)

        PRIMARY BODY RISK ASSESSMENT (from initial review):
        \(primaryResponseJSON)

        Please review the above risk assessment. Check that: (1) the identified regions are genuinely at risk given the patient's specific lifestyle and history, not just generic recommendations; (2) risk levels are appropriately calibrated — not overstated or understated; (3) rationale is specific and actionable. Return your refined assessment.
        """
    }

    // MARK: - Response Parsing

    static func parseBodyRiskResponse(_ text: String, assessment: BodyRiskAssessment) throws -> BodyRiskResult {
        guard let jsonData = text.data(using: .utf8) else {
            logger.error("Response text could not be converted to UTF-8 data")
            throw ClaudeAPIError.decodingError(NSError(domain: "BodyRiskAnalyzer", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid response text encoding"]))
        }

        let aiResponse: AIBodyRiskResponse
        do {
            aiResponse = try JSONDecoder().decode(AIBodyRiskResponse.self, from: jsonData)
            logger.info("Direct JSON decode succeeded")
        } catch let directError {
            logger.warning("Direct JSON decode failed: \(directError.localizedDescription). Attempting fallback extraction...")
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex {
                let jsonSubstring = String(text[startIndex...endIndex])
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    do {
                        aiResponse = try JSONDecoder().decode(AIBodyRiskResponse.self, from: fallbackData)
                        logger.info("Fallback JSON decode succeeded")
                    } catch let fallbackError {
                        logger.error("Fallback JSON decode also failed: \(fallbackError.localizedDescription)")
                        throw ClaudeAPIError.decodingError(fallbackError)
                    }
                } else {
                    throw ClaudeAPIError.decodingError(directError)
                }
            } else {
                logger.error("No JSON object found in response")
                throw ClaudeAPIError.decodingError(directError)
            }
        }

        let riskRegions = aiResponse.riskRegions.prefix(3).map { aiRegion in
            RiskRegion(
                id: UUID(),
                regionName: aiRegion.region,
                riskLevel: RiskLevel(rawValue: aiRegion.riskLevel.lowercased()) ?? .moderate,
                rationale: aiRegion.rationale
            )
        }

        return BodyRiskResult(
            id: UUID(),
            riskRegions: Array(riskRegions),
            generatedDate: Date(),
            assessmentSnapshot: assessment
        )
    }
}
