import XCTest
import RealityKit
@testable import PT_Helper

/// Tests that tapping body regions on the 3D model selects the correct region.
///
/// Model LOCAL coordinate system (Z-up, from Blender export):
///   X = left/right, Y = depth (neg=anterior), Z = height
///
/// WORLD coordinate system (after USDZ -90° X rotation):
///   X = left/right, Y = height (up), Z = depth (pos=anterior)
///
/// Front camera: at positive Z, looking toward negative Z.
@MainActor
final class BodyMapCollisionTests: XCTestCase {

    // ── Proxy config (shared via BodyMapConstants) ─────────────────
    private let proxyPrefix = BodyMapConstants.proxyPrefix
    private let proxyRadii = BodyMapConstants.proxyRadii
    private let proxyForwardBias = BodyMapConstants.proxyForwardBias

    // ── Test state ───────────────────────────────────────────────────
    private var bodyEntity: Entity!
    private var regionKeys: Set<String>!
    private var arView: ARView!

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()

        let vm = BodyMapViewModel()
        regionKeys = Set(vm.regions.map(\.zoneKey))

        let entity = try await BodyModelCache.shared.loadModel()

        configureCollision(for: entity)
        createProxies(for: entity)
        createArmZoneProxies(for: entity)
        createLegZoneProxies(for: entity)

        bodyEntity = entity

