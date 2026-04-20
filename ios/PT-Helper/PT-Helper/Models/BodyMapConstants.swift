import SwiftUI
import UIKit

/// Single source of truth for all Body Map 3D configuration.
/// Used by both `BodyMap3DView` and `BodyMapCollisionTests`.
enum BodyMapConstants {

    // MARK: - Gesture Sensitivity

    static let rotationSensitivity: Float = 0.008
    static let panSensitivity: Float = 0.003
    // MARK: - Momentum Physics

    static let momentumFriction: Float = 0.93
    static let momentumStopThreshold: Float = 0.0001
    static let momentumFPS: TimeInterval = 1.0 / 60.0

    // MARK: - Zoom / Scale

    static let minScale: Float = 0.6
    static let maxScale: Float = 4.0
    static let doubleTapZoomLevel: Float = 2.5
    static let rubberBandFactor: Float = 0.3
    /// Absolute minimum visual scale (prevents inversion during rubber-band)
    static let absoluteMinScale: Float = 0.4
    /// Below this zoom level, snap pan back to center
    static let snapToCenterThreshold: Float = 1.1

    // MARK: - Model

    /// Scale factor so the body fills the viewport on load
    static let modelScale: Float = 3.5
    /// Model origin is at feet — shift down so torso center aligns with pivot
    static let modelHalfHeight: Float = 0.85

    // MARK: - Proxy Entities

    /// Prefix for invisible tap-target proxy entity names
    static let proxyPrefix = "_proxy_"

    /// Small regions that get forward-protruding invisible proxy spheres.
    /// Key = base region key (no left_/right_ prefix), Value = sphere radius in model space.
    /// Arm regions (shoulder, upper_arm, elbow, forearm, wrist_hand) are handled
    /// by `createArmZoneProxies` instead — each gets a Y-band box proxy so arm
    /// taps resolve to the correct region with clean vertical boundaries.
    static let proxyRadii: [String: Float] = [
        "head": 0.04,
        "knee": 0.025,
        "ankle_foot": 0.035,
        "neck": 0.020,
    ]

    /// How far anterior (toward camera) proxy entities protrude past the mesh
    static let proxyForwardBias: Float = 0.02

    /// Lateral offset for ankle proxies to protrude past the calf convex hull
    static let ankleProxyLateralBias: Float = 0.015

    /// Fraction from bottom of knee mesh where the kneecap actually is
    static let kneeCapHeightFraction: Float = 0.2

    /// Fraction of ankle zone height used for capsule height
    static let ankleCapsuleHeightFraction: Float = 0.5

    /// How far anterior each arm zone box protrudes past its region's mesh
    /// front. Ensures the zoned box is hit before any adjacent region's
    /// convex hull at the same (X, Y) position. Mirrors `proxyForwardBias`.
    static let armZoneForwardBias: Float = 0.03

    /// Ordered arm region keys from top (shoulder) to bottom (wrist_hand).
    /// Used by `createArmZoneProxies` to build adjacent, non-overlapping
    /// Y-banded collisions so every tap inside a region's band resolves to
    /// that region — no convex hull bloat, no neighbor interception.
    static let armRegionOrder: [String] = [
        "shoulder", "upper_arm", "elbow", "forearm", "wrist_hand"
    ]

    // MARK: - Highlight Material

