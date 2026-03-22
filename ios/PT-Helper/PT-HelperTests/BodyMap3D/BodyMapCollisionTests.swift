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
    private let ankleProxyLateralBias = BodyMapConstants.ankleProxyLateralBias

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
        for child in parent.children {
            if regionKeys.contains(child.name),
               child.components[ModelComponent.self] != nil {
                child.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                child.generateCollisionShapes(recursive: true)
            }
            configureCollision(for: child)
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
            } else if baseKey == "ankle_foot" {
                proxyZ = center.z
            }

            // Push ankle proxy laterally outward so it protrudes past
            // the calf convex hull when viewed from the side
            var proxyX = center.x
            if baseKey == "ankle_foot" {
                if zoneKey.hasPrefix("left_") {
                    proxyX = center.x - ankleProxyLateralBias
                } else if zoneKey.hasPrefix("right_") {
                    proxyX = center.x + ankleProxyLateralBias
                }
            }

            let proxy = Entity()
            proxy.name = proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(
                proxyX,
                bounds.min.y - proxyForwardBias,
                proxyZ
            )

            if baseKey == "ankle_foot" {
                let capsuleHeight = bounds.extents.z * BodyMapConstants.ankleCapsuleHeightFraction
                let shape = ShapeResource.generateCapsule(height: capsuleHeight, radius: radius)
                proxy.components.set(CollisionComponent(shapes: [shape]))
                // Rotate capsule from Y-aligned to Z-aligned (vertical in local space)
                proxy.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            } else {
                let shape = ShapeResource.generateSphere(radius: radius)
                proxy.components.set(CollisionComponent(shapes: [shape]))
            }

            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))

            entity.addChild(proxy)
        }
    }

    private func regionBaseKey(_ zoneKey: String) -> String {
        BodyMapConstants.regionBaseKey(zoneKey)
    }

    // MARK: - Raycast Helpers (world space: X=left/right, Y=height, Z=depth)

    /// Cast a ray from the front (positive Z) through (worldX, worldY).
    private func frontRaycast(x: Float, y: Float) -> String? {
        let origin = SIMD3<Float>(x, y, 1.0)
        let direction = SIMD3<Float>(0, 0, -1)
        let results = arView.scene.raycast(
            origin: origin, direction: direction,
            length: 3.0, query: .all, mask: .all, relativeTo: nil
        )
        return results.first?.entity.name
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

    func testNoProxiesForLargeRegions() {
        let largeBaseKeys: Set<String> = [
            "head", "chest", "abdomen", "upper_back", "lower_back",
            "upper_arm", "forearm", "glute", "hip",
            "thigh", "hamstring", "calf_shin"
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

    // MARK: - 4b. Ankle/Foot Capsule Geometric Tests (local space, Z=height)

    func testAnkleFootProxyCenteredOnZone() {
        guard let ankleEntity = bodyEntity.findEntity(named: "left_ankle_foot"),
              let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_ankle_foot") else {
            XCTFail("Ankle entity or proxy not found"); return
        }

        let bounds = ankleEntity.visualBounds(relativeTo: bodyEntity)
        let proxyZ = proxy.position(relativeTo: bodyEntity).z

        let tolerance = bounds.extents.z * 0.15
        XCTAssertTrue(
            abs(proxyZ - bounds.center.z) < tolerance,
            "Ankle capsule center (\(proxyZ)) should be near mesh center (\(bounds.center.z))"
        )
    }

    func testAnkleFootCapsuleCoversFootToAnkle() {
        guard let ankleEntity = bodyEntity.findEntity(named: "left_ankle_foot"),
              let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_ankle_foot") else {
            XCTFail("Ankle entity or proxy not found"); return
        }

        let bounds = ankleEntity.visualBounds(relativeTo: bodyEntity)
        let proxyZ = proxy.position(relativeTo: bodyEntity).z
        let radius = proxyRadii["ankle_foot"]!
        let capsuleHeight = bounds.extents.z * BodyMapConstants.ankleCapsuleHeightFraction

        // Capsule total coverage: center ± (capsuleHeight/2 + radius)
        let capsuleTop = proxyZ + capsuleHeight / 2 + radius
        let capsuleBottom = proxyZ - capsuleHeight / 2 - radius

        // Should cover at least 80% up from bottom (upper ankle area)
        let upperAnkle = bounds.min.z + bounds.extents.z * 0.8
        XCTAssertTrue(
            capsuleTop >= upperAnkle,
            "Capsule top (\(capsuleTop)) should reach upper ankle (\(upperAnkle))"
        )

        // Should cover down to at least 20% from bottom (foot area)
        let footLevel = bounds.min.z + bounds.extents.z * 0.2
        XCTAssertTrue(
            capsuleBottom <= footLevel,
            "Capsule bottom (\(capsuleBottom)) should reach foot level (\(footLevel))"
        )
    }

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

    func testAnkleFootProxyProtrudesLaterally() {
        guard let ankleEntity = bodyEntity.findEntity(named: "left_ankle_foot"),
              let proxy = bodyEntity.findEntity(named: proxyPrefix + "left_ankle_foot") else {
            XCTFail("Ankle entity or proxy not found"); return
        }

        let bounds = ankleEntity.visualBounds(relativeTo: bodyEntity)
        let proxyPos = proxy.position(relativeTo: bodyEntity)
        let radius = proxyRadii["ankle_foot"]!

        // Left ankle: proxy outer edge should extend past mesh's outer edge (min.x)
        let proxyOuterX = proxyPos.x - radius
        XCTAssertTrue(
            proxyOuterX < bounds.min.x,
            "Ankle proxy outer edge (x=\(proxyOuterX)) should protrude past mesh lateral edge (x=\(bounds.min.x))"
        )
    }

    // MARK: - 4c. Raycast: Side-View Ankle/Foot Full Zone Tests (world space)

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
    func testTapLeftUpperArmSelectsUpperArm() { assertFrontTapHits("left_upper_arm") }
    func testTapLeftElbowSelectsElbow() { assertProxyFrontTapHits("left_elbow") }
    func testTapLeftForearmSelectsForearm() { assertFrontTapHits("left_forearm") }
    func testTapLeftWristHandSelectsWristHand() { assertProxyFrontTapHits("left_wrist_hand") }
    func testTapLeftHipSelectsHip() { assertFrontTapHits("left_hip", yFraction: -0.3) }
    func testTapLeftThighSelectsThigh() { assertFrontTapHits("left_thigh") }
    func testTapLeftKneeSelectsKnee() { assertProxyFrontTapHits("left_knee") }
    func testTapLeftCalfShinSelectsCalfShin() { assertFrontTapHits("left_calf_shin") }
    func testTapLeftAnkleFootSelectsAnkleFoot() { assertProxyFrontTapHits("left_ankle_foot") }

    // MARK: - 6. Raycast: Front-Visible Regions (Right Side)

    func testTapRightShoulderSelectsShoulder() { assertProxyFrontTapHits("right_shoulder") }
    func testTapRightUpperArmSelectsUpperArm() { assertFrontTapHits("right_upper_arm") }
    func testTapRightElbowSelectsElbow() { assertProxyFrontTapHits("right_elbow") }
    func testTapRightForearmSelectsForearm() { assertFrontTapHits("right_forearm") }
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
