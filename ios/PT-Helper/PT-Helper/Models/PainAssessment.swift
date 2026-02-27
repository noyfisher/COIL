import Foundation

struct PainAssessment: Codable, Identifiable {
    enum PainType: String, Codable, CaseIterable {
        case sharp, dull, burning, throbbing, aching, stabbing, tingling, tightness
        var displayName: String {
            switch self {
            case .sharp: return "Sharp"
            case .dull: return "Dull"
            case .burning: return "Burning"
            case .throbbing: return "Throbbing"
            case .aching: return "Aching"
            case .stabbing: return "Stabbing"
            case .tingling: return "Tingling"
            case .tightness: return "Tightness"
            }
        }
    }
    enum PainDuration: String, Codable, CaseIterable {
        case today, fewDays, oneToTwoWeeks, twoToFourWeeks, overAMonth, overThreeMonths
        var displayName: String {
            switch self {
            case .today: return "Today"
            case .fewDays: return "A Few Days"
            case .oneToTwoWeeks: return "1-2 Weeks"
            case .twoToFourWeeks: return "2-4 Weeks"
            case .overAMonth: return "Over a Month"
            case .overThreeMonths: return "Over 3 Months"
            }
        }
    }
    enum PainFrequency: String, Codable, CaseIterable {
        case constant, intermittent, onlyWithActivity, onlyAtRest, atNight
        var displayName: String {
            switch self {
            case .constant: return "Constant"
            case .intermittent: return "Intermittent"
            case .onlyWithActivity: return "Only with Activity"
            case .onlyAtRest: return "Only at Rest"
            case .atNight: return "At Night"
            }
        }
    }
    enum PainOnset: String, Codable, CaseIterable {
        case sudden, gradual, afterInjury, afterSurgery, unknown
        var displayName: String {
            switch self {
            case .sudden: return "Sudden"
            case .gradual: return "Gradual"
            case .afterInjury: return "After Injury"
            case .afterSurgery: return "After Surgery"
            case .unknown: return "Unknown"
            }
        }
    }

    let id: UUID
    let selectedRegion: BodyRegion
    let painType: PainType
    let customPainDescription: String?
    let painIntensity: Int
    let painDuration: PainDuration
    let painFrequency: PainFrequency
    let painOnset: PainOnset
    let aggravatingFactors: [String]
    let relievingFactors: [String]
    let additionalNotes: String?
}

struct ConditionResult: Codable, Identifiable {
    let id: UUID
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

struct AnalysisResult: Codable, Identifiable {
    let id: UUID
    let assessments: [PainAssessment]
    let conditions: [ConditionResult]
    let overallSummary: String
    let disclaimerText: String
    let generatedDate: Date
    let userProfileSnapshot: UserProfile
}
