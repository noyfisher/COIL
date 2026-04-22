import Foundation
import FirebaseFirestore
import FirebaseAuth

struct UserProfile: Codable, Identifiable {
    var id: String { userId }
    var userId: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var sex: String
    var heightFeet: Int
    var heightInches: Int
    var weight: Double
    var medicalConditions: [String]
    var otherMedicalConditions: String?
    var surgeries: [Surgery]
    var injuries: [Injury]
    var activityLevel: String
    var primarySport: String?

    var age: Int {
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return ageComponents.year ?? 0
    }

    var medications: [String]?
    var dominantSide: String?           // "Left" | "Right" | "Ambidextrous"
    var medicationHistory: [MedicationChange]?
    var wellnessGoals: [WellnessGoal] = []

    struct Surgery: Codable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var year: Int
        var bodyArea: String?
        var recoveryStatus: String?     // "Fully recovered" | "Still recovering" | "Have restrictions"
        var restrictions: String?
        var surgeryType: String?        // Exact name or description of the surgery
        var causingInjury: String?      // What injury led to this surgery
        var hasHardware: Bool?          // Whether pins/screws/plates remain
        var hardwareDetails: String?    // Description of remaining hardware
    }

    struct MedicationChange: Codable, Equatable {
        let medication: String
        let action: String              // "started" or "stopped"
        let date: Date
    }

    struct Injury: Codable, Identifiable {
        var id: UUID = UUID()
        var bodyArea: String
        var description: String
        var isCurrent: Bool
        var year: Int?
        var sawDoctor: Bool?
        var hadPhysicalTherapy: Bool?
        var recoveryStatus: String?     // "Fully recovered" | "Mostly recovered" | "Still dealing with it"
    }

    struct WellnessGoal: Codable, Identifiable {
        var id: UUID = UUID()
        var category: GoalCategory
        var customDescription: String?
        var startDate: Date
        var isActive: Bool
    }

    // MARK: - Firestore Parsing

    /// Create a UserProfile from a Firestore data dictionary.
    static func from(firestoreData data: [String: Any]) -> UserProfile {
        let uid = data["userId"] as? String ?? Auth.auth().currentUser?.uid ?? ""

        var profile = UserProfile(
            userId: uid,
            firstName: data["firstName"] as? String ?? data["name"] as? String ?? "",
            lastName: data["lastName"] as? String ?? "",
            dateOfBirth: (data["dateOfBirth"] as? Timestamp)?.dateValue() ?? Date(),
            sex: data["sex"] as? String ?? "",
            heightFeet: data["heightFeet"] as? Int ?? 0,
            heightInches: data["heightInches"] as? Int ?? 0,
            weight: data["weight"] as? Double ?? 0.0,
            medicalConditions: data["medicalConditions"] as? [String] ?? [],
            otherMedicalConditions: data["otherMedicalConditions"] as? String,
            surgeries: [],
            injuries: [],
            activityLevel: data["activityLevel"] as? String ?? "",
            primarySport: data["primarySport"] as? String
        )

        profile.medications = data["medications"] as? [String]
        profile.dominantSide = data["dominantSide"] as? String

        // Parse medication history
        if let historyData = data["medicationHistory"] as? [[String: Any]] {
            let isoFormatter = ISO8601DateFormatter()
            profile.medicationHistory = historyData.compactMap { entry in
                guard let medication = entry["medication"] as? String,
                      let action = entry["action"] as? String else { return nil }
                let date: Date
                if let dateString = entry["date"] as? String,
                   let parsed = isoFormatter.date(from: dateString) {
                    date = parsed
                } else if let timestamp = entry["date"] as? Timestamp {
                    date = timestamp.dateValue()
                } else {
                    date = Date()
                }
                return MedicationChange(medication: medication, action: action, date: date)
            }
        }

        if let surgeriesData = data["surgeries"] as? [[String: Any]] {
            profile.surgeries = surgeriesData.map { s in
                Surgery(
                    id: UUID(uuidString: s["id"] as? String ?? "") ?? UUID(),
                    name: s["name"] as? String ?? "",
                    year: s["year"] as? Int ?? 2024,
                    bodyArea: s["bodyArea"] as? String,
                    recoveryStatus: s["recoveryStatus"] as? String,
                    restrictions: s["restrictions"] as? String,
                    surgeryType: s["surgeryType"] as? String,
                    causingInjury: s["causingInjury"] as? String,
                    hasHardware: s["hasHardware"] as? Bool,
                    hardwareDetails: s["hardwareDetails"] as? String
                )
            }
        }

        if let injuriesData = data["injuries"] as? [[String: Any]] {
            profile.injuries = injuriesData.map { i in
                Injury(
                    id: UUID(uuidString: i["id"] as? String ?? "") ?? UUID(),
                    bodyArea: i["bodyArea"] as? String ?? "",
                    description: i["description"] as? String ?? "",
                    isCurrent: i["isCurrent"] as? Bool ?? false,
                    year: i["year"] as? Int,
                    sawDoctor: i["sawDoctor"] as? Bool,
                    hadPhysicalTherapy: i["hadPhysicalTherapy"] as? Bool,
                    recoveryStatus: i["recoveryStatus"] as? String
                )
            }
        }

        if let goalsData = data["wellnessGoals"] as? [[String: Any]] {
            profile.wellnessGoals = goalsData.compactMap { g in
                guard let categoryRaw = g["category"] as? String,
                      let category = GoalCategory(rawValue: categoryRaw) else { return nil }
                let startDate: Date
                if let ts = g["startDate"] as? Timestamp {
                    startDate = ts.dateValue()
                } else {
                    startDate = Date()
                }
                return WellnessGoal(
                    id: UUID(uuidString: g["id"] as? String ?? "") ?? UUID(),
                    category: category,
                    customDescription: g["customDescription"] as? String,
                    startDate: startDate,
                    isActive: g["isActive"] as? Bool ?? true
                )
            }
        }

        return profile
    }

    /// Computed property for full name
    var name: String {
        let full = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? firstName : full
    }
}
