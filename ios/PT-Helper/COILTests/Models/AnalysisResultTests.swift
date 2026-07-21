import XCTest
@testable import COIL

// MARK: - AnalysisResult Tests

final class AnalysisResultTests: XCTestCase {

    private func makeProfile() -> UserProfile {
        UserProfile(
            userId: "test",
            firstName: "Test", lastName: "User",
            dateOfBirth: Date(), sex: "Male",
            heightFeet: 5, heightInches: 10, weight: 175,
            medicalConditions: [], otherMedicalConditions: nil,
            surgeries: [], injuries: [],
            activityLevel: "Active", primarySport: nil
        )
    }

    private func makeAssessment() -> PainAssessment {
        let region = BodyRegion(
            name: "Right Knee", zoneKey: "right_knee",
            sides: [.front],
            frontPosition: CGPoint(x: 0.5, y: 0.5),
            backPosition: nil
        )
        return PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painTypes: ["Sharp"],
            customPainDescription: nil,
            painIntensity: 7,
            painDurations: ["2-4 Weeks"],
            painFrequencies: ["Only with Activity"],
            painOnsets: ["Gradual"],
            aggravatingFactors: ["Running"],
            relievingFactors: ["Rest"],
            additionalNotes: nil,
            currentTreatment: nil
        )
    }

    func testAnalysisResultCreation() {
        let profile = makeProfile()
        let assessment = makeAssessment()
        let condition = ConditionResult(
            id: UUID(),
            conditionName: "Patellofemoral Pain Syndrome",
            commonName: "Runner's Knee",
            confidence: 85,
            explanation: "Test explanation",
            whatItMeans: "The cartilage under your kneecap is irritated",
            howToManage: "Avoid stairs when possible and ice after activity",
            isRedFlag: false,
            redFlagMessage: nil,
            nextSteps: ["Rest", "PT"]
        )

        let result = AnalysisResult(
            id: UUID(),
            assessments: [assessment],
            conditions: [condition],
            overallSummary: "Test summary",
            disclaimerText: "Test disclaimer",
            generatedDate: Date(),
            userProfileSnapshot: profile
        )

        XCTAssertEqual(result.assessments.count, 1)
        XCTAssertEqual(result.conditions.count, 1)
        XCTAssertEqual(result.conditions.first?.conditionName, "Patellofemoral Pain Syndrome")
        XCTAssertEqual(result.conditions.first?.commonName, "Runner's Knee")
        XCTAssertEqual(result.overallSummary, "Test summary")
        XCTAssertEqual(result.disclaimerText, "Test disclaimer")
        XCTAssertEqual(result.userProfileSnapshot.firstName, "Test")
    }

    func testAnalysisResultWithMultipleConditions() {
        let profile = makeProfile()
        let conditions = [
            ConditionResult(id: UUID(), conditionName: "Condition A", commonName: "Common A", confidence: 90, explanation: "A", whatItMeans: "Body info A", howToManage: "Manage A", isRedFlag: false, redFlagMessage: nil, nextSteps: ["Step 1"]),
            ConditionResult(id: UUID(), conditionName: "Condition B", commonName: "Common B", confidence: 70, explanation: "B", whatItMeans: "Body info B", howToManage: "Manage B", isRedFlag: false, redFlagMessage: nil, nextSteps: ["Step 2"]),
            ConditionResult(id: UUID(), conditionName: "Condition C", commonName: "Common C", confidence: 40, explanation: "C", whatItMeans: "Body info C", howToManage: "Manage C", isRedFlag: true, redFlagMessage: "Urgent", nextSteps: ["Step 3"])
        ]

        let result = AnalysisResult(
            id: UUID(),
            assessments: [makeAssessment()],
            conditions: conditions,
            overallSummary: "Multiple conditions found",
            disclaimerText: "Disclaimer",
            generatedDate: Date(),
            userProfileSnapshot: profile
        )

        XCTAssertEqual(result.conditions.count, 3)
        let redFlags = result.conditions.filter { $0.isRedFlag }
        XCTAssertEqual(redFlags.count, 1)
        XCTAssertEqual(redFlags.first?.conditionName, "Condition C")
    }

    func testAnalysisResultPreservesProfileSnapshot() {
        var profile = makeProfile()
        profile.medicalConditions = ["Diabetes", "Asthma"]
        profile.surgeries = [UserProfile.Surgery(name: "Knee Surgery", year: 2020)]

        let result = AnalysisResult(
            id: UUID(),
            assessments: [makeAssessment()],
            conditions: [],
            overallSummary: "Summary",
            disclaimerText: "Disclaimer",
            generatedDate: Date(),
            userProfileSnapshot: profile
        )

        XCTAssertEqual(result.userProfileSnapshot.medicalConditions.count, 2)
        XCTAssertEqual(result.userProfileSnapshot.surgeries.count, 1)
        XCTAssertEqual(result.userProfileSnapshot.surgeries.first?.name, "Knee Surgery")
    }
}
