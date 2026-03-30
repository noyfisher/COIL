import SwiftUI
import RealityKit
import Combine

/// 3D interactive body map using RealityKit.
/// Users can tap body regions to select/deselect them,
/// drag horizontally to rotate, drag vertically to scroll when zoomed,
/// and pinch to zoom.
struct BodyMap3DView: View {
    @StateObject private var viewModel = BodyMapViewModel()

    // MARK: - Navigation State

    @State private var navigateToPainDetail = false
    @State private var showDisclaimer = false
    /// Stable ViewModel for injury analysis — created before navigation flag is set,
    /// cleaned up via onChange when navigation pops back.
    @State private var injuryAnalysisVM: InjuryAnalysisViewModel?

    // MARK: - Model State

    @State private var pivotEntity: Entity?
    @State private var bodyEntity: Entity?
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var originalMaterials: [String: [any RealityKit.Material]] = [:]

    // MARK: - Transform State

    @State private var accumulatedRotation: Float = 0
    @State private var accumulatedPanY: Float = 0
    @State private var accumulatedScale: Float = 1.0

    // MARK: - Gesture State

    @State private var isPinching: Bool = false
    @State private var previousDragTranslation: CGSize = .zero

    // MARK: - Momentum State

    @State private var rotationVelocity: Float = 0
    @State private var momentumTimer: AnyCancellable?
    @State private var lastDragTime: Date?
    @State private var lastDragTranslationX: CGFloat = 0

    // MARK: - Zone Drill-Down State

    @State private var activeZone: BodyZone?
    /// Set of zoneKeys for entities hidden during drill-down.
    @State private var hiddenEntityKeys: Set<String> = []

    // MARK: - UI State

