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
                                             weight: TestDataSeeder.shouldPrefillWeight ? 170.0 : 0.0,
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
                var dict: [String: Any] = [
                    "id": surgery.id.uuidString,
                    "name": surgery.name,
                    "year": surgery.year
                ]
                if let bodyArea = surgery.bodyArea { dict["bodyArea"] = bodyArea }
                if let status = surgery.recoveryStatus { dict["recoveryStatus"] = status }
                if let restrictions = surgery.restrictions { dict["restrictions"] = restrictions }
                if let surgeryType = surgery.surgeryType { dict["surgeryType"] = surgeryType }
                if let causingInjury = surgery.causingInjury { dict["causingInjury"] = causingInjury }
                if let hasHardware = surgery.hasHardware { dict["hasHardware"] = hasHardware }
                if let hardwareDetails = surgery.hardwareDetails { dict["hardwareDetails"] = hardwareDetails }
                return dict
            },
            "injuries": userProfile.injuries.map { injury -> [String: Any] in
                var dict: [String: Any] = [
                    "id": injury.id.uuidString,
                    "bodyArea": injury.bodyArea,
                    "description": injury.description,
                    "isCurrent": injury.isCurrent
                ]
                if let year = injury.year { dict["year"] = year }
                if let saw = injury.sawDoctor { dict["sawDoctor"] = saw }
                if let pt = injury.hadPhysicalTherapy { dict["hadPhysicalTherapy"] = pt }
                if let status = injury.recoveryStatus { dict["recoveryStatus"] = status }
                return dict
            },
            "activityLevel": userProfile.activityLevel
        ]
        if let other = userProfile.otherMedicalConditions {
            profileData["otherMedicalConditions"] = other
        }
        if let sport = userProfile.primarySport {
            profileData["primarySport"] = sport
        }
        if let meds = userProfile.medications, !meds.isEmpty {
            profileData["medications"] = meds
        }
        if let side = userProfile.dominantSide {
            profileData["dominantSide"] = side
        }

        // Medication history: merge existing history with any new changes
        let isoFormatter = ISO8601DateFormatter()
        if let history = userProfile.medicationHistory, !history.isEmpty {
            profileData["medicationHistory"] = history.map { change -> [String: Any] in
                [
                    "medication": change.medication,
                    "action": change.action,
                    "date": isoFormatter.string(from: change.date)
                ]
            }
        }

        db.collection("users").document(uid).collection("profile").document("health")
            .setData(profileData) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        AppLogger.data.error("Error saving profile: \(error.localizedDescription)")
                        completion(false)
                    } else {
                        AnalyticsService.shared.log(.onboardingCompleted)
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
                            return UserProfile.MedicationChange(medication: medication, action: action, date: date)
                        }
                    }

                    // Parse surgeries
                    if let surgeriesData = data["surgeries"] as? [[String: Any]] {
                        profile.surgeries = surgeriesData.map { s in
                            UserProfile.Surgery(
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

                    // Parse injuries
                    if let injuriesData = data["injuries"] as? [[String: Any]] {
                        profile.injuries = injuriesData.map { i in
                            UserProfile.Injury(
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
            AnalyticsService.shared.log(.onboardingStepCompleted, parameters: ["step_number": currentStep - 1])
        } else {
            showValidationErrors = true
        }
    }

    func previousStep() {
        if currentStep > 1 {
            currentStep -= 1
        }
    }

    // MARK: - Medication Diff Tracking

    /// Computes medication changes between previous and current medications,
    /// appends them to the existing medication history.
    func updateMedicationHistory(previousMedications: [String]?) {
        let oldMeds = Set(previousMedications ?? [])
        let newMeds = Set(userProfile.medications ?? [])

        let now = Date()
        var changes: [UserProfile.MedicationChange] = userProfile.medicationHistory ?? []

        // Newly added medications
        for med in newMeds.subtracting(oldMeds) {
            changes.append(UserProfile.MedicationChange(medication: med, action: "started", date: now))
        }

        // Removed medications
        for med in oldMeds.subtracting(newMeds) {
            changes.append(UserProfile.MedicationChange(medication: med, action: "stopped", date: now))
        }

        userProfile.medicationHistory = changes
    }
}
