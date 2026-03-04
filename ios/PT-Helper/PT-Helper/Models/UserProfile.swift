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

    struct Surgery: Codable, Identifiable {
        var id: UUID = UUID()
        var name: String
        var year: Int
    }

    struct Injury: Codable, Identifiable {
        var id: UUID = UUID()
        var bodyArea: String
        var description: String
        var isCurrent: Bool
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

        if let surgeriesData = data["surgeries"] as? [[String: Any]] {
            profile.surgeries = surgeriesData.map { s in
                Surgery(
                    id: UUID(uuidString: s["id"] as? String ?? "") ?? UUID(),
                    name: s["name"] as? String ?? "",
                    year: s["year"] as? Int ?? 2024
                )
            }
        }

        if let injuriesData = data["injuries"] as? [[String: Any]] {
            profile.injuries = injuriesData.map { i in
                Injury(
                    id: UUID(uuidString: i["id"] as? String ?? "") ?? UUID(),
                    bodyArea: i["bodyArea"] as? String ?? "",
                    description: i["description"] as? String ?? "",
                    isCurrent: i["isCurrent"] as? Bool ?? false
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