        arView = ARView(frame: CGRect(x: 0, y: 0, width: 400, height: 800), cameraMode: .nonAR)
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    }

    override func tearDown() async throws {
        arView?.scene.anchors.removeAll()
        arView = nil
        bodyEntity = nil
        regionKeys = nil
        try await super.tearDown()
    }

    // MARK: - Setup Helpers (replicate BodyMap3DView logic exactly)

    private func configureCollision(for parent: Entity) {
        let zoneBoxedRegions = Set(BodyMapConstants.armRegionOrder
            + BodyMapConstants.lowerLegRegionOrder)
        for child in parent.children {
            if regionKeys.contains(child.name),
               child.components[ModelComponent.self] != nil {
                child.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                let baseKey = BodyMapConstants.regionBaseKey(child.name)
                if !zoneBoxedRegions.contains(baseKey) {
                    child.generateCollisionShapes(recursive: true)
                }
            }
            configureCollision(for: child)
        }
    }

    private func createArmZoneProxies(for entity: Entity) {
        for side in ["left", "right"] {
            createArmZoneProxies(for: entity, side: side)
        }
    }

    private func createArmZoneProxies(for entity: Entity, side: String) {
        let order = BodyMapConstants.armRegionOrder
        let zoneKeys = order.map { "\(side)_\($0)" }
        guard zoneKeys.allSatisfy({ regionKeys.contains($0) }) else { return }
        let ents = zoneKeys.compactMap { entity.findEntity(named: $0) }
        guard ents.count == order.count else { return }
        let bounds = ents.map { $0.visualBounds(relativeTo: entity) }

        var transitions: [Float] = []
        for i in 0..<(order.count - 1) {
            transitions.append((bounds[i].center.z + bounds[i + 1].center.z) / 2)
        }

        for (i, zoneKey) in zoneKeys.enumerated() {
            let topZ = (i == 0) ? bounds[i].max.z : transitions[i - 1]
            let botZ = (i == order.count - 1) ? bounds[i].min.z : transitions[i]
            let zoneExtentZ = max(0.005, topZ - botZ)
            let zoneCenterZ = (topZ + botZ) / 2

            let yFront = bounds[i].min.y - BodyMapConstants.armZoneForwardBias
            let yBack = bounds[i].max.y
            let zoneCenterY = (yFront + yBack) / 2
            let zoneExtentY = max(0.005, yBack - yFront)

            let zoneCenterX = bounds[i].center.x
            let zoneExtentX = max(0.005, bounds[i].extents.x)

            let proxy = Entity()
            proxy.name = proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(zoneCenterX, zoneCenterY, zoneCenterZ)
            let shape = ShapeResource.generateBox(size: SIMD3<Float>(zoneExtentX, zoneExtentY, zoneExtentZ))
            proxy.components.set(CollisionComponent(shapes: [shape]))
            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.addChild(proxy)
        }
    }

    private func createLegZoneProxies(for entity: Entity) {
        for side in ["left", "right"] {
            createLegZoneProxies(for: entity, side: side)
        }
    }

    private func createLegZoneProxies(for entity: Entity, side: String) {
        let order = BodyMapConstants.lowerLegRegionOrder
        let zoneKeys = order.map { "\(side)_\($0)" }
        guard zoneKeys.allSatisfy({ regionKeys.contains($0) }) else { return }
        let ents = zoneKeys.compactMap { entity.findEntity(named: $0) }
        guard ents.count == order.count else { return }
        let bounds = ents.map { $0.visualBounds(relativeTo: entity) }

        var transitions: [Float] = []
        for i in 0..<(order.count - 1) {
            transitions.append((bounds[i].center.z + bounds[i + 1].center.z) / 2)
        }

        for (i, zoneKey) in zoneKeys.enumerated() {
            let topZ = (i == 0) ? bounds[i].max.z : transitions[i - 1]
            let botZ = (i == order.count - 1) ? bounds[i].min.z : transitions[i]
            let zoneExtentZ = max(0.005, topZ - botZ)
            let zoneCenterZ = (topZ + botZ) / 2

            let yFront = bounds[i].min.y - BodyMapConstants.armZoneForwardBias
            let yBack = bounds[i].max.y
            let zoneCenterY = (yFront + yBack) / 2
            let zoneExtentY = max(0.005, yBack - yFront)

            let zoneCenterX = bounds[i].center.x
            let zoneExtentX = max(0.005, bounds[i].extents.x)

            let proxy = Entity()
            proxy.name = proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(zoneCenterX, zoneCenterY, zoneCenterZ)
            let shape = ShapeResource.generateBox(size: SIMD3<Float>(zoneExtentX, zoneExtentY, zoneExtentZ))
            proxy.components.set(CollisionComponent(shapes: [shape]))
            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.addChild(proxy)
        }
    }

    private func createProxies(for entity: Entity) {
        for zoneKey in regionKeys {
            let baseKey = regionBaseKey(zoneKey)

            guard let radius = proxyRadii[baseKey],
                  let regionEntity = entity.findEntity(named: zoneKey) else { continue }

            let bounds = regionEntity.visualBounds(relativeTo: entity)
            let center = bounds.center

            var proxyZ = center.z
            if baseKey == "knee" {
                proxyZ = bounds.min.z + bounds.extents.z * BodyMapConstants.kneeCapHeightFraction
            } else if baseKey == "head" {
                proxyZ = bounds.max.z - bounds.extents.z * 0.2
            }

            let proxyX = center.x

            let forwardBias: Float
            switch baseKey {
            case "head": forwardBias = 0.04
            default: forwardBias = proxyForwardBias
            }

            let proxy = Entity()
            proxy.name = proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(
                proxyX,
                bounds.min.y - forwardBias,
                proxyZ
            )

            let shape = ShapeResource.generateSphere(radius: radius)
            proxy.components.set(CollisionComponent(shapes: [shape]))

            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))

            entity.addChild(proxy)
        }
    }

    private func regionBaseKey(_ zoneKey: String) -> String {
        BodyMapConstants.regionBaseKey(zoneKey)
    }

    // MARK: - Raycast Helpers (world space: X=left/right, Y=height, Z=depth)

    /// Cast a ray from the front (positive Z) through (worldX, worldY).
    /// Returns the NEAREST hit so overlapping collisions resolve deterministically.
    private func frontRaycast(x: Float, y: Float) -> String? {
        let origin = SIMD3<Float>(x, y, 1.0)
        let direction = SIMD3<Float>(0, 0, -1)
        let results = arView.scene.raycast(
            origin: origin, direction: direction,
            length: 3.0, query: .nearest, mask: .all, relativeTo: nil
        )
        return results.first?.entity.name
    }

    /// Cast a ray from the front and return all hit entity names, sorted
    /// nearest-to-farthest by distance. Used to simulate the app's
    /// drill-down mode, which ignores hits outside the active zone.
    private func frontRaycastAll(x: Float, y: Float) -> [String] {
        let origin = SIMD3<Float>(x, y, 1.0)
        let direction = SIMD3<Float>(0, 0, -1)
        let results = arView.scene.raycast(
            origin: origin, direction: direction,
            length: 3.0, query: .all, mask: .all, relativeTo: nil
        )
        return results.sorted(by: { $0.distance < $1.distance }).map { $0.entity.name }
    }

    /// Simulates the app's arm-zone drill-down: pick the closest raycast hit
    /// that belongs to the given arm side. Off-zone hits (chest, torso) get
    /// filtered out just like `handleEntityTap` does in production.
    private func firstArmZoneHit(x: Float, y: Float, isLeft: Bool) -> String? {
        let armKeys: Set<String> = isLeft
            ? ["left_shoulder", "left_upper_arm", "left_elbow", "left_forearm", "left_wrist_hand"]
            : ["right_shoulder", "right_upper_arm", "right_elbow", "right_forearm", "right_wrist_hand"]
        for rawName in frontRaycastAll(x: x, y: y) {
            if let resolved = resolveHit(rawName), armKeys.contains(resolved) {
                return resolved
            }
        }
        return nil
    }

    /// Cast a ray from the back (negative Z) through (worldX, worldY).
    private func backRaycast(x: Float, y: Float) -> String? {
        let origin = SIMD3<Float>(x, y, -1.0)
        let direction = SIMD3<Float>(0, 0, 1)
        let results = arView.scene.raycast(
            origin: origin, direction: direction,
            length: 3.0, query: .all, mask: .all, relativeTo: nil
        )
        return results.first?.entity.name
    }

    /// Cast a ray from the left side (negative X) looking inward.
    /// World space: X=left/right, Y=height, Z=depth.
    private func leftSideRaycast(y: Float, z: Float) -> String? {
        let origin = SIMD3<Float>(-1.0, y, z)
        let direction = SIMD3<Float>(1, 0, 0)
        let results = arView.scene.raycast(
            origin: origin, direction: direction,
            length: 3.0, query: .all, mask: .all, relativeTo: nil
        )
        return results.first?.entity.name
    }

    /// Cast a ray from the right side (positive X) looking inward.
    private func rightSideRaycast(y: Float, z: Float) -> String? {
        let origin = SIMD3<Float>(1.0, y, z)
        let direction = SIMD3<Float>(-1, 0, 0)
        let results = arView.scene.raycast(
            origin: origin, direction: direction,
            length: 3.0, query: .all, mask: .all, relativeTo: nil
        )
        return results.first?.entity.name
    }

    /// Strip proxy prefix to get the real region zone key.
    private func resolveHit(_ name: String?) -> String? {
        guard let name = name else { return nil }
        if name.hasPrefix(proxyPrefix) {
            return String(name.dropFirst(proxyPrefix.count))
        }
        return name
    }

    // MARK: - 1. Entity Existence Tests

    func testAllRegionEntitiesExist() {
        for key in regionKeys {
            XCTAssertNotNil(
                bodyEntity.findEntity(named: key),
                "Region entity '\(key)' should exist in the model"
            )
        }
    }

    func testProxyEntitiesExistForSmallRegions() {
        for key in regionKeys {
            let baseKey = regionBaseKey(key)
            if proxyRadii[baseKey] != nil {
                XCTAssertNotNil(
                    bodyEntity.findEntity(named: proxyPrefix + key),
                    "Proxy entity for '\(key)' should exist"
                )
            }
        }
    }

    func testNoProxiesForTorsoAndLegRegions() {
        // Torso and upper-leg large regions rely on mesh collision — no proxies.
        // (Arm + lower-leg regions DO have Y-band box proxies via
        // createArmZoneProxies / createLegZoneProxies.)
        let largeBaseKeys: Set<String> = [
            "chest", "abdomen", "upper_back", "lower_back",
            "glute", "hip", "thigh", "hamstring"
        ]
        for key in regionKeys {
            let baseKey = regionBaseKey(key)
            if largeBaseKeys.contains(baseKey) {
                XCTAssertNil(
                    bodyEntity.findEntity(named: proxyPrefix + key),
                    "Large region '\(key)' should NOT have a proxy"
                )
            }
        }
    }

    func testArmRegionsHaveZoneProxies() {
        for side in ["left", "right"] {
            for baseKey in BodyMapConstants.armRegionOrder {
                let key = "\(side)_\(baseKey)"
                XCTAssertNotNil(
                    bodyEntity.findEntity(named: proxyPrefix + key),
                    "Arm region '\(key)' should have a Y-band zone proxy"
                )
            }
        }
    }

    /// End-to-end boundary check: for each pair of adjacent arm regions,
    /// cast a ray just above and just below their *center* midpoint and
    /// confirm the two rays resolve to the upper region and lower region
    /// respectively. Uses center midpoints (not min/max) because the arm
    /// meshes overlap each other significantly along Z.
    func testAdjacentArmZonesMeetAtSingleBoundary() {
        for side in ["left", "right"] {
            let order = BodyMapConstants.armRegionOrder
            let zoneKeys = order.map { "\(side)_\($0)" }
            let ents = zoneKeys.compactMap { bodyEntity.findEntity(named: $0) }
            guard ents.count == order.count else {
                XCTFail("Missing arm entities for side=\(side)"); return
            }
            let worldBounds = ents.map { $0.visualBounds(relativeTo: nil) }
            let isLeft = (side == "left")
            for i in 0..<(order.count - 1) {
                let upperBounds = worldBounds[i]
                let lowerBounds = worldBounds[i + 1]
                // World Y = height; use center midpoint, not min/max.
                let midY = (upperBounds.center.y + lowerBounds.center.y) / 2
                // Tap at each region's own X center so the ray is squarely inside
                // that region's zone box laterally.
                let hitAbove = firstArmZoneHit(x: upperBounds.center.x, y: midY + 0.003, isLeft: isLeft)
                let hitBelow = firstArmZoneHit(x: lowerBounds.center.x, y: midY - 0.003, isLeft: isLeft)
                XCTAssertEqual(hitAbove, zoneKeys[i],
                    "Tap just above \(order[i])/\(order[i+1]) midpoint should select \(zoneKeys[i]), got: \(hitAbove ?? "nil")"
                )
                XCTAssertEqual(hitBelow, zoneKeys[i + 1],
                    "Tap just below \(order[i])/\(order[i+1]) midpoint should select \(zoneKeys[i+1]), got: \(hitBelow ?? "nil")"
                )
            }
        }
    }

    // MARK: - 2. Knee Proxy Geometric Tests (local space, Z=height)

    func testKneeProxyPositionedAtKneecapHeight() {
        guard let kneeEntity = bodyEntity.findEntity(named: "left_knee"),
              let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_knee") else {
            XCTFail("Knee entity or proxy not found"); return
        }

        let bounds = kneeEntity.visualBounds(relativeTo: bodyEntity)
        let expectedZ = bounds.min.z + bounds.extents.z * BodyMapConstants.kneeCapHeightFraction
        let proxyZ = proxy.position(relativeTo: bodyEntity).z

        let tolerance = bounds.extents.z * 0.15
        XCTAssertTrue(
            abs(proxyZ - expectedZ) < tolerance,
            "Knee proxy height (\(proxyZ)) should be near kneecap (\(expectedZ)), not center (\(bounds.center.z))"
        )
    }

    func testKneeProxyBetweenThighAndCalf() {
        guard let thigh = bodyEntity.findEntity(named: "left_thigh"),
              let calf = bodyEntity.findEntity(named: "left_calf_shin"),
              let kneeProxy = bodyEntity.findEntity(named: proxyPrefix + "left_knee") else {
            XCTFail("Entities not found"); return
        }

        let thighBounds = thigh.visualBounds(relativeTo: bodyEntity)
        let calfBounds = calf.visualBounds(relativeTo: bodyEntity)
        let proxyZ = kneeProxy.position(relativeTo: bodyEntity).z

        XCTAssertTrue(
            proxyZ < thighBounds.center.z,
            "Knee proxy height (\(proxyZ)) should be below thigh center (\(thighBounds.center.z))"
        )
        XCTAssertTrue(
            proxyZ > calfBounds.center.z,
            "Knee proxy height (\(proxyZ)) should be above calf center (\(calfBounds.center.z))"
        )
    }

    func testKneeProxyProtrudesAnterior() {
        guard let knee = bodyEntity.findEntity(named: "left_knee"),
              let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_knee") else {
            XCTFail("Entities not found"); return
        }

        let bounds = knee.visualBounds(relativeTo: bodyEntity)
        let proxyPos = proxy.position(relativeTo: bodyEntity)
        // In local space: anterior = negative Y, proxy front = position.y - radius
        let proxyFrontY = proxyPos.y - proxyRadii["knee"]!

        XCTAssertTrue(
            proxyFrontY < bounds.min.y,
            "Knee proxy front (y=\(proxyFrontY)) should protrude past mesh anterior (y=\(bounds.min.y))"
        )
    }

    // MARK: - 3. All Proxy Forward Protrusion Tests

    func testAllProxiesProtrudeAnterior() {
        for key in regionKeys {
            let baseKey = regionBaseKey(key)
            guard let radius = proxyRadii[baseKey],
                  let regionEntity = bodyEntity.findEntity(named: key),
                  let proxy = bodyEntity.findEntity(named: proxyPrefix + key) else { continue }

            let bounds = regionEntity.visualBounds(relativeTo: bodyEntity)
            let proxyPos = proxy.position(relativeTo: bodyEntity)
            let proxyFrontY = proxyPos.y - radius

            XCTAssertTrue(
                proxyFrontY < bounds.min.y,
                "Proxy for '\(key)' front (y=\(proxyFrontY)) should protrude past mesh (y=\(bounds.min.y))"
            )
        }
    }

    // MARK: - 4. Raycast: Knee Boundary Tests (world space)

    func testTapKneeAreaSelectsKnee() {
        guard let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_knee") else {
            XCTFail("Left knee proxy not found"); return
        }
        let pos = proxy.position(relativeTo: nil) // world space
        let hit = resolveHit(frontRaycast(x: pos.x, y: pos.y))
        XCTAssertEqual(hit, "left_knee", "Tapping knee area should select left_knee, got: \(hit ?? "nil")")
    }

    func testTapAboveKneeSelectsThigh() {
        guard let thigh = bodyEntity.findEntity(named: "left_thigh") else {
            XCTFail("Thigh not found"); return
        }
        let bounds = thigh.visualBounds(relativeTo: nil)
        let hit = resolveHit(frontRaycast(x: bounds.center.x, y: bounds.center.y))
        XCTAssertEqual(hit, "left_thigh", "Tapping thigh center should select left_thigh, got: \(hit ?? "nil")")
    }

    func testTapUpperThighSelectsThigh() {
        guard let thigh = bodyEntity.findEntity(named: "left_thigh") else {
            XCTFail("Thigh not found"); return
        }
        let bounds = thigh.visualBounds(relativeTo: nil)
        let upperY = bounds.center.y + bounds.extents.y * 0.05
        let hit = resolveHit(frontRaycast(x: bounds.center.x, y: upperY))
        XCTAssertEqual(hit, "left_thigh", "Tapping upper thigh should select left_thigh, got: \(hit ?? "nil")")
    }

    func testTapBelowKneeSelectsCalfShin() {
        guard let calf = bodyEntity.findEntity(named: "left_calf_shin") else {
            XCTFail("Calf not found"); return
        }
        let bounds = calf.visualBounds(relativeTo: nil)
        let hit = resolveHit(frontRaycast(x: bounds.center.x, y: bounds.center.y))
        XCTAssertEqual(hit, "left_calf_shin", "Tapping calf center should select left_calf_shin, got: \(hit ?? "nil")")
    }

    // MARK: - 4a. Arm Zone Boundary Tests (world space)

    /// Regression test for the reported bug. A tap anywhere inside the
    /// shoulder's Y band — including the lower portion abutting upper_arm —
    /// must resolve to shoulder, never upper_arm.
    func testTapJustAboveShoulderUpperArmBoundarySelectsShoulder() {
        guard let shoulder = bodyEntity.findEntity(named: "left_shoulder"),
              let upperArm = bodyEntity.findEntity(named: "left_upper_arm") else {
            XCTFail("Arm entities not found"); return
        }
        let sBounds = shoulder.visualBounds(relativeTo: nil)
        let uBounds = upperArm.visualBounds(relativeTo: nil)
        let boundaryY = (sBounds.center.y + uBounds.center.y) / 2
        let tapY = boundaryY + 0.002
        let hit = firstArmZoneHit(x: sBounds.center.x, y: tapY, isLeft: true)
        XCTAssertEqual(hit, "left_shoulder", "Tap just above shoulder/upper_arm boundary should select left_shoulder, got: \(hit ?? "nil")")
    }

    /// A tap just below the same boundary must resolve to upper_arm, never
    /// shoulder. Together with the previous test this confirms the line where
    /// shoulder and upper_arm meet.
    func testTapJustBelowShoulderUpperArmBoundarySelectsUpperArm() {
        guard let shoulder = bodyEntity.findEntity(named: "left_shoulder"),
              let upperArm = bodyEntity.findEntity(named: "left_upper_arm") else {
            XCTFail("Arm entities not found"); return
        }
        let sBounds = shoulder.visualBounds(relativeTo: nil)
        let uBounds = upperArm.visualBounds(relativeTo: nil)
        let boundaryY = (sBounds.center.y + uBounds.center.y) / 2
        let tapY = boundaryY - 0.002
        let hit = firstArmZoneHit(x: uBounds.center.x, y: tapY, isLeft: true)
        XCTAssertEqual(hit, "left_upper_arm", "Tap just below shoulder/upper_arm boundary should select left_upper_arm, got: \(hit ?? "nil")")
    }

    func testTapMidUpperArmSelectsUpperArm() {
        guard let upperArm = bodyEntity.findEntity(named: "left_upper_arm") else {
            XCTFail("Upper arm not found"); return
        }
        let bounds = upperArm.visualBounds(relativeTo: nil)
        let hit = firstArmZoneHit(x: bounds.center.x, y: bounds.center.y, isLeft: true)
        XCTAssertEqual(hit, "left_upper_arm", "Arm-zone tap at upper_arm center should select left_upper_arm, got: \(hit ?? "nil")")
    }

    // MARK: - 4c. Lower-Leg Y-Band Zone Tests (local space, Z=height)

    func testAnkleFootProxyBelowCalfShinCenter() {
        guard let calf = bodyEntity.findEntity(named: "left_calf_shin"),
              let ankleProxy = bodyEntity.findEntity(named: proxyPrefix + "left_ankle_foot") else {
            XCTFail("Entities not found"); return
        }

        let calfBounds = calf.visualBounds(relativeTo: bodyEntity)
        let proxyZ = ankleProxy.position(relativeTo: bodyEntity).z

        XCTAssertTrue(
            proxyZ < calfBounds.center.z,
            "Ankle proxy center (\(proxyZ)) should be below calf center (\(calfBounds.center.z))"
        )
    }

    func testLowerLegRegionsHaveZoneProxies() {
        for side in ["left", "right"] {
            for baseKey in BodyMapConstants.lowerLegRegionOrder {
                let key = "\(side)_\(baseKey)"
                XCTAssertNotNil(
                    bodyEntity.findEntity(named: proxyPrefix + key),
                    "Lower-leg region '\(key)' should have a Y-band zone proxy"
                )
            }
        }
    }

    /// Verify the calf_shin / ankle_foot transition is a single shared
    /// boundary at the mesh-center midpoint (mirrors testAdjacentArmZonesMeetAtSingleBoundary).
    func testLegZonesMeetAtSingleBoundary() {
        for side in ["left", "right"] {
            let order = BodyMapConstants.lowerLegRegionOrder
            let zoneKeys = order.map { "\(side)_\($0)" }
            let ents = zoneKeys.compactMap { bodyEntity.findEntity(named: $0) }
            guard ents.count == order.count else {
                XCTFail("Missing lower-leg entities for side=\(side)"); return
            }
            let worldBounds = ents.map { $0.visualBounds(relativeTo: nil) }
            for i in 0..<(order.count - 1) {
                let upperBounds = worldBounds[i]
                let lowerBounds = worldBounds[i + 1]
                let midY = (upperBounds.center.y + lowerBounds.center.y) / 2
                let hitAbove = resolveHit(frontRaycast(x: upperBounds.center.x, y: midY + 0.003))
                let hitBelow = resolveHit(frontRaycast(x: lowerBounds.center.x, y: midY - 0.003))
                XCTAssertEqual(
                    hitAbove, zoneKeys[i],
                    "Tap just above midpoint of \(zoneKeys[i])/\(zoneKeys[i+1]) on side=\(side) should select \(zoneKeys[i]), got \(hitAbove ?? "nil")"
                )
                XCTAssertEqual(
                    hitBelow, zoneKeys[i + 1],
                    "Tap just below midpoint of \(zoneKeys[i])/\(zoneKeys[i+1]) on side=\(side) should select \(zoneKeys[i+1]), got \(hitBelow ?? "nil")"
                )
            }
        }
    }

    // MARK: - 4d. Raycast: Side-View Ankle/Foot Full Zone Tests (world space)

    /// Helper: side raycast at a given fraction of the ankle/foot zone height.
    /// 0.0 = bottom of foot, 1.0 = top of ankle mesh.
    private func assertSideTapAnkleZone(
        heightFraction: Float,
        zoneKey: String = "left_ankle_foot",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let ankle = bodyEntity.findEntity(named: zoneKey),
              let proxy = bodyEntity.findEntity(named: proxyPrefix + zoneKey) else {
            XCTFail("Entities not found", file: file, line: line); return
        }
        let bounds = ankle.visualBounds(relativeTo: nil) // world space
        let proxyWorldPos = proxy.position(relativeTo: nil)
        let targetY = bounds.min.y + bounds.extents.y * heightFraction
        let isLeft = zoneKey.hasPrefix("left_")
        let hit = resolveHit(
            isLeft
                ? leftSideRaycast(y: targetY, z: proxyWorldPos.z)
                : rightSideRaycast(y: targetY, z: proxyWorldPos.z)
        )
        XCTAssertEqual(
            hit, zoneKey,
            "Side tap at \(zoneKey) height \(Int(heightFraction * 100))% should select \(zoneKey), got: \(hit ?? "nil")",
            file: file, line: line
        )
    }

    func testSideTapFootBottomSelectsAnkleFoot() {
        assertSideTapAnkleZone(heightFraction: 0.2, zoneKey: "left_ankle_foot")
    }

    func testSideTapMidAnkleFromSideSelectsAnkleFoot() {
        assertSideTapAnkleZone(heightFraction: 0.5, zoneKey: "left_ankle_foot")
    }

    func testSideTapUpperAnkleFromSideSelectsAnkleFoot() {
        assertSideTapAnkleZone(heightFraction: 0.8, zoneKey: "left_ankle_foot")
    }

    func testSideTapRightFootBottomSelectsAnkleFoot() {
        assertSideTapAnkleZone(heightFraction: 0.2, zoneKey: "right_ankle_foot")
    }

    func testSideTapRightMidAnkleSelectsAnkleFoot() {
        assertSideTapAnkleZone(heightFraction: 0.5, zoneKey: "right_ankle_foot")
    }

    func testSideTapRightUpperAnkleSelectsAnkleFoot() {
        assertSideTapAnkleZone(heightFraction: 0.8, zoneKey: "right_ankle_foot")
    }

    func testFrontTapAnkleAreaSelectsAnkleFoot() {
        guard let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_ankle_foot") else {
            XCTFail("Left ankle/foot proxy not found"); return
        }
        let pos = proxy.position(relativeTo: nil)
        let hit = resolveHit(frontRaycast(x: pos.x, y: pos.y))
        XCTAssertEqual(hit, "left_ankle_foot", "Front tap at ankle proxy should select left_ankle_foot, got: \(hit ?? "nil")")
    }

    // MARK: - 5. Raycast: Front-Visible Regions (Left Side)

    func testTapHeadSelectsHead() { assertFrontTapHits("head") }
    func testTapNeckSelectsNeck() { assertProxyFrontTapHits("neck") }
    func testTapChestSelectsChest() { assertFrontTapHits("chest", yFraction: 0.15) }
    func testTapAbdomenSelectsAbdomen() { assertFrontTapHits("abdomen") }
    func testTapLeftShoulderSelectsShoulder() { assertProxyFrontTapHits("left_shoulder") }
    func testTapLeftUpperArmSelectsUpperArm() { assertProxyFrontTapHits("left_upper_arm") }
    func testTapLeftElbowSelectsElbow() { assertProxyFrontTapHits("left_elbow") }
    func testTapLeftForearmSelectsForearm() { assertProxyFrontTapHits("left_forearm") }
    func testTapLeftWristHandSelectsWristHand() { assertProxyFrontTapHits("left_wrist_hand") }
    func testTapLeftHipSelectsHip() { assertFrontTapHits("left_hip", yFraction: -0.3) }
    func testTapLeftThighSelectsThigh() { assertFrontTapHits("left_thigh") }
    func testTapLeftKneeSelectsKnee() { assertProxyFrontTapHits("left_knee") }
    func testTapLeftCalfShinSelectsCalfShin() { assertFrontTapHits("left_calf_shin") }
    func testTapLeftAnkleFootSelectsAnkleFoot() { assertProxyFrontTapHits("left_ankle_foot") }

    // MARK: - 6. Raycast: Front-Visible Regions (Right Side)

    func testTapRightShoulderSelectsShoulder() { assertProxyFrontTapHits("right_shoulder") }
    func testTapRightUpperArmSelectsUpperArm() { assertProxyFrontTapHits("right_upper_arm") }
    func testTapRightElbowSelectsElbow() { assertProxyFrontTapHits("right_elbow") }
    func testTapRightForearmSelectsForearm() { assertProxyFrontTapHits("right_forearm") }
    func testTapRightWristHandSelectsWristHand() { assertProxyFrontTapHits("right_wrist_hand") }
    func testTapRightHipSelectsHip() { assertFrontTapHits("right_hip", yFraction: -0.3) }
    func testTapRightThighSelectsThigh() { assertFrontTapHits("right_thigh") }
    func testTapRightKneeSelectsKnee() { assertProxyFrontTapHits("right_knee") }
    func testTapRightCalfShinSelectsCalfShin() { assertFrontTapHits("right_calf_shin") }
    func testTapRightAnkleFootSelectsAnkleFoot() { assertProxyFrontTapHits("right_ankle_foot") }

    // MARK: - 7. Raycast: Back-Visible Regions

    func testTapUpperBackSelectsUpperBack() { assertBackTapHits("upper_back") }
    func testTapLowerBackSelectsLowerBack() { assertBackTapHits("lower_back", yFraction: -0.3) }
    func testTapLeftGluteSelectsGlute() { assertBackTapHits("left_glute") }
    func testTapRightGluteSelectsGlute() { assertBackTapHits("right_glute") }
    func testTapLeftHamstringSelectsHamstring() { assertBackTapHits("left_hamstring") }
    func testTapRightHamstringSelectsHamstring() { assertBackTapHits("right_hamstring") }

    // MARK: - Assertion Helpers

    /// For non-proxy regions: cast ray at entity's visual bounds from the front.
    /// Uses WORLD coordinates (Y=height, Z=depth).
    /// xFraction/yFraction offset the tap within the entity's extents to avoid
    /// overlapping convex hull collision from neighboring regions.
    private func assertFrontTapHits(
        _ zoneKey: String,
        xFraction: Float = 0,
        yFraction: Float = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let entity = bodyEntity.findEntity(named: zoneKey) else {
            XCTFail("Entity '\(zoneKey)' not found", file: file, line: line); return
        }
        let bounds = entity.visualBounds(relativeTo: nil) // world space
        let x = bounds.center.x + bounds.extents.x * xFraction
        let y = bounds.center.y + bounds.extents.y * yFraction
        let hit = resolveHit(frontRaycast(x: x, y: y))
        XCTAssertEqual(
            hit, zoneKey,
            "Front tap at \(zoneKey) (xF=\(xFraction), yF=\(yFraction)) should select \(zoneKey), got: \(hit ?? "nil")",
            file: file, line: line
        )
    }

    /// For proxy regions: cast ray at the proxy sphere position from the front.
    private func assertProxyFrontTapHits(_ zoneKey: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let proxy = bodyEntity.findEntity(named: proxyPrefix + zoneKey) else {
            XCTFail("Proxy for '\(zoneKey)' not found", file: file, line: line); return
        }
        let pos = proxy.position(relativeTo: nil) // world space
        let hit = resolveHit(frontRaycast(x: pos.x, y: pos.y))
        XCTAssertEqual(
            hit, zoneKey,
            "Front tap at \(zoneKey) proxy should select \(zoneKey), got: \(hit ?? "nil")",
            file: file, line: line
        )
    }

    /// For back-only regions: cast ray at entity's visual bounds from the back.
    /// yFraction offsets the tap within the entity's extents to avoid
    /// overlapping convex hull collision from neighboring regions.
    private func assertBackTapHits(
        _ zoneKey: String,
        xFraction: Float = 0,
        yFraction: Float = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let entity = bodyEntity.findEntity(named: zoneKey) else {
            XCTFail("Entity '\(zoneKey)' not found", file: file, line: line); return
        }
        let bounds = entity.visualBounds(relativeTo: nil) // world space
        let x = bounds.center.x + bounds.extents.x * xFraction
        let y = bounds.center.y + bounds.extents.y * yFraction
        let hit = resolveHit(backRaycast(x: x, y: y))
        XCTAssertEqual(
            hit, zoneKey,
            "Back tap at \(zoneKey) (xF=\(xFraction), yF=\(yFraction)) should select \(zoneKey), got: \(hit ?? "nil")",
            file: file, line: line
        )
    }
}
