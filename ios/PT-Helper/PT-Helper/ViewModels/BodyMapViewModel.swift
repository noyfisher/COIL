import SwiftUI
import FirebaseFirestore
import FirebaseAuth

class BodyMapViewModel: ObservableObject {
    @Published var regions: [BodyRegion] = []
    @Published var currentSide: BodySide = .front
    @Published var userProfile = UserProfile(
        userId: Auth.auth().currentUser?.uid ?? "",
        firstName: "", lastName: "",
        dateOfBirth: Date(), sex: "",
        heightFeet: 0, heightInches: 0, weight: 0.0,
        medicalConditions: [], otherMedicalConditions: nil,
        surgeries: [], injuries: [],
        activityLevel: "", primarySport: nil
    )

    private let db = Firestore.firestore()

    init() {
        loadRegions()
        loadUserProfile()
    }

    func toggleSelection(for region: BodyRegion) {
        if let index = regions.firstIndex(where: { $0.id == region.id }) {
            regions[index].isSelected.toggle()
        }
    }

    func clearAll() {
        for i in regions.indices {
            regions[i].isSelected = false
        }
    }

    /// Regions visible on the current side (front or back).
    var regionsForCurrentSide: [BodyRegion] {
        regions.filter { $0.sides.contains(currentSide) }
    }

    /// All selected regions across both sides (passed to PainDetailView).
    var selectedRegions: [BodyRegion] {
        regions.filter { $0.isSelected }
    }

    private func loadRegions() {
        regions = [
            // ── Front-only regions ──────────────────────────────
            BodyRegion(name: "Head/Neck", zoneKey: "head_neck",
                       sides: [.front],
                       frontPosition: CGPoint(x: 0.5, y: 0.08),
                       backPosition: nil),

            BodyRegion(name: "Chest", zoneKey: "chest",
                       sides: [.front],
                       frontPosition: CGPoint(x: 0.5, y: 0.25),
                       backPosition: nil),

            BodyRegion(name: "Abdomen", zoneKey: "abdomen",
                       sides: [.front],
                       frontPosition: CGPoint(x: 0.5, y: 0.42),
                       backPosition: nil),

            // ── Back-only regions ───────────────────────────────
            BodyRegion(name: "Upper Back", zoneKey: "upper_back",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.5, y: 0.25)),

            BodyRegion(name: "Lower Back", zoneKey: "lower_back",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.5, y: 0.42)),

            // ── Both-side regions (mirrored x on back) ─────────
            BodyRegion(name: "Left Shoulder", zoneKey: "left_shoulder",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.3, y: 0.2),
                       backPosition: CGPoint(x: 0.7, y: 0.2)),

            BodyRegion(name: "Right Shoulder", zoneKey: "right_shoulder",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.7, y: 0.2),
                       backPosition: CGPoint(x: 0.3, y: 0.2)),

            BodyRegion(name: "Left Elbow", zoneKey: "left_elbow",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.2, y: 0.38),
                       backPosition: CGPoint(x: 0.8, y: 0.38)),

            BodyRegion(name: "Right Elbow", zoneKey: "right_elbow",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.8, y: 0.38),
                       backPosition: CGPoint(x: 0.2, y: 0.38)),

            BodyRegion(name: "Left Wrist/Hand", zoneKey: "left_wrist_hand",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.15, y: 0.52),
                       backPosition: CGPoint(x: 0.85, y: 0.52)),

            BodyRegion(name: "Right Wrist/Hand", zoneKey: "right_wrist_hand",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.85, y: 0.52),
                       backPosition: CGPoint(x: 0.15, y: 0.52)),

            BodyRegion(name: "Left Hip", zoneKey: "left_hip",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.55),
                       backPosition: CGPoint(x: 0.62, y: 0.55)),

            BodyRegion(name: "Right Hip", zoneKey: "right_hip",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.55),
                       backPosition: CGPoint(x: 0.38, y: 0.55)),

            BodyRegion(name: "Left Knee", zoneKey: "left_knee",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.72),
                       backPosition: CGPoint(x: 0.62, y: 0.72)),

            BodyRegion(name: "Right Knee", zoneKey: "right_knee",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.72),
                       backPosition: CGPoint(x: 0.38, y: 0.72)),

            BodyRegion(name: "Left Ankle/Foot", zoneKey: "left_ankle_foot",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.35, y: 0.9),
                       backPosition: CGPoint(x: 0.65, y: 0.9)),

            BodyRegion(name: "Right Ankle/Foot", zoneKey: "right_ankle_foot",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.65, y: 0.9),
                       backPosition: CGPoint(x: 0.35, y: 0.9))
        ]
    }

    private func loadUserProfile() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).collection("profile").document("health").getDocument { snapshot, error in
            if let error = error {
                AppLogger.data.error("Error loading user profile: \(error.localizedDescription)")
            } else if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                DispatchQueue.main.async {
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
                    if let surgeriesData = data["surgeries"] as? [[String: Any]] {
                        profile.surgeries = surgeriesData.map { s in
                            UserProfile.Surgery(
                                id: UUID(uuidString: s["id"] as? String ?? "") ?? UUID(),
                                name: s["name"] as? String ?? "",
                                year: s["year"] as? Int ?? 2024
                            )
                        }
                    }
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
                }
            }
        }
    }
}
