import SwiftUI
import FirebaseAuth

@MainActor
class BodyMapViewModel: ObservableObject {
    @Published var regions: [BodyRegion] = []
    @Published var currentSide: BodySide = .front
    @Published var activeZone: BodyZone?

    /// User profile sourced from the shared UserProfileService (single Firestore read).
    var userProfile: UserProfile {
        UserProfileService.shared.profile ?? UserProfile(
            userId: Auth.auth().currentUser?.uid ?? "",
            firstName: "", lastName: "",
            dateOfBirth: Date(), sex: "",
            heightFeet: 0, heightInches: 0, weight: 0.0,
            medicalConditions: [], otherMedicalConditions: nil,
            surgeries: [], injuries: [],
            activityLevel: "", primarySport: nil
        )
    }

    init() {
        loadRegions()
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

    /// Regions belonging to a specific zone.
    func regions(in zone: BodyZone) -> [BodyRegion] {
        let keys = Set(zone.regionZoneKeys)
        return regions.filter { keys.contains($0.zoneKey) }
    }

    /// Count of selected regions within a zone.
    func selectedCount(in zone: BodyZone) -> Int {
        regions(in: zone).filter(\.isSelected).count
    }

    private func loadRegions() {
        regions = [
            // ── Head & Neck ───────────────────────────────────
            BodyRegion(name: "Head", zoneKey: "head",
                       sides: [.front],
                       frontPosition: CGPoint(x: 0.5, y: 0.05),
                       backPosition: nil),

            BodyRegion(name: "Neck", zoneKey: "neck",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.5, y: 0.12),
                       backPosition: CGPoint(x: 0.5, y: 0.10)),

            // ── Torso (front) ─────────────────────────────────
            BodyRegion(name: "Chest", zoneKey: "chest",
                       sides: [.front],
                       frontPosition: CGPoint(x: 0.5, y: 0.22),
                       backPosition: nil),

            BodyRegion(name: "Abdomen", zoneKey: "abdomen",
                       sides: [.front],
                       frontPosition: CGPoint(x: 0.5, y: 0.38),
                       backPosition: nil),

            // ── Torso (back) ──────────────────────────────────
            BodyRegion(name: "Upper Back", zoneKey: "upper_back",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.5, y: 0.22)),

            BodyRegion(name: "Lower Back", zoneKey: "lower_back",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.5, y: 0.38)),

            // ── Shoulders ─────────────────────────────────────
            BodyRegion(name: "Left Shoulder", zoneKey: "left_shoulder",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.28, y: 0.18),
                       backPosition: CGPoint(x: 0.72, y: 0.18)),

            BodyRegion(name: "Right Shoulder", zoneKey: "right_shoulder",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.72, y: 0.18),
                       backPosition: CGPoint(x: 0.28, y: 0.18)),

            // ── Upper Arms ────────────────────────────────────
            BodyRegion(name: "Left Upper Arm", zoneKey: "left_upper_arm",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.2, y: 0.28),
                       backPosition: CGPoint(x: 0.8, y: 0.28)),

            BodyRegion(name: "Right Upper Arm", zoneKey: "right_upper_arm",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.8, y: 0.28),
                       backPosition: CGPoint(x: 0.2, y: 0.28)),

            // ── Elbows ───────────────────────────────────────
            BodyRegion(name: "Left Elbow", zoneKey: "left_elbow",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.18, y: 0.34),
                       backPosition: CGPoint(x: 0.82, y: 0.34)),

            BodyRegion(name: "Right Elbow", zoneKey: "right_elbow",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.82, y: 0.34),
                       backPosition: CGPoint(x: 0.18, y: 0.34)),

            // ── Forearms ──────────────────────────────────────
            BodyRegion(name: "Left Forearm", zoneKey: "left_forearm",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.15, y: 0.40),
                       backPosition: CGPoint(x: 0.85, y: 0.40)),

            BodyRegion(name: "Right Forearm", zoneKey: "right_forearm",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.85, y: 0.40),
                       backPosition: CGPoint(x: 0.15, y: 0.40)),

            // ── Wrists & Hands ────────────────────────────────
            BodyRegion(name: "Left Wrist/Hand", zoneKey: "left_wrist_hand",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.12, y: 0.52),
                       backPosition: CGPoint(x: 0.88, y: 0.52)),

            BodyRegion(name: "Right Wrist/Hand", zoneKey: "right_wrist_hand",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.88, y: 0.52),
                       backPosition: CGPoint(x: 0.12, y: 0.52)),

            // ── Glutes ────────────────────────────────────────
            BodyRegion(name: "Left Glute", zoneKey: "left_glute",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.62, y: 0.50)),

            BodyRegion(name: "Right Glute", zoneKey: "right_glute",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.38, y: 0.50)),

            // ── Hips ──────────────────────────────────────────
            BodyRegion(name: "Left Hip", zoneKey: "left_hip",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.50),
                       backPosition: CGPoint(x: 0.62, y: 0.52)),

            BodyRegion(name: "Right Hip", zoneKey: "right_hip",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.50),
                       backPosition: CGPoint(x: 0.38, y: 0.52)),

            // ── Thighs (quads, adductors, IT band) ───────────
            BodyRegion(name: "Left Thigh", zoneKey: "left_thigh",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.60),
                       backPosition: CGPoint(x: 0.62, y: 0.60)),

            BodyRegion(name: "Right Thigh", zoneKey: "right_thigh",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.60),
                       backPosition: CGPoint(x: 0.38, y: 0.60)),

            // ── Hamstrings ────────────────────────────────────
            BodyRegion(name: "Left Hamstring", zoneKey: "left_hamstring",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.62, y: 0.62)),

            BodyRegion(name: "Right Hamstring", zoneKey: "right_hamstring",
                       sides: [.back],
                       frontPosition: nil,
                       backPosition: CGPoint(x: 0.38, y: 0.62)),

            // ── Knees ─────────────────────────────────────────
            BodyRegion(name: "Left Knee", zoneKey: "left_knee",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.72),
                       backPosition: CGPoint(x: 0.62, y: 0.72)),

            BodyRegion(name: "Right Knee", zoneKey: "right_knee",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.72),
                       backPosition: CGPoint(x: 0.38, y: 0.72)),

            // ── Calves & Shins ────────────────────────────────
            BodyRegion(name: "Left Calf/Shin", zoneKey: "left_calf_shin",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.80),
                       backPosition: CGPoint(x: 0.62, y: 0.80)),

            BodyRegion(name: "Right Calf/Shin", zoneKey: "right_calf_shin",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.80),
                       backPosition: CGPoint(x: 0.38, y: 0.80)),

            // ── Ankles & Feet ─────────────────────────────────
            BodyRegion(name: "Left Ankle/Foot", zoneKey: "left_ankle_foot",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.38, y: 0.92),
                       backPosition: CGPoint(x: 0.62, y: 0.92)),

            BodyRegion(name: "Right Ankle/Foot", zoneKey: "right_ankle_foot",
                       sides: [.front, .back],
                       frontPosition: CGPoint(x: 0.62, y: 0.92),
                       backPosition: CGPoint(x: 0.38, y: 0.92)),
        ]
    }

}
