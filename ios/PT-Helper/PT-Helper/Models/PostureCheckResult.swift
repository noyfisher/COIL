import Foundation

/// Context in which the posture check was performed.
enum PostureContext: String, Codable, CaseIterable, Identifiable {
    case atDesk = "At Desk"
    case standing = "Standing"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .atDesk: return "desktopcomputer"
        case .standing: return "figure.stand"
        case .other: return "person.fill.questionmark"
        }
    }

    var promptDescription: String {
        switch self {
        case .atDesk: return "seated at a desk"
        case .standing: return "standing upright"
        case .other: return "in a general position"
        }
    }
}

/// The result of a single posture check-in analysis.
struct PostureCheckResult: Codable, Identifiable {
    var id: UUID = UUID()
    /// Context in which the check was performed
    var context: PostureContext
    /// Overall alignment score (0–100; higher is better)
    var score: Int
    /// 2–3 specific posture observations from the AI
    var observations: [String]
    /// 1–2 actionable corrective cues
    var correctiveCues: [String]
    /// Date and time of the check
    var captureDate: Date = Date()
    /// Firestore document ID, populated after saving
    var firestoreId: String?

    // MARK: - Computed

    var scoreLabel: String {
        switch score {
        case 80...100: return "Great"
        case 60..<80:  return "Good"
        case 40..<60:  return "Fair"
        default:       return "Needs Work"
        }
    }

    var scoreColorName: String {
        switch score {
        case 80...100: return "success"
        case 60..<80:  return "accent"
        case 40..<60:  return "warning"
        default:       return "danger"
        }
    }
}
