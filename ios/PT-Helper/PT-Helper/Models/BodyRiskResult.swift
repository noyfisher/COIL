import Foundation

// MARK: - RiskLevel

enum RiskLevel: String, Codable, CaseIterable {
    case low
    case moderate
    case elevated

    var displayName: String {
        switch self {
        case .low: return "Low Risk"
        case .moderate: return "Moderate Risk"
        case .elevated: return "Elevated Risk"
        }
    }

    var shortName: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .elevated: return "Elevated"
        }
    }
}

// MARK: - RiskRegion

struct RiskRegion: Codable, Identifiable {
    var id: UUID = UUID()
    var regionName: String
    var riskLevel: RiskLevel
    var rationale: String
}

// MARK: - BodyRiskResult

struct BodyRiskResult: Codable, Identifiable {
    var id: UUID = UUID()
    var riskRegions: [RiskRegion]
    var generatedDate: Date
    var assessmentSnapshot: BodyRiskAssessment
}
