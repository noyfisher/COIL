import SwiftUI
import RealityKit

/// 3D interactive body map using RealityKit.
/// Users can tap body regions to select/deselect them,
/// drag horizontally to rotate, drag vertically to scroll when zoomed,
/// and pinch to zoom.
struct BodyMap3DView: View {
    @StateObject private var viewModel = BodyMapViewModel()
    @State private var navigateToPainDetail = false
    @State private var showDisclaimer = false
    @State private var pivotEntity: Entity?   // parent we rotate/zoom/pan
    @State private var bodyEntity: Entity?     // actual model (child of pivot)
    @State private var isLoading = true

    // Free horizontal rotation — accumulates across drag gestures
    @State private var accumulatedRotation: Float = 0

    // Vertical pan — lets user scroll to head/feet when zoomed in
    @State private var accumulatedPanY: Float = 0

    // Pinch-to-zoom — accumulates across magnify gestures
    @State private var accumulatedScale: Float = 1.0
    private let minScale: Float = 0.6
    private let maxScale: Float = 4.0

    // Store original materials keyed by entity name
    @State private var originalMaterials: [String: [any RealityKit.Material]] = [:]

    // Brief region-name toast shown on tap
    @State private var lastTappedName: String?

    // Highlight color for selected body parts (vibrant red)
    private let highlightColor = UIColor(red: 0.95, green: 0.20, blue: 0.20, alpha: 1.0)

