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
        "neck": 0.020,
    ]

    /// How far anterior (toward camera) proxy entities protrude past the mesh
    static let proxyForwardBias: Float = 0.02

    /// Fraction from bottom of knee mesh where the kneecap actually is
    static let kneeCapHeightFraction: Float = 0.2

    // MARK: - Lower-Leg Y-Banded Zones
    //
    // calf_shin + ankle_foot are partitioned along Z (vertical) using the same
    // pattern as the arm chain: mesh-center midpoint transitions, auto-
    // generated convex hulls disabled, dedicated Y-band box proxies own taps.
    // This avoids the calf_shin convex hull bleeding down into the ankle area.

    /// Ordered lower-leg region keys from top (calf_shin) to bottom (ankle_foot).
    static let lowerLegRegionOrder: [String] = [
        "calf_shin", "ankle_foot"
    ]

    /// Small Z overlap (in model units) between the calf_shin Y-band top and
    /// the knee mesh bottom. Prevents a hairline gap where neither collision
    /// fires. Negative values would create a gap; keep at +0.002 unless tuning.
    static let calfShinKneeOverlap: Float = 0.002

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

    static let highlightColor = UIColor(red: 0.106, green: 0.424, blue: 0.659, alpha: 1.0) // #1B6CA8 Recover Blue
    static let highlightRoughness: Float = 0.25
    static let highlightMetallic: Float = 0.15

    // MARK: - Region Material

    static let regionRoughness: Float = 0.45
    static let regionMetallic: Float = 0.05

    // MARK: - Region Color Palette

    /// Recovery palette: every region renders with the same faint-blue wash so
    /// the mannequin reads as a single neutral surface; the saturated Recover
    /// Blue selection tint provides all the per-region differentiation users need.
    /// Baked as a full-opacity color because SimpleMaterial tint alpha is
    /// transparency, not a paint wash — a low-alpha blue would make the body
    /// see-through to the scene background.
    static let regionWash = UIColor(red: 0.929, green: 0.953, blue: 0.973, alpha: 1)  // #EDF3F8 — accent ~8% over white

    /// Default color coding for each region group when the mannequin is shown
    /// in the OVERVIEW state (no zone drilled in). Every region renders with
    /// the unified blue wash so the mannequin reads as a single neutral surface.
    /// During drill-down, regions in the active zone are repainted using
    /// `zoneRegionColors` for at-a-glance differentiation; the wash returns
    /// on exit. Bilateral pairs share a color. Key = base region key
    /// (no left_/right_ prefix).
    static let regionColors: [String: UIColor] = [
        "head":       regionWash,
        "neck":       regionWash,
        "chest":      regionWash,
        "abdomen":    regionWash,
        "upper_back": regionWash,
        "lower_back": regionWash,
        "shoulder":   regionWash,
        "upper_arm":  regionWash,
        "elbow":      regionWash,
        "forearm":    regionWash,
        "wrist_hand": regionWash,
        "glute":      regionWash,
        "hip":        regionWash,
        "thigh":      regionWash,
        "hamstring":  regionWash,
        "knee":       regionWash,
        "calf_shin":  regionWash,
        "ankle_foot": regionWash,
    ]

    // MARK: - Per-Zone Palette (drill-down only)
    //
    // When the user drills into a zone, every region in that zone is repainted
    // with a distinct recovery-palette color so the sub-regions are instantly
    // distinguishable. On exit, the wash returns. Because zones are mutually
    // exclusive on screen, the same palette colors can be reused across zones
    // — only one zone is ever visible at a time.

    // Palette swatches (design tokens reused across zones)
    private static let paletteAccent     = UIColor(red: 0.106, green: 0.424, blue: 0.659, alpha: 1)  // #1B6CA8 accent
    private static let paletteAccentDark = UIColor(red: 0.082, green: 0.353, blue: 0.557, alpha: 1)  // #155A8E accentDark
    private static let paletteSuccess    = UIColor(red: 0.165, green: 0.682, blue: 0.510, alpha: 1)  // #2AAE82 success
    private static let paletteWarning    = UIColor(red: 0.941, green: 0.761, blue: 0.227, alpha: 1)  // #F0C23A warning
    private static let paletteWarmEnd    = UIColor(red: 0.941, green: 0.482, blue: 0.227, alpha: 1)  // #F07B3A warmAccent
    private static let paletteMuted      = UIColor(red: 0.490, green: 0.576, blue: 0.651, alpha: 1)  // #7D93A6 mutedText
    private static let paletteDark       = UIColor(red: 0.110, green: 0.169, blue: 0.227, alpha: 1)  // #1C2B3A primaryText

    /// Per-zone color assignment used during drill-down only. Outer key =
    /// `BodyZone.rawValue`; inner key = base region key (no left_/right_ prefix).
    /// Bilateral zones (left/right arm, left/right leg) reuse the same palette
    /// since only one side's zone is visible at a time. Within a single zone,
    /// every region gets a distinct hue for at-a-glance differentiation.
    static let zoneRegionColors: [String: [String: UIColor]] = [
        "head_neck": [
            "head":       paletteAccent,
            "neck":       paletteSuccess,
        ],
        "torso": [
            "chest":      paletteAccent,
            "abdomen":    paletteWarning,
            "upper_back": paletteSuccess,
            "lower_back": paletteDark,
        ],
        "left_arm": [
            "shoulder":   paletteAccent,
            "upper_arm":  paletteSuccess,
            "elbow":      paletteWarning,
            "forearm":    paletteMuted,
            "wrist_hand": paletteDark,
        ],
        "right_arm": [
            "shoulder":   paletteAccent,
            "upper_arm":  paletteSuccess,
            "elbow":      paletteWarning,
            "forearm":    paletteMuted,
            "wrist_hand": paletteDark,
        ],
        "left_leg": [
            "hip":        paletteAccent,
            "glute":      paletteAccentDark,
            "thigh":      paletteSuccess,
            "hamstring":  paletteWarmEnd,
            "knee":       paletteWarning,
            "calf_shin":  paletteMuted,
            "ankle_foot": paletteDark,
        ],
        "right_leg": [
            "hip":        paletteAccent,
            "glute":      paletteAccentDark,
            "thigh":      paletteSuccess,
            "hamstring":  paletteWarmEnd,
            "knee":       paletteWarning,
            "calf_shin":  paletteMuted,
            "ankle_foot": paletteDark,
        ],
    ]

    /// Resolve the per-zone palette color for a region's base key when the
    /// given zone is active. Returns `nil` if the zone has no entry for this
    /// region (callers should fall back to `regionColors`).
    static func zoneColor(zone: BodyZone, baseKey: String) -> UIColor? {
        return zoneRegionColors[zone.rawValue]?[baseKey]
    }

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

    static let sceneBackground = UIColor(red: 0.918, green: 0.941, blue: 0.961, alpha: 1.0)          // #EAF0F5 — Cloud Base pageBackground
    static let loadingOverlayBackground = UIColor(red: 0.918, green: 0.941, blue: 0.961, alpha: 0.95) // #EAF0F5 — Cloud Base pageBackground

    // MARK: - Helpers

    /// Strip left_/right_ prefix to get the base region key for color/proxy lookup.
    static func regionBaseKey(_ zoneKey: String) -> String {
        if zoneKey.hasPrefix("left_") { return String(zoneKey.dropFirst(5)) }
        if zoneKey.hasPrefix("right_") { return String(zoneKey.dropFirst(6)) }
        return zoneKey
    }
}
