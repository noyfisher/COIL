import Foundation

// MARK: - PrimaryActivity

enum PrimaryActivity: String, Codable, CaseIterable {
    case deskWork
    case standing
    case physicalLabor
    case athleticTraining

    var displayName: String {
        switch self {
        case .deskWork: return "Desk Work"
        case .standing: return "Standing"
        case .physicalLabor: return "Physical Labor"
        case .athleticTraining: return "Athletic Training"
        }
    }

    var icon: String {
        switch self {
        case .deskWork: return "laptopcomputer"
        case .standing: return "figure.stand"
        case .physicalLabor: return "hammer.fill"
        case .athleticTraining: return "figure.run"
        }
    }

    var description: String {
        switch self {
        case .deskWork: return "Mostly seated at a computer"
        case .standing: return "On your feet most of the day"
        case .physicalLabor: return "Lifting, bending, or manual work"
        case .athleticTraining: return "Sport or structured training"
        }
    }
}

// MARK: - BodyRiskAssessment

struct BodyRiskAssessment: Codable, Identifiable {
    var id: UUID = UUID()
    var primaryActivity: PrimaryActivity
    var hoursSeatedPerDay: Double
    var dominantSportOrHobby: String?
    var assessmentDate: Date = Date()
}
