import XCTest
@testable import COIL

// MARK: - Performance Tests

final class PerformanceTests: XCTestCase {

    // MARK: - Validation Pipeline Performance

    func testValidateAnalysis_performance() {
        let conditions = (0..<5).map { i in
            TestFixtures.makeCondition(
                name: "Condition \(i)",
                confidence: Double.random(in: 30...90)
            )
        }
        let assessments = [TestFixtures.makeAssessment()]
        let result = TestFixtures.makeAnalysisResult(conditions: conditions, assessments: assessments)

        measure {
            _ = ResponseValidationPipeline.validateAnalysis(result, assessments: assessments)
        }
    }

    func testValidateRehabPlan_performance() {
        let exercises = (0..<10).map { i in
            TestFixtures.makeExercise(name: "Exercise \(i)", targetArea: "Knee")
        }
        let plan = TestFixtures.makePlan(exercises: exercises)
        let profile = TestFixtures.makeProfile()

        measure {
            _ = ResponseValidationPipeline.validateRehabPlan(
                plan,
                conditions: ["Test Condition"],
                userProfile: profile
            )
        }
    }

    // MARK: - History Relevance Filter Performance

    func testHistoryRelevanceFilter_classify_performance() {
        // Simulate a patient with substantial history
        let surgeries = (0..<10).map { i in
            UserProfile.Surgery(
                name: "Surgery \(i)", year: 2020 + (i % 6),
                bodyArea: ["Left Knee", "Right Shoulder", "Lower Back", "Left Hip", "Right Ankle", "Neck"][i % 6],
                recoveryStatus: ["Fully recovered", "Still recovering", "Have restrictions"][i % 3]
            )
        }
        let regions = [
            TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee"),
            TestFixtures.makeRegion(name: "Lower Back", zoneKey: "lower_back"),
            TestFixtures.makeRegion(name: "Left Shoulder", zoneKey: "left_shoulder")
        ]

        measure {
            _ = HistoryRelevanceFilter.classify(surgeries: surgeries, assessedRegions: regions)
        }
    }

    func testHistoryRelevanceFilter_injuries_performance() {
        let injuries = (0..<10).map { i in
            UserProfile.Injury(
                bodyArea: ["Left Knee", "Right Shoulder", "Lower Back", "Left Hip", "Right Ankle"][i % 5],
                description: "Injury \(i)",
                isCurrent: i < 2,
                year: 2018 + i,
                recoveryStatus: ["Fully recovered", "Still dealing with it", "Mostly recovered"][i % 3]
            )
        }
        let regions = [
            TestFixtures.makeRegion(name: "Right Knee", zoneKey: "right_knee"),
            TestFixtures.makeRegion(name: "Lower Back", zoneKey: "lower_back")
        ]

        measure {
            _ = HistoryRelevanceFilter.classify(injuries: injuries, assessedRegions: regions)
        }
    }

    // MARK: - Input Sanitizer Performance

    func testInputSanitizer_performance() {
        let longInput = String(repeating: "This is some test input with various content. ", count: 20)

        measure {
            for _ in 0..<100 {
                _ = InputSanitizer.sanitize(longInput)
            }
        }
    }

    // MARK: - ClaudeAPIService cleanJSON Performance

    func testCleanJSONResponse_performance() {
        let json = """
        ```json
        {"conditions": [{"conditionName": "Test", "commonName": "Test", "confidence": 75, "explanation": "Test explanation that is somewhat long to simulate real response data from the AI model", "whatItMeans": "Test meaning", "howToManage": "Test management", "isRedFlag": false, "redFlagMessage": null, "nextSteps": ["Step 1", "Step 2", "Step 3"]}], "overallSummary": "A comprehensive summary of the analysis results", "disclaimerText": "This is not medical advice."}
        ```
        """

        measure {
            for _ in 0..<1000 {
                _ = ClaudeAPIService.cleanJSONResponse(json)
            }
        }
    }
}
