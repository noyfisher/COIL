import RealityKit
import Foundation

/// Singleton that loads and caches the 3D body model so it is only parsed once per app session.
/// The 5.3 MB USDZ is expensive to parse — this avoids re-loading on every tab switch.
actor BodyModelCache {
    static let shared = BodyModelCache()

    private var cachedEntity: Entity?

    private init() {}

    /// Load (or return cached) body model entity.
    /// The returned entity is a CLONE so each view can modify it independently.
    func loadModel() async throws -> Entity {
        if let cached = cachedEntity {
            return await cached.clone(recursive: true)
        }

        guard let modelURL = Bundle.main.url(forResource: "body_model", withExtension: "usdz") else {
            throw BodyModelError.modelNotFound
        }

        let entity = try await Entity(contentsOf: modelURL)
        cachedEntity = entity
        return await entity.clone(recursive: true)
    }

    /// Clear the cache (e.g., on memory warning)
    func clear() {
        cachedEntity = nil
    }

    enum BodyModelError: LocalizedError {
        case modelNotFound

        var errorDescription: String? {
            "body_model.usdz not found in bundle"
        }
    }
}
