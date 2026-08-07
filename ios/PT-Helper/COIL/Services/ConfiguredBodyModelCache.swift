import RealityKit
import UIKit

/// Caches a single, fully-configured body-model template (collision shapes,
/// `InputTargetComponent`, region colors, and zone proxies already built) so
/// every `BodyMap3DView` open only has to clone it instead of re-running that
/// deterministic setup work on `@MainActor` each time.
@MainActor
final class ConfiguredBodyModelCache {
    static let shared = ConfiguredBodyModelCache()

    private var template: Entity?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    /// Returns a clone of the configured template, building it once via `buildTemplate`
    /// on first use and reusing it for every subsequent call.
    func configuredModel(regionKeys: Set<String>, buildTemplate: (Entity) -> Void) async throws -> Entity {
        if let template {
            return template.clone(recursive: true)
        }

        let raw = try await BodyModelCache.shared.loadModel()
        buildTemplate(raw)
        template = raw
        return raw.clone(recursive: true)
    }

    @objc private func handleMemoryWarning() {
        template = nil
        Task { await BodyModelCache.shared.clear() }
    }
}
