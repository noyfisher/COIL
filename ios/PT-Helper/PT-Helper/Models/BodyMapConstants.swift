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
    static let proxyRadii: [String: Float] = [
        "head": 0.04,
        "knee": 0.025,
        "elbow": 0.018,
        "ankle_foot": 0.035,
        "wrist_hand": 0.03,
        "neck": 0.020,
        "shoulder": 0.022,
        "hip": 0.04,
        "glute": 0.022,
        "hamstring": 0.022,
        "forearm": 0.025,
        "upper_arm": 0.020,
    ]

    /// How far anterior (toward camera) proxy entities protrude past the mesh
    static let proxyForwardBias: Float = 0.02

    /// Lateral offset for ankle proxies to protrude past the calf convex hull
    static let ankleProxyLateralBias: Float = 0.015

    /// Fraction from bottom of knee mesh where the kneecap actually is
    static let kneeCapHeightFraction: Float = 0.2

    /// Fraction of ankle zone height used for capsule height
    static let ankleCapsuleHeightFraction: Float = 0.5

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
        "head":       UIColor(red: 0.45, green: 0.72, blue: 1.00, alpha: 1),  // light blue
        "neck":       UIColor(red: 0.00, green: 0.75, blue: 0.70, alpha: 1),  // teal
        "chest":      UIColor(red: 1.00, green: 0.60, blue: 0.22, alpha: 1),  // orange
        "abdomen":    UIColor(red: 0.65, green: 0.85, blue: 0.25, alpha: 1),  // yellow-green
        "upper_back": UIColor(red: 0.62, green: 0.35, blue: 0.82, alpha: 1),  // purple
        "lower_back": UIColor(red: 0.35, green: 0.35, blue: 0.80, alpha: 1),  // indigo
        "shoulder":   UIColor(red: 1.00, green: 0.50, blue: 0.50, alpha: 1),  // coral
        "upper_arm":  UIColor(red: 0.30, green: 0.60, blue: 0.90, alpha: 1),  // sky blue
        "elbow":      UIColor(red: 0.50, green: 0.88, blue: 0.35, alpha: 1),  // lime
        "forearm":    UIColor(red: 0.92, green: 0.78, blue: 0.20, alpha: 1),  // gold
        "wrist_hand": UIColor(red: 1.00, green: 0.42, blue: 0.70, alpha: 1),  // pink
        "glute":      UIColor(red: 0.62, green: 0.42, blue: 0.24, alpha: 1),  // brown
        "hip":        UIColor(red: 0.82, green: 0.32, blue: 0.72, alpha: 1),  // magenta
        "thigh":      UIColor(red: 0.22, green: 0.65, blue: 0.35, alpha: 1),  // forest green
        "hamstring":  UIColor(red: 0.55, green: 0.62, blue: 0.22, alpha: 1),  // olive
        "knee":       UIColor(red: 0.00, green: 0.82, blue: 0.82, alpha: 1),  // cyan
        "calf_shin":  UIColor(red: 0.70, green: 0.52, blue: 0.90, alpha: 1),  // lavender
        "ankle_foot": UIColor(red: 1.00, green: 0.72, blue: 0.48, alpha: 1),  // peach
    ]

    // MARK: - Zone Drill-Down

    /// Alpha tint for dimmed (non-zone) region materials during drill-down.
    /// 0.02 makes them nearly invisible — a faint ghost outline only.
    static let zoneDimAlpha: CGFloat = 0.02
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

    static let sceneBackground = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
    static let loadingOverlayBackground = UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 0.95)

    // MARK: - Helpers

    /// Strip left_/right_ prefix to get the base region key for color/proxy lookup.
    static func regionBaseKey(_ zoneKey: String) -> String {
        if zoneKey.hasPrefix("left_") { return String(zoneKey.dropFirst(5)) }
        if zoneKey.hasPrefix("right_") { return String(zoneKey.dropFirst(6)) }
        return zoneKey
    }
}