    static let highlightColor = UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1.0)
    static let highlightRoughness: Float = 0.25
    static let highlightMetallic: Float = 0.15

    // MARK: - Region Material

    static let regionRoughness: Float = 0.45
    static let regionMetallic: Float = 0.05

    // MARK: - Region Color Palette

    /// Color coding for each region group. Bilateral pairs share a color.
    /// Key = base region key (no left_/right_ prefix).
    static let regionColors: [String: UIColor] = [
        "head":       UIColor(red: 0.318, green: 0.749, blue: 0.427, alpha: 1),  // #51BF6D — spring green
        "neck":       UIColor(red: 0.624, green: 0.812, blue: 0.784, alpha: 1),  // #9FCFC8 — pale aqua
        "chest":      UIColor(red: 0.333, green: 0.769, blue: 0.710, alpha: 1),  // #55C4B5 — teal mint
        "abdomen":    UIColor(red: 0.549, green: 0.824, blue: 0.529, alpha: 1),  // #8CD287 — soft lime
        "upper_back": UIColor(red: 0.231, green: 0.675, blue: 0.224, alpha: 1),  // #3BAC39 — kelly green
        "lower_back": UIColor(red: 0.314, green: 0.588, blue: 0.545, alpha: 1),  // #50968B — deep sage teal
        "shoulder":   UIColor(red: 0.310, green: 0.588, blue: 0.349, alpha: 1),  // #4F9659 — forest sage
        "upper_arm":  UIColor(red: 0.435, green: 0.698, blue: 0.584, alpha: 1),  // #6FB295 — seafoam
        "elbow":      UIColor(red: 0.490, green: 0.816, blue: 0.682, alpha: 1),  // #7DD0AE — mint cream
        "forearm":    UIColor(red: 0.286, green: 0.733, blue: 0.569, alpha: 1),  // #49BB91 — jade
        "wrist_hand": UIColor(red: 0.451, green: 0.710, blue: 0.443, alpha: 1),  // #73B571 — sage green
        "glute":      UIColor(red: 0.624, green: 0.812, blue: 0.635, alpha: 1),  // #9FCFA2 — pale sage
        "hip":        UIColor(red: 0.310, green: 0.761, blue: 0.286, alpha: 1),  // #4FC249 — vivid green
        "thigh":      UIColor(red: 0.412, green: 0.804, blue: 0.514, alpha: 1),  // #69CD83 — emerald mint
        "hamstring":  UIColor(red: 0.231, green: 0.671, blue: 0.427, alpha: 1),  // #3BAB6D — clover
        "knee":       UIColor(red: 0.514, green: 0.831, blue: 0.788, alpha: 1),  // #83D4C9 — aqua mist
        "calf_shin":  UIColor(red: 0.353, green: 0.655, blue: 0.467, alpha: 1),  // #5AA777 — eucalyptus
        "ankle_foot": UIColor(red: 0.380, green: 0.706, blue: 0.353, alpha: 1),  // #61B45A — leaf green
    ]

    // MARK: - Zone Drill-Down

    /// Alpha tint for dimmed (non-zone) region materials during drill-down.
    /// 0.02 makes them nearly invisible — a faint ghost outline only.
    static let zoneDimAlpha: CGFloat = 0.06
    static let zoneDimRoughness: Float = 0.8
    static let zoneDimMetallic: Float = 0.0

    /// Camera animation durations
    static let zoneDrillDuration: TimeInterval = 0.5
    static let zoneExitDuration: TimeInterval = 0.4

    /// Per-zone camera framing targets.
    /// pivotX: horizontal translation to center the zone (positive = shift right on screen).
    /// pivotY: vertical translation (negative = shift up toward head, positive = shift down).
    /// pivotScale: uniform scale to zoom in on the zone.
    /// rotation: additional Y-axis rotation (radians) to face the zone toward the camera.
    static let zoneCameraTargets: [String: (pivotX: Float, pivotY: Float, pivotScale: Float, rotation: Float)] = [
        "head_neck":  (pivotX: 0,     pivotY: -0.70, pivotScale: 2.8, rotation: 0),
        "torso":      (pivotX: 0,     pivotY: -0.50, pivotScale: 2.8, rotation: 0),
        "left_arm":   (pivotX: 0.30,  pivotY: -0.55, pivotScale: 2.5, rotation: 0.65),
        "right_arm":  (pivotX: -0.30, pivotY: -0.55, pivotScale: 2.5, rotation: -0.65),
        "left_leg":   (pivotX: 0,     pivotY: 0.60,  pivotScale: 2.5, rotation: 0),
        "right_leg":  (pivotX: 0,     pivotY: 0.60,  pivotScale: 2.5, rotation: 0),
    ]

    // MARK: - Background

    static let sceneBackground = UIColor(red: 0.91, green: 0.94, blue: 0.91, alpha: 1.0)           // #E8F0E9
    static let loadingOverlayBackground = UIColor(red: 0.91, green: 0.94, blue: 0.91, alpha: 0.95)  // #E8F0E9

    // MARK: - Helpers

    /// Strip left_/right_ prefix to get the base region key for color/proxy lookup.
    static func regionBaseKey(_ zoneKey: String) -> String {
        if zoneKey.hasPrefix("left_") { return String(zoneKey.dropFirst(5)) }
        if zoneKey.hasPrefix("right_") { return String(zoneKey.dropFirst(6)) }
        return zoneKey
    }
}
