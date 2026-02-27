import SwiftUI
import Foundation
import FirebaseFirestore
import FirebaseAuth

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: Int = 1
    @Published var userProfile = UserProfile(userId: Auth.auth().currentUser?.uid ?? "",
                                             firstName: "",
                                             lastName: "",
                                             dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date(),
                                             sex: "",
                                             heightFeet: 5,
                                             heightInches: 7,
                                             weight: 0.0,
                                             medicalConditions: [],
                                             otherMedicalConditions: nil,
                                             surgeries: [],
                                             injuries: [],
                                             activityLevel: "",
                                             primarySport: nil)

    private let db = Firestore.firestore()

    func saveProfile(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            AppLogger.auth.error("Error saving profile: no authenticated user")
            completion(false)
            return
        }
        userProfile.userId = uid

        // Build dictionary manually to avoid Codable encoding issues
        var profileData: [String: Any] = [
            "userId": uid,
            "firstName": userProfile.firstName,
            "lastName": userProfile.lastName,
            "dateOfBirth": Timestamp(date: userProfile.dateOfBirth),
            "sex": userProfile.sex,
            "heightFeet": userProfile.heightFeet,
            "heightInches": userProfile.heightInches,
            "weight": userProfile.weight,
            "medicalConditions": userProfile.medicalConditions,
            "surgeries": userProfile.surgeries.map { surgery -> [String: Any] in
                [
                    "id": surgery.id.uuidString,
                    "name": surgery.name,
                    "year": surgery.year
                ]
            },
            "injuries": userProfile.injuries.map { injury -> [String: Any] in
                [
                    "id": injury.id.uuidString,
                    "bodyArea": injury.bodyArea,
                    "description": injury.description,
                    "isCurrent": injury.isCurrent
                ]
            },
            "activityLevel": userProfile.activityLevel
        ]
        if let other = userProfile.otherMedicalConditions {
            profileData["otherMedicalConditions"] = other
        }
        if let sport = userProfile.primarySport {
            profileData["primarySport"] = sport
        }

        db.collection("users").document(uid).collection("profile").document("health")
            .setData(profileData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        AppLogger.data.error("Error saving profile: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        completion(true)
                    }
                }
            }
    }

    func loadProfile(completion: @escaping (Bool) -> Void) {
        guard let uid = Auth.auth().currentUser?.uid else {
            completion(false)
            return
        }
        db.collection("users").document(uid).collection("profile").document("health").getDocument { snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    AppLogger.data.error("Error loading profile: \(error.localizedDescription)")
                    completion(false)
                } else if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                    // Parse manually to match our manual save format
                    var profile = UserProfile(
                        userId: data["userId"] as? String ?? uid,
                        firstName: data["firstName"] as? String ?? "",
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

                    // Parse surgeries
                    if let surgeriesData = data["surgeries"] as? [[String: Any]] {
                        profile.surgeries = surgeriesData.map { s in
                            UserProfile.Surgery(
                                id: UUID(uuidString: s["id"] as? String ?? "") ?? UUID(),
                                name: s["name"] as? String ?? "",
                                year: s["year"] as? Int ?? 2024
                            )
                        }
                    }

                    // Parse injuries
                    if let injuriesData = data["injuries"] as? [[String: Any]] {
                        profile.injuries = injuriesData.map { i in
                            UserProfile.Injury(
                                id: UUID(uuidString: i["id"] as? String ?? "") ?? UUID(),
                                bodyArea: i["bodyArea"] as? String ?? "",
                                description: i["description"] as? String ?? "",
                                isCurrent: i["isCurrent"] as? Bool ?? false
                            )
                        }
                    }

                    self.userProfile = profile
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }
    }

    /// Whether the current step has all required fields filled in
    var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case 1:
            // Basic info: need first name, last name, sex, reasonable height/weight
            let hasName = !userProfile.firstName.trimmingCharacters(in: .whitespaces).isEmpty
                && !userProfile.lastName.trimmingCharacters(in: .whitespaces).isEmpty
            let hasSex = !userProfile.sex.isEmpty
            let hasHeight = userProfile.heightFeet >= 3 && userProfile.heightFeet <= 7
            let hasWeight = userProfile.weight >= 50 && userProfile.weight <= 500
            return hasName && hasSex && hasHeight && hasWeight
        case 5:
            // Activity level must be selected
            return !userProfile.activityLevel.isEmpty
        default:
            // Steps 2, 3, 4 (medical, surgical, injury history) are optional
            // Step 6 is the review/submit step
            return true
        }
    }

    /// Set to true when the user attempts to proceed but validation fails.
    /// Views observe this to show inline error messages.
    @Published var showValidationErrors = false

    func nextStep() {
        if currentStep < 6 && canProceedFromCurrentStep {
            showValidationErrors = false
            currentStep += 1
        } else {
            showValidationErrors = true
        }
    }

    func previousStep() {
        if currentStep > 1 {
            currentStep -= 1
        }
    }
}
