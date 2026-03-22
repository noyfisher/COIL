import Foundation

/// Defines 6 anatomical zones that group the 30 body regions into logical areas.
/// Used for the two-step drill-down selection flow in the 3D body map.
enum BodyZone: String, CaseIterable, Identifiable {
    case headNeck = "head_neck"
    case torso = "torso"
    case leftArm = "left_arm"
    case rightArm = "right_arm"
    case leftLeg = "left_leg"
    case rightLeg = "right_leg"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .headNeck: return "Head & Neck"
        case .torso: return "Torso"
        case .leftArm: return "Left Arm"
        case .rightArm: return "Right Arm"
        case .leftLeg: return "Left Leg"
        case .rightLeg: return "Right Leg"
        }
    }

    var iconName: String {
        switch self {
        case .headNeck: return "brain.head.profile"
        case .torso: return "heart.fill"
        case .leftArm, .rightArm: return "figure.arms.open"
        case .leftLeg, .rightLeg: return "figure.walk"
        }
    }

    /// The region zoneKeys that belong to this zone.
    var regionZoneKeys: [String] {
        switch self {
        case .headNeck:
            return ["head", "neck"]
        case .torso:
            return ["chest", "abdomen", "upper_back", "lower_back"]
        case .leftArm:
            return ["left_shoulder", "left_upper_arm", "left_elbow", "left_forearm", "left_wrist_hand"]
        case .rightArm:
            return ["right_shoulder", "right_upper_arm", "right_elbow", "right_forearm", "right_wrist_hand"]
        case .leftLeg:
            return ["left_hip", "left_glute", "left_thigh", "left_hamstring", "left_knee", "left_calf_shin", "left_ankle_foot"]
        case .rightLeg:
            return ["right_hip", "right_glute", "right_thigh", "right_hamstring", "right_knee", "right_calf_shin", "right_ankle_foot"]
        }
    }

    /// Look up which zone a given region zoneKey belongs to.
    static func zone(for zoneKey: String) -> BodyZone? {
        for zone in BodyZone.allCases {
            if zone.regionZoneKeys.contains(zoneKey) {
                return zone
            }
        }
        return nil
    }
}