    // Color coding for each region group (bilateral pairs share a color)
    private let regionColors: [String: UIColor] = [
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

    // Proxy prefix for invisible tap targets
    private let proxyPrefix = "_proxy_"

    // Small regions that get forward-protruding invisible proxy spheres.
    // Key = base region key, Value = sphere radius in model space.
    private let proxyRadii: [String: Float] = [
        "knee": 0.025,
        "elbow": 0.018,
        "ankle_foot": 0.020,
        "wrist_hand": 0.018,
        "neck": 0.025,
        "shoulder": 0.022,
    ]
    private let proxyForwardBias: Float = 0.02

    // Scale factor so the body fills the viewport on load
    private let modelScale: Float = 3.5

    var body: some View {
        ZStack {
            // Dark background
            Color(uiColor: UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerSection

                // Selected regions indicator
                selectedRegionsPills

                // 3D Model — always in view tree so RealityView can load
                ZStack {
                    model3DSection

                    if isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Loading 3D Model...")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: UIColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 0.95)))
                    }

                    // Region name toast on tap
                    if let name = lastTappedName {
                        VStack {
                            Text(name)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.75))
                                .clipShape(Capsule())
                                .transition(.opacity.combined(with: .scale))
                            Spacer()
                        }
                        .padding(.top, 12)
                    }
                }

                // Bottom actions
                bottomActions
            }
        }
        .navigationTitle("Body Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView(onAccept: {
                navigateToPainDetail = true
            })
        }
        .navigationDestination(isPresented: $navigateToPainDetail) {
            PainDetailView(
                viewModel: InjuryAnalysisViewModel(
                    userProfile: viewModel.userProfile,
                    selectedRegions: viewModel.selectedRegions
                )
            )
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 6) {
            Text("Where does it hurt?")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)
            Text("Tap areas • Drag to rotate • Pinch to zoom")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
    }

    // MARK: - Selected Regions Pills

    private var selectedRegionsPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if viewModel.selectedRegions.isEmpty {
                    Text("No areas selected")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    ForEach(viewModel.selectedRegions, id: \.id) { region in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text(region.name)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                            Button(action: {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.toggleSelection(for: region)
                                }
                                restoreMaterial(for: region.zoneKey)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 40)
        .padding(.top, 8)
    }

    // MARK: - 3D Model

    private var model3DSection: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual

                do {
                    // Load from cache (parsed once, cloned for each view instance)
                    let entity = try await BodyModelCache.shared.loadModel()

                    // Scale up so the body fills the screen
                    entity.scale = SIMD3<Float>(repeating: modelScale)

                    // ── Pivot pattern ──────────────────────────────────
                    let pivot = Entity()

                    // Offset: model origin at feet → shift down so torso
                    // center aligns with the pivot origin
                    let modelHalfHeight: Float = 0.85
                    entity.position.y = -modelHalfHeight

                    pivot.addChild(entity)

                    // Configure each body-region child for tap interaction
                    let regionKeys = Set(viewModel.regions.map(\.zoneKey))

                    // All regions use mesh-exact collision (color = boundary)
                    @MainActor func configureChildren(of parent: Entity) {
                        for child in parent.children {
                            if regionKeys.contains(child.name),
                               child.components[ModelComponent.self] != nil {
                                child.components.set(InputTargetComponent(allowedInputTypes: .indirect))
                                child.generateCollisionShapes(recursive: true)

                                applyRegionColor(to: child)

                                if let mc = child.components[ModelComponent.self] {
                                    originalMaterials[child.name] = mc.materials
                                }
                            }
                            configureChildren(of: child)
                        }
                    }
                    configureChildren(of: entity)

                    // Create invisible forward-protruding proxy entities for small regions.
                    // These proxy spheres sit in front of neighboring mesh collision,
                    // so SpatialTapGesture hits them first when the user taps the region.
                    for zoneKey in regionKeys {
                        let baseKey = regionBaseKey(zoneKey)
                        guard let radius = proxyRadii[baseKey],
                              let regionEntity = entity.findEntity(named: zoneKey) else { continue }

                        let bounds = regionEntity.visualBounds(relativeTo: entity)
                        let center = bounds.center

                        // Model is Z-up: Z = height, Y = depth (negative = anterior).
                        // Knee mesh includes long muscles (Sartorius from hip to shin)
                        // so bounds.center.z is mid-thigh height. The kneecap is at
                        // ~20% from the bottom of the Z range.
                        var proxyZ = center.z
                        if baseKey == "knee" {
                            proxyZ = bounds.min.z + bounds.extents.z * 0.2
                        }

                        let proxy = Entity()
                        proxy.name = proxyPrefix + zoneKey
                        // Push sphere anterior (negative Y = toward camera from front)
                        // past neighboring thigh/calf collision surfaces
                        proxy.position = SIMD3<Float>(
                            center.x,
                            bounds.min.y - proxyForwardBias,
                            proxyZ
                        )

                        let shape = ShapeResource.generateSphere(radius: radius)
                        proxy.components.set(CollisionComponent(shapes: [shape]))
                        proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))

                        entity.addChild(proxy)
                    }

                    content.add(pivot)
                    pivotEntity = pivot
                    bodyEntity = entity
                    isLoading = false

                } catch {
                    AppLogger.data.error("Failed to load body model: \(error.localizedDescription)")
                }
            }
            .gesture(tapGesture)
            .gesture(rotateAndPanGesture)
            .simultaneousGesture(zoomGesture)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Reset view button (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    resetViewButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Gestures

    /// Tap to select/deselect body parts
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                handleEntityTap(value.entity)
            }
    }

    /// Single-finger drag: horizontal → rotate, vertical → pan up/down
    private var rotateAndPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard let pivot = pivotEntity else { return }

                // ── Horizontal → rotation ─────────────────────────
                let rotSensitivity: Float = 0.008
                let dragAngle = Float(value.translation.width) * rotSensitivity
                let totalAngle = accumulatedRotation + dragAngle
                pivot.transform.rotation = simd_quatf(
                    angle: totalAngle,
                    axis: SIMD3<Float>(0, 1, 0)
                )

                // ── Vertical → pan (useful when zoomed in) ───────
                let panSensitivity: Float = 0.003
                let rawPanY = accumulatedPanY - Float(value.translation.height) * panSensitivity

                // Pan range scales with zoom — no pan at 1x, full range at max zoom
                let zoomFactor = max(accumulatedScale - 1.0, 0)
                let maxPan: Float = zoomFactor * 1.0
                let clampedPanY = min(max(rawPanY, -maxPan), maxPan)

                pivot.position.y = clampedPanY
            }
            .onEnded { value in
                // Commit rotation
                let rotSensitivity: Float = 0.008
                accumulatedRotation += Float(value.translation.width) * rotSensitivity

                // Commit pan
                let panSensitivity: Float = 0.003
                let rawPanY = accumulatedPanY - Float(value.translation.height) * panSensitivity
                let zoomFactor = max(accumulatedScale - 1.0, 0)
                let maxPan: Float = zoomFactor * 1.0
                accumulatedPanY = min(max(rawPanY, -maxPan), maxPan)
            }
    }

    /// Pinch to zoom in/out
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let pivot = pivotEntity else { return }

                let newScale = accumulatedScale * Float(value.magnification)
                let clamped = min(max(newScale, minScale), maxScale)

                pivot.scale = SIMD3<Float>(repeating: clamped)
            }
            .onEnded { value in
                let newScale = accumulatedScale * Float(value.magnification)
                accumulatedScale = min(max(newScale, minScale), maxScale)

                // Clamp existing pan to new zoom's range
                let zoomFactor = max(accumulatedScale - 1.0, 0)
                let maxPan: Float = zoomFactor * 1.0
                accumulatedPanY = min(max(accumulatedPanY, -maxPan), maxPan)

                // If zoomed out to ~1x, snap pan back to center
                if accumulatedScale < 1.1 {
                    accumulatedPanY = 0
                    pivotEntity?.position.y = 0
                }

            }
    }

    // MARK: - Reset View Button

    private var resetViewButton: some View {
        Button(action: resetView) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("Reset")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(viewModel.selectedRegions.count) area(s) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Spacer()
                if !viewModel.selectedRegions.isEmpty {
                    Button(action: { clearAllSelections() }) {
                        Text("Clear All")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.red)
                    }
                }
            }

            Button(action: {
                if DisclaimerManager.hasAccepted {
                    navigateToPainDetail = true
                } else {
                    showDisclaimer = true
                }
            }) {
                HStack(spacing: AppSpacing.sm) {
                    Text("Continue")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    viewModel.selectedRegions.isEmpty
                        ? Color.gray.opacity(0.3)
                        : Color.blue
                )
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(AppCorners.large)
            }
            .disabled(viewModel.selectedRegions.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
        .padding(.top, 12)
    }

    // MARK: - Interaction Logic

    private func handleEntityTap(_ entity: Entity) {
        // Resolve proxy entity names to the real region name
        let name: String
        if entity.name.hasPrefix(proxyPrefix) {
            name = String(entity.name.dropFirst(proxyPrefix.count))
        } else {
            name = entity.name
        }

        guard let regionIndex = viewModel.regions.firstIndex(where: { $0.zoneKey == name }) else {
            return
        }

        let region = viewModel.regions[regionIndex]
        let wasSelected = region.isSelected

        // Haptic
        let impact = UIImpactFeedbackGenerator(style: wasSelected ? .soft : .light)
        impact.impactOccurred()

        // Toggle
        withAnimation(.spring(response: 0.3)) {
            viewModel.toggleSelection(for: region)
        }

        // Update 3D highlight
        if wasSelected {
            restoreMaterial(for: name)
        } else {
            applyHighlight(for: name)
        }

        // Show region name toast briefly
        withAnimation(.easeOut(duration: 0.2)) {
            lastTappedName = region.name
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.3)) {
                if lastTappedName == region.name {
                    lastTappedName = nil
                }
            }
        }
    }

    /// Apply a bright red highlight material to the selected body region
    private func applyHighlight(for entityName: String) {
        guard let body = bodyEntity,
              let entity = body.findEntity(named: entityName) else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: highlightColor)
        material.roughness = .float(0.25)
        material.metallic = .float(0.15)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
        }
    }

    /// Restore the original material when deselected
    private func restoreMaterial(for entityName: String) {
        guard let body = bodyEntity,
              let entity = body.findEntity(named: entityName),
              let origMats = originalMaterials[entityName],
              var mc = entity.components[ModelComponent.self] else { return }

        mc.materials = origMats
        entity.components[ModelComponent.self] = mc
    }

    private func clearAllSelections() {
        for region in viewModel.selectedRegions {
            restoreMaterial(for: region.zoneKey)
        }
        withAnimation(.spring(response: 0.3)) {
            viewModel.clearAll()
        }
    }

    /// Reset rotation, zoom, and pan to defaults
    private func resetView() {
        guard let pivot = pivotEntity else { return }
        accumulatedRotation = 0
        accumulatedScale = 1.0
        accumulatedPanY = 0
        pivot.transform.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        pivot.scale = SIMD3<Float>(repeating: 1.0)
        pivot.position.y = 0
    }

    // MARK: - Region Color Coding

    /// Strip left_/right_ prefix to get the base region key for color lookup.
    private func regionBaseKey(_ zoneKey: String) -> String {
        if zoneKey.hasPrefix("left_") { return String(zoneKey.dropFirst(5)) }
        if zoneKey.hasPrefix("right_") { return String(zoneKey.dropFirst(6)) }
        return zoneKey
    }

    /// Apply a color-coded material to a region entity based on its zone key.
    private func applyRegionColor(to entity: Entity) {
        let baseKey = regionBaseKey(entity.name)
        guard let color = regionColors[baseKey] else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = .float(0.45)
        material.metallic = .float(0.05)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
        }
    }

}