    @State private var lastTappedName: String?
    @State private var showCoachMark = false
    @AppStorage("hasSeenBodyMapCoach") private var hasSeenCoach = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(uiColor: BodyMapConstants.sceneBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerSection
                selectedRegionsPills

                ZStack {
                    model3DSection

                    if isLoading {
                        loadingOverlay
                    }

                    if let error = loadError {
                        modelErrorView(error)
                    }

                    if let name = lastTappedName {
                        regionNameToast(name)
                    }

                    // First-time coach mark overlay
                    if showCoachMark {
                        coachMarkOverlay
                    }
                }

                // Zone sub-region panel (below 3D viewport, visible during drill-down)
                if let zone = activeZone {
                    zoneRegionStrip(zone: zone)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomActions
            }
        }
        .onAppear {
            AnalyticsService.shared.log(.bodyMapOpened)
            if !hasSeenCoach && !isLoading {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation { showCoachMark = true }
                }
            }
        }
        .onChange(of: isLoading) { _, newValue in
            if !newValue && !hasSeenCoach {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { showCoachMark = true }
                }
            }
        }
        .navigationTitle("Body Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView(onAccept: {
                injuryAnalysisVM = InjuryAnalysisViewModel(
                    userProfile: viewModel.userProfile,
                    selectedRegions: viewModel.selectedRegions
                )
                navigateToPainDetail = true
            })
        }
        .onChange(of: navigateToPainDetail) { _, navigating in
            if !navigating {
                injuryAnalysisVM = nil
            }
        }
        .navigationDestination(isPresented: $navigateToPainDetail) {
            if let vm = injuryAnalysisVM {
                PainDetailView(viewModel: vm)
            }
        }
        .trackScreen("BodyMap3D")
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            if let zone = activeZone {
                // Drill-down header with back button and zone name
                HStack {
                    Button(action: exitDrillDown) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .bold))
                            Text("Back")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }

                    Spacer()

                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: zone.iconName)
                            .font(.system(size: 16))
                        Text(zone.displayName)
                            .font(AppFonts.sectionTitle)
                    }
                    .foregroundColor(.white)

                    Spacer()

                    // Invisible spacer to balance the back button
                    Color.clear.frame(width: 60, height: 1)
                }
                Text("Tap regions to select specific areas")
                    .font(.caption)
                    .foregroundColor(.gray)
            } else {
                // Overview header
                Text("Where does it hurt?")
                    .font(AppFonts.sectionTitle)
                    .foregroundColor(.white)
                Text("Tap a body zone to zoom in")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, AppSpacing.lg)
        .padding(.horizontal, AppSpacing.xl)
        .animation(.easeInOut(duration: 0.25), value: activeZone)
    }

    // MARK: - Selected Regions Pills

    private var selectedRegionsPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                if viewModel.selectedRegions.isEmpty {
                    Text("No areas selected")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    ForEach(viewModel.selectedRegions, id: \.id) { region in
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(Color(uiColor: BodyMapConstants.highlightColor))
                                .frame(width: 8, height: 8)
                            Text(region.name)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                            Button(action: {
                                withAnimation(AppAnimations.springy) {
                                    viewModel.toggleSelection(for: region)
                                }
                                restoreMaterial(for: region.zoneKey)
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color(uiColor: BodyMapConstants.highlightColor).opacity(0.8))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .frame(height: 40)
        .padding(.top, AppSpacing.sm)
    }

    // MARK: - 3D Model

    private var model3DSection: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual

                do {
                    let entity = try await BodyModelCache.shared.loadModel()
                    entity.scale = SIMD3<Float>(repeating: BodyMapConstants.modelScale)

                    let pivot = Entity()
                    entity.position.y = -BodyMapConstants.modelHalfHeight
                    pivot.addChild(entity)

                    let regionKeys = Set(viewModel.regions.map(\.zoneKey))

                    configureCollisionShapes(for: entity, regionKeys: regionKeys)
                    createProxyEntities(for: entity, regionKeys: regionKeys)


                    content.add(pivot)
                    pivotEntity = pivot
                    bodyEntity = entity
                    isLoading = false

                } catch {
                    AppLogger.data.error("Failed to load body model: \(error.localizedDescription)")
                    isLoading = false
                    loadError = error
                }
            }
            .gesture(doubleTapGesture)
            .gesture(tapGesture)
            .gesture(rotateAndPanGesture)
            .simultaneousGesture(zoomGesture)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Reset button (bottom-right)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    resetViewButton
                        .padding(.trailing, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.md)
                }
            }

        }
    }

    // MARK: - Loading & Error Overlays

    private var loadingOverlay: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
            Text("Loading 3D Model...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: BodyMapConstants.loadingOverlayBackground))
    }

    private func modelErrorView(_ error: Error) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Unable to Load 3D Model")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(.white)
                Text("Please try again or restart the app.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }

            Button(action: retryModelLoad) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.body.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accent)
                .cornerRadius(AppCorners.card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: BodyMapConstants.sceneBackground))
    }

    // MARK: - Coach Mark Overlay

    private var coachMarkOverlay: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()

            VStack(spacing: AppSpacing.xl) {
                HStack(spacing: AppSpacing.xxl) {
                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Tap to zoom in")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "hand.draw.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Drag to rotate")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }

                    VStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                            .symbolEffect(.pulse, options: .repeating)
                        Text("Pinch to zoom")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }
                }

                Text("Tap a body zone, then select specific areas")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))

                Button(action: {
                    withAnimation { showCoachMark = false }
                    hasSeenCoach = true
                }) {
                    Text("Got it")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.accent)
                        .padding(.horizontal, AppSpacing.xxl)
                        .padding(.vertical, AppSpacing.sm)
                        .background(.white)
                        .cornerRadius(AppCorners.pill)
                }
            }
            .padding(AppSpacing.xl)
            .background(.ultraThinMaterial)
            .cornerRadius(AppCorners.xl)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .transition(.opacity)
        .onTapGesture {
            withAnimation { showCoachMark = false }
            hasSeenCoach = true
        }
    }

    private func regionNameToast(_ name: String) -> some View {
        VStack {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(Color.black.opacity(0.75))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .scale))
            Spacer()
        }
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Gestures

    /// Double-tap: exit drill-down if active, otherwise toggle zoom
    private var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2)
            .targetedToAnyEntity()
            .onEnded { _ in
                // If in drill-down, double-tap exits back to overview
                if activeZone != nil {
                    exitDrillDown()
                    return
                }

                guard let pivot = pivotEntity else { return }

                cancelMomentum()

                let targetScale: Float
                if accumulatedScale > 1.5 {
                    targetScale = 1.0
                    accumulatedPanY = 0
                } else {
                    targetScale = BodyMapConstants.doubleTapZoomLevel
                }
                accumulatedScale = targetScale

                var target = pivot.transform
                target.scale = SIMD3<Float>(repeating: targetScale)
                if targetScale <= 1.0 {
                    target.translation.y = 0
                }
                pivot.move(to: target, relativeTo: pivot.parent,
                           duration: 0.35, timingFunction: .easeInOut)

                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }

    /// Tap to select/deselect body parts
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                handleEntityTap(value.entity)
            }
    }

    /// Single-finger drag: omni-directional rotation + pan simultaneously
    private var rotateAndPanGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isPinching else { return }
                guard let pivot = pivotEntity else { return }

                // Delta since last frame (for velocity tracking)
                let deltaX = value.translation.width - previousDragTranslation.width
                previousDragTranslation = value.translation

                // Cancel momentum on first move
                if lastDragTime == nil {
                    cancelMomentum()
                    rotationVelocity = 0
                }

                // Rotation from horizontal component (always active)
                let dragAngle = Float(value.translation.width) * BodyMapConstants.rotationSensitivity
                pivot.transform.rotation = simd_quatf(
                    angle: accumulatedRotation + dragAngle,
                    axis: SIMD3<Float>(0, 1, 0)
                )

                // Track velocity for momentum
                let now = Date()
                if let last = lastDragTime {
                    let dt = now.timeIntervalSince(last)
                    if dt > 0.001 {
                        let dx = Float(deltaX) * BodyMapConstants.rotationSensitivity
                        rotationVelocity = dx / Float(dt) / 60.0
                    }
                }
                lastDragTime = now
                lastDragTranslationX = value.translation.width

                // Pan from vertical component (only when zoomed)
                if accumulatedScale > 1.0 {
                    let rawPanY = accumulatedPanY - Float(value.translation.height) * BodyMapConstants.panSensitivity
                    let zoomFactor = max(accumulatedScale - 1.0, 0)
                    let maxPan: Float = zoomFactor * 1.0

                    let clampedPanY: Float
                    if rawPanY > maxPan {
                        clampedPanY = maxPan + (rawPanY - maxPan) * BodyMapConstants.rubberBandFactor
                    } else if rawPanY < -maxPan {
                        clampedPanY = -maxPan - (-maxPan - rawPanY) * BodyMapConstants.rubberBandFactor
                    } else {
                        clampedPanY = rawPanY
                    }
                    pivot.position.y = clampedPanY
                }
            }
            .onEnded { value in
                guard !isPinching else { return }

                // Commit rotation
                accumulatedRotation += Float(value.translation.width) * BodyMapConstants.rotationSensitivity

                // Start momentum if velocity is significant
                if abs(rotationVelocity) > BodyMapConstants.momentumStopThreshold {
                    startRotationMomentum()
                }

                // Commit pan (clamp to bounds, spring back if overshot)
                if accumulatedScale > 1.0 {
                    let rawPanY = accumulatedPanY - Float(value.translation.height) * BodyMapConstants.panSensitivity
                    let zoomFactor = max(accumulatedScale - 1.0, 0)
                    let maxPan: Float = zoomFactor * 1.0
                    accumulatedPanY = min(max(rawPanY, -maxPan), maxPan)

                    if let pivot = pivotEntity,
                       pivot.position.y > maxPan + 0.001 || pivot.position.y < -maxPan - 0.001 {
                        var target = pivot.transform
                        target.translation.y = accumulatedPanY
                        pivot.move(to: target, relativeTo: pivot.parent,
                                   duration: 0.25, timingFunction: .easeInOut)
                    }
                }

                resetGestureTracking()
            }
    }

    /// Pinch to zoom in/out (Phases 1, 6)
    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                isPinching = true
                guard let pivot = pivotEntity else { return }

                let newScale = accumulatedScale * Float(value.magnification)

                // Phase 6: rubber-band at limits
                let clamped: Float
                if newScale < BodyMapConstants.minScale {
                    clamped = BodyMapConstants.minScale - (BodyMapConstants.minScale - newScale) * BodyMapConstants.rubberBandFactor
                } else if newScale > BodyMapConstants.maxScale {
                    clamped = BodyMapConstants.maxScale + (newScale - BodyMapConstants.maxScale) * BodyMapConstants.rubberBandFactor
                } else {
                    clamped = newScale
                }

                pivot.scale = SIMD3<Float>(repeating: max(clamped, BodyMapConstants.absoluteMinScale))
            }
            .onEnded { value in
                let newScale = accumulatedScale * Float(value.magnification)
                accumulatedScale = min(max(newScale, BodyMapConstants.minScale), BodyMapConstants.maxScale)

                // Clamp existing pan to new zoom's range
                let zoomFactor = max(accumulatedScale - 1.0, 0)
                let maxPan: Float = zoomFactor * 1.0
                accumulatedPanY = min(max(accumulatedPanY, -maxPan), maxPan)

                // If zoomed out to ~1x, snap pan back to center
                if accumulatedScale < BodyMapConstants.snapToCenterThreshold {
                    accumulatedPanY = 0
                }

                // Phase 6: spring back if visually overshot limits
                if let pivot = pivotEntity {
                    let visualScale = pivot.scale.x
                    if visualScale < BodyMapConstants.minScale || visualScale > BodyMapConstants.maxScale
                        || accumulatedScale < BodyMapConstants.snapToCenterThreshold {
                        var target = pivot.transform
                        target.scale = SIMD3<Float>(repeating: accumulatedScale)
                        target.translation.y = accumulatedPanY
                        pivot.move(to: target, relativeTo: pivot.parent,
                                   duration: 0.3, timingFunction: .easeInOut)
                    }
                }

                isPinching = false
            }
    }

    // MARK: - Rotation Momentum (Phase 3)

    private func startRotationMomentum() {
        momentumTimer?.cancel()

        momentumTimer = Timer.publish(every: BodyMapConstants.momentumFPS, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard let pivot = pivotEntity else {
                    cancelMomentum()
                    return
                }

                rotationVelocity *= BodyMapConstants.momentumFriction

                if abs(rotationVelocity) < BodyMapConstants.momentumStopThreshold {
                    cancelMomentum()
                    rotationVelocity = 0
                    return
                }

                accumulatedRotation += rotationVelocity
                pivot.transform.rotation = simd_quatf(
                    angle: accumulatedRotation,
                    axis: SIMD3<Float>(0, 1, 0)
                )
            }
    }

    private func cancelMomentum() {
        momentumTimer?.cancel()
        momentumTimer = nil
    }

    private func resetGestureTracking() {
        previousDragTranslation = .zero
        lastDragTime = nil
        lastDragTranslationX = 0
    }

    // MARK: - Reset View Button

    private var resetViewButton: some View {
        Button(action: resetView) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .semibold))
                Text("Reset")
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        VStack(spacing: AppSpacing.md) {
            HStack {
                Text("\(viewModel.selectedRegions.count) area(s) selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                Spacer()
                if !viewModel.selectedRegions.isEmpty {
                    Button(action: { clearAllSelections() }) {
                        Text("Clear All")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppColors.danger)
                    }
                }
            }

            Button(action: {
                if DisclaimerManager.hasAccepted {
                    injuryAnalysisVM = InjuryAnalysisViewModel(
                        userProfile: viewModel.userProfile,
                        selectedRegions: viewModel.selectedRegions
                    )
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
                .padding(.vertical, AppSpacing.lg)
                .background(
                    viewModel.selectedRegions.isEmpty
                        ? Color.gray.opacity(0.3)
                        : AppColors.accent
                )
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(AppCorners.large)
            }
            .disabled(viewModel.selectedRegions.isEmpty)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.bottom, AppSpacing.xxl)
        .padding(.top, AppSpacing.md)
    }

    // MARK: - Model Setup Helpers

    /// Configure each body-region child for tap interaction and apply region colors.
    @MainActor
    private func configureCollisionShapes(for parent: Entity, regionKeys: Set<String>) {
        for child in parent.children {
            if regionKeys.contains(child.name),
               child.components[ModelComponent.self] != nil {
                child.components.set(InputTargetComponent(allowedInputTypes: .indirect))

                let baseKey = BodyMapConstants.regionBaseKey(child.name)
                if baseKey == "forearm" {
                    // Don't generate mesh collision for forearm — its convex hull overlaps
                    // the wrist_hand entity and intercepts taps meant for the hand.
                    // Forearm uses only its proxy sphere (defined in proxyRadii) for tap detection.
                } else {
                    child.generateCollisionShapes(recursive: true)
                }

                applyRegionColor(to: child)

                if let mc = child.components[ModelComponent.self] {
                    originalMaterials[child.name] = mc.materials
                }
            }
            configureCollisionShapes(for: child, regionKeys: regionKeys)
        }
    }

    /// Create invisible forward-protruding proxy entities for small regions.
    @MainActor
    private func createProxyEntities(for entity: Entity, regionKeys: Set<String>) {
        for zoneKey in regionKeys {
            let baseKey = BodyMapConstants.regionBaseKey(zoneKey)
            guard let radius = BodyMapConstants.proxyRadii[baseKey],
                  let regionEntity = entity.findEntity(named: zoneKey) else { continue }

            let bounds = regionEntity.visualBounds(relativeTo: entity)
            let center = bounds.center

            var proxyZ = center.z
            if baseKey == "knee" {
                proxyZ = bounds.min.z + bounds.extents.z * BodyMapConstants.kneeCapHeightFraction
            } else if baseKey == "ankle_foot" {
                proxyZ = center.z
            } else if baseKey == "head" {
                // Push head proxy up toward the top of the skull, away from the neck
                proxyZ = bounds.max.z - bounds.extents.z * 0.2
            }

            var proxyX = center.x
            if baseKey == "ankle_foot" {
                if zoneKey.hasPrefix("left_") {
                    proxyX = center.x - BodyMapConstants.ankleProxyLateralBias
                } else if zoneKey.hasPrefix("right_") {
                    proxyX = center.x + BodyMapConstants.ankleProxyLateralBias
                }
            }

            // Regions that need extra forward bias to sit in front of adjacent regions
            let forwardBias: Float
            switch baseKey {
            case "hip": forwardBias = 0.05
            case "head": forwardBias = 0.04
            default: forwardBias = BodyMapConstants.proxyForwardBias
            }

            let proxy = Entity()
            proxy.name = BodyMapConstants.proxyPrefix + zoneKey
            proxy.position = SIMD3<Float>(
                proxyX,
                bounds.min.y - forwardBias,
                proxyZ
            )

            if baseKey == "ankle_foot" {
                let capsuleHeight = bounds.extents.z * BodyMapConstants.ankleCapsuleHeightFraction
                let shape = ShapeResource.generateCapsule(height: capsuleHeight, radius: radius)
                proxy.components.set(CollisionComponent(shapes: [shape]))
                proxy.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(1, 0, 0))
            } else {
                let shape = ShapeResource.generateSphere(radius: radius)
                proxy.components.set(CollisionComponent(shapes: [shape]))
            }

            proxy.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            entity.addChild(proxy)
        }
    }

    // MARK: - Interaction Logic

    private func handleEntityTap(_ entity: Entity) {
        let name: String
        if entity.name.hasPrefix(BodyMapConstants.proxyPrefix) {
            name = String(entity.name.dropFirst(BodyMapConstants.proxyPrefix.count))
        } else {
            name = entity.name
        }

        guard viewModel.regions.contains(where: { $0.zoneKey == name }) else {
            return
        }

        if let zone = activeZone {
            // Drill-down mode: only respond to taps within the active zone
            guard zone.regionZoneKeys.contains(name) else { return }
            selectRegion(named: name)
        } else {
            // Overview mode: drill into the tapped entity's zone
            guard let zone = BodyZone.zone(for: name) else { return }
            drillIntoZone(zone)
        }
    }

    /// Toggle selection on a specific region (used in drill-down mode).
    private func selectRegion(named name: String) {
        guard let regionIndex = viewModel.regions.firstIndex(where: { $0.zoneKey == name }) else {
            return
        }

        let region = viewModel.regions[regionIndex]
        let wasSelected = region.isSelected

        let impact = UIImpactFeedbackGenerator(style: wasSelected ? .soft : .light)
        impact.impactOccurred()

        withAnimation(AppAnimations.springy) {
            viewModel.toggleSelection(for: region)
        }

        SessionLogger.shared.logUserAction(wasSelected ? .regionDeselected : .regionSelected,
                                            action: wasSelected ? "deselect" : "select",
                                            metadata: ["region": region.name, "zoneKey": region.zoneKey])

        if wasSelected {
            restoreMaterial(for: name)
        } else {
            applyHighlight(for: name)
        }

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

    /// Toggle a region from the ZoneSelectionPanel (same logic, called via panel callback).
    private func toggleRegionInDrillDown(_ region: BodyRegion) {
        selectRegion(named: region.zoneKey)
    }

    // MARK: - Zone Drill-Down

    private func drillIntoZone(_ zone: BodyZone) {
        guard let pivot = pivotEntity else { return }

        cancelMomentum()
        rotationVelocity = 0

        // Look up camera target
        guard let target = BodyMapConstants.zoneCameraTargets[zone.rawValue] else { return }

        // Update accumulated state to match the drill-down position
        accumulatedScale = target.pivotScale
        accumulatedPanY = target.pivotY
        accumulatedRotation += target.rotation

        // Animate pivot to frame the zone
        var transform = pivot.transform
        transform.scale = SIMD3<Float>(repeating: target.pivotScale)
        transform.translation.x = target.pivotX
        transform.translation.y = target.pivotY
        transform.rotation = simd_quatf(angle: accumulatedRotation, axis: SIMD3<Float>(0, 1, 0))

        pivot.move(to: transform, relativeTo: pivot.parent,
                   duration: BodyMapConstants.zoneDrillDuration, timingFunction: .easeInOut)

        // Dim non-zone entities
        dimNonZoneEntities(zone: zone)

        withAnimation(.easeInOut(duration: 0.3)) {
            activeZone = zone
            viewModel.activeZone = zone
        }

        // Show zone name toast
        withAnimation(.easeOut(duration: 0.2)) {
            lastTappedName = zone.displayName
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeIn(duration: 0.3)) {
                if lastTappedName == zone.displayName {
                    lastTappedName = nil
                }
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        SessionLogger.shared.logUserAction(.regionSelected,
                                            action: "zone_drill_in",
                                            metadata: ["zone": zone.rawValue])
    }

    private func exitDrillDown() {
        guard let pivot = pivotEntity else { return }

        cancelMomentum()
        rotationVelocity = 0

        // Undo zone rotation
        if let zone = activeZone,
           let target = BodyMapConstants.zoneCameraTargets[zone.rawValue] {
            accumulatedRotation -= target.rotation
        }

        // Restore all dimmed entities
        restoreAllDimmedEntities()

        // Animate back to overview
        accumulatedScale = 1.0
        accumulatedPanY = 0

        var transform = pivot.transform
        transform.scale = SIMD3<Float>(repeating: 1.0)
        transform.translation.x = 0
        transform.translation.y = 0
        transform.rotation = simd_quatf(angle: accumulatedRotation, axis: SIMD3<Float>(0, 1, 0))

        pivot.move(to: transform, relativeTo: pivot.parent,
                   duration: BodyMapConstants.zoneExitDuration, timingFunction: .easeInOut)

        withAnimation(.easeInOut(duration: 0.3)) {
            activeZone = nil
            viewModel.activeZone = nil
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        SessionLogger.shared.logUserAction(.regionDeselected,
                                            action: "zone_drill_out",
                                            metadata: [:])
    }

    // MARK: - Zone Dimming

    /// Hide all entities that don't belong to the active zone using isEnabled.
    private func dimNonZoneEntities(zone: BodyZone) {
        guard let body = bodyEntity else { return }
        let zoneKeys = Set(zone.regionZoneKeys)
        let keysToHide = Set(viewModel.regions.map(\.zoneKey)).subtracting(zoneKeys)

        hiddenEntityKeys = keysToHide
        setEntitiesEnabled(in: body, keys: keysToHide, enabled: false)
    }

    /// Restore all hidden entities.
    private func restoreAllDimmedEntities() {
        guard let body = bodyEntity else { return }

        setEntitiesEnabled(in: body, keys: hiddenEntityKeys, enabled: true)
        hiddenEntityKeys.removeAll()
    }

    /// Recursively enable/disable entities and their proxies matching the given keys.
    private func setEntitiesEnabled(in parent: Entity, keys: Set<String>, enabled: Bool) {
        for child in parent.children {
            if keys.contains(child.name) {
                child.isEnabled = enabled
            } else if child.name.hasPrefix(BodyMapConstants.proxyPrefix) {
                let regionKey = String(child.name.dropFirst(BodyMapConstants.proxyPrefix.count))
                if keys.contains(regionKey) {
                    child.isEnabled = enabled
                }
            }
            setEntitiesEnabled(in: child, keys: keys, enabled: enabled)
        }
    }

    private func applyHighlight(for entityName: String) {
        guard let body = bodyEntity,
              let entity = body.findEntity(named: entityName) else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: BodyMapConstants.highlightColor)
        material.roughness = .float(BodyMapConstants.highlightRoughness)
        material.metallic = .float(BodyMapConstants.highlightMetallic)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
        }
    }

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
        withAnimation(AppAnimations.springy) {
            viewModel.clearAll()
        }
    }

    private func resetView() {
        // If in drill-down, exit first (which animates back to overview)
        if activeZone != nil {
            exitDrillDown()
        }

        guard let pivot = pivotEntity else { return }

        cancelMomentum()
        rotationVelocity = 0

        accumulatedRotation = 0
        accumulatedScale = 1.0
        accumulatedPanY = 0
        resetGestureTracking()

        var target = Transform.identity
        target.rotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        target.scale = SIMD3<Float>(repeating: 1.0)
        target.translation.y = 0

        pivot.move(to: target, relativeTo: pivot.parent,
                   duration: 0.4, timingFunction: .easeInOut)
    }

    private func retryModelLoad() {
        loadError = nil
        isLoading = true
        // RealityView will re-execute its content closure on next layout pass
    }

    // MARK: - Zone Region Strip

    /// Horizontal scrollable strip of sub-region toggle buttons, shown below the 3D viewport during drill-down.
    private func zoneRegionStrip(zone: BodyZone) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(viewModel.regions(in: zone), id: \.id) { region in
                    Button(action: { toggleRegionInDrillDown(region) }) {
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(regionStripColor(for: region))
                                .frame(width: 8, height: 8)
                            Text(region.name)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                            if region.isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color(uiColor: BodyMapConstants.highlightColor))
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background(
                            region.isSelected
                                ? Color(uiColor: BodyMapConstants.highlightColor).opacity(0.25)
                                : Color.white.opacity(0.1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
        }
        .padding(.top, AppSpacing.sm)
    }

    private func regionStripColor(for region: BodyRegion) -> Color {
        let baseKey = BodyMapConstants.regionBaseKey(region.zoneKey)
        if let color = BodyMapConstants.regionColors[baseKey] {
            return Color(uiColor: color)
        }
        return .gray
    }

    // MARK: - Region Color Coding

    private func applyRegionColor(to entity: Entity) {
        let baseKey = BodyMapConstants.regionBaseKey(entity.name)
        guard let color = BodyMapConstants.regionColors[baseKey] else { return }

        var material = SimpleMaterial()
        material.color = .init(tint: color)
        material.roughness = .float(BodyMapConstants.regionRoughness)
        material.metallic = .float(BodyMapConstants.regionMetallic)

        if var mc = entity.components[ModelComponent.self] {
            mc.materials = [material]
            entity.components[ModelComponent.self] = mc
        }
    }
}
