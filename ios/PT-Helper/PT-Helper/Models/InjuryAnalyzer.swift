import Foundation

// MARK: - Intermediate Decodable Types for AI Response

private struct AIAnalysisResponse: Decodable {
    let conditions: [AIConditionResult]
    let overallSummary: String
    let disclaimerText: String
}

private struct AIConditionResult: Decodable {
    let conditionName: String
    let commonName: String
    let confidence: Double
    let explanation: String
    let whatItMeans: String
    let howToManage: String
    let isRedFlag: Bool
    let redFlagMessage: String?
    let nextSteps: [String]
}

// MARK: - AI-Powered Injury Analyzer

class InjuryAnalyzer {

    /// Result of a validated analysis including any safety warnings.
    struct ValidatedAnalysis {
        let result: AnalysisResult
        let validation: ValidationResult
        let redFlagAlerts: [ValidationWarning]
    }

    /// Analyze pain assessments using the Claude AI API, then validate the response.
    static func analyze(assessments: [PainAssessment], profile: UserProfile) async throws -> ValidatedAnalysis {
        let systemPrompt = buildSystemPrompt()
        let userMessage = buildUserMessage(assessments: assessments, profile: profile)

        let responseText = try await ClaudeAPIService.shared.sendMessage(
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        let rawResult = try parseAnalysisResponse(responseText, assessments: assessments, profile: profile)

        // Run validation pipeline
        let (validatedResult, validation, redFlags) = ResponseValidationPipeline.validateAnalysis(
            rawResult,
            assessments: assessments
        )

        return ValidatedAnalysis(
            result: validatedResult,
            validation: validation,
            redFlagAlerts: redFlags
        )
    }

    // MARK: - System Prompt

    private static func buildSystemPrompt() -> String {
        """
        You are a friendly health guide helping everyday people understand their pain. Write like you're explaining to a friend — no medical jargon. This is educational only, not a diagnosis.

        YOUR AUDIENCE: Regular people who may not be able to see a doctor right away. They need to understand what might be going on with their body in plain, simple language.

        RULES:
        - Return top 3 possible conditions with confidence 0-100
        - "conditionName": the medical/clinical name (e.g. "Patellofemoral Pain Syndrome")
        - "commonName": a plain English name anyone would understand (e.g. "Runner's Knee" or "Kneecap Pain")
        - "explanation": 1-2 SHORT sentences about what this condition is and why it matches. Keep it brief — no walls of text
        - "whatItMeans": 1-2 SHORT sentences about what's happening in their body. Plain terms, no jargon (e.g. "The cushion under your kneecap is getting irritated from not tracking properly")
        - "howToManage": Keep this very brief — 1 sentence max. Save detailed advice for the rehab plan
        - "nextSteps": 2-3 short, concrete steps (e.g. "Ice the area for 15 minutes twice a day")
        - "overallSummary": 1-2 sentences summarizing the situation directly to the person. Be reassuring but concise
        - Flag red flags: cauda equina, fractures, infections, spinal cord issues, night pain without relief, sudden weakness, chest pain. Write the redFlagMessage in urgent but clear language

        Respond ONLY with valid JSON (no markdown fences):
        {"conditions":[{"conditionName":"string","commonName":"string","confidence":number,"explanation":"string","whatItMeans":"string","howToManage":"string","isRedFlag":boolean,"redFlagMessage":"string or null","nextSteps":["strings"]}],"overallSummary":"string","disclaimerText":"This is not a medical diagnosis — it's a starting point to help you understand what might be going on. If your pain is severe, getting worse, or not improving, please see a doctor or visit an urgent care clinic."}
        """
    }

    // MARK: - User Message Construction

    private static func buildUserMessage(assessments: [PainAssessment], profile: UserProfile) -> String {
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
            message += "\n- Other Medical Conditions: \(other)"
        }

        if !profile.surgeries.isEmpty {
            let surgeryList = profile.surgeries.map { "\($0.name) (\($0.year))" }.joined(separator: ", ")
            message += "\n- Past Surgeries: \(surgeryList)"
        }

        if !profile.injuries.isEmpty {
            let injuryList = profile.injuries.map { injury in
                let status = injury.isCurrent ? "current" : "past"
                return "\(injury.bodyArea): \(injury.description) (\(status))"
            }.joined(separator: "; ")
            message += "\n- Injuries: \(injuryList)"
        }

        message += "\n\nPAIN ASSESSMENTS:\n"

        for (index, assessment) in assessments.enumerated() {
            message += """

            --- Region \(index + 1): \(assessment.selectedRegion.name) ---
            - Pain Type: \(assessment.painType.displayName)
            """

            if let customDesc = assessment.customPainDescription, !customDesc.isEmpty {
                message += "\n- Patient's Description: \(customDesc)"
            }

            message += """

            - Pain Intensity: \(assessment.painIntensity)/10
            - Duration: \(assessment.painDuration.displayName)
            - Frequency: \(assessment.painFrequency.displayName)
            - Onset: \(assessment.painOnset.displayName)
            """

            if !assessment.aggravatingFactors.isEmpty {
                message += "\n- Aggravating Factors: \(assessment.aggravatingFactors.joined(separator: ", "))"
            }

            if !assessment.relievingFactors.isEmpty {
                message += "\n- Relieving Factors: \(assessment.relievingFactors.joined(separator: ", "))"
            }

            if let notes = assessment.additionalNotes, !notes.isEmpty {
                message += "\n- Additional Notes: \(notes)"
            }
        }

        message += "\n\nPlease analyze these symptoms and provide your assessment."

        return message
    }

    // MARK: - Response Parsing

    private static func parseAnalysisResponse(_ text: String, assessments: [PainAssessment], profile: UserProfile) throws -> AnalysisResult {
        guard let jsonData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(NSError(domain: "InjuryAnalyzer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response text encoding"]))
        }

        let aiResponse: AIAnalysisResponse
        do {
            aiResponse = try JSONDecoder().decode(AIAnalysisResponse.self, from: jsonData)
        } catch {
            // Try to extract JSON between first { and last }
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}") {
                let jsonSubstring = String(text[startIndex...endIndex])
                if let fallbackData = jsonSubstring.data(using: .utf8) {
                    do {
                        aiResponse = try JSONDecoder().decode(AIAnalysisResponse.self, from: fallbackData)
                    } catch {
                        throw ClaudeAPIError.decodingError(error)
                    }
                } else {
                    throw ClaudeAPIError.decodingError(error)
                }
            } else {
                throw ClaudeAPIError.decodingError(error)
            }
        }

        // Map AI response to our model types
        let conditions = aiResponse.conditions.map { aiCondition in
            ConditionResult(
                id: UUID(),
                conditionName: aiCondition.conditionName,
                commonName: aiCondition.commonName,
                confidence: aiCondition.confidence,
                explanation: aiCondition.explanation,
                whatItMeans: aiCondition.whatItMeans,
                howToManage: aiCondition.howToManage,
                isRedFlag: aiCondition.isRedFlag,
                redFlagMessage: aiCondition.redFlagMessage,
                nextSteps: aiCondition.nextSteps
            )
        }

        return AnalysisResult(
            id: UUID(),
            assessments: assessments,
            conditions: conditions,
            overallSummary: aiResponse.overallSummary,
            disclaimerText: aiResponse.disclaimerText,
            generatedDate: Date(),
            userProfileSnapshot: profile
        )
    }
}
