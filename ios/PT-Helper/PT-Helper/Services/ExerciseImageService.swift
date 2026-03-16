import Foundation
import os
import UIKit
import FirebaseStorage

/// Loads, caches, and serves AI-generated exercise illustration images.
/// Falls back gracefully when no image is available (the view layer shows an SF Symbol instead).
/// Not @MainActor — disk I/O runs off the main thread.
final class ExerciseImageService: @unchecked Sendable {
    static let shared = ExerciseImageService()

    // MARK: - Mapping

    /// Mapping from normalized filename key to image metadata.
    /// Loaded once from the bundled exercise_image_mapping.json.
    private var mapping: [String: ImageEntry] = [:]

    private struct ImageEntry: Decodable {
        let name: String
        let filename: String
        let category: String
        let target_area: String
    }

    // MARK: - Caches

    /// In-memory image cache (evicted when the app is backgrounded / under memory pressure).
    private let memoryCache = NSCache<NSString, UIImage>()

    /// Disk cache directory: Library/Caches/exercise-images/
    private let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("exercise-images", isDirectory: true)
    }()

    /// Firebase Storage download-URL cache so we only resolve each path once per session.
    private var downloadURLCache: [String: URL] = [:]

    /// Track in-flight downloads to avoid duplicate network requests.
    private var activeDownloads: [String: Task<UIImage?, Never>] = [:]

    // MARK: - Firebase Storage

    private let storageRef: StorageReference = {
        let storage = Storage.storage()
        return storage.reference().child("exercise-images")
    }()

    // MARK: - Init

    private init() {
        // Create disk cache directory
        try? FileManager.default.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)

        // Set memory cache limits (e.g. ~50 images)
        memoryCache.countLimit = 60

        // Load bundled mapping
        loadMapping()
    }

    // MARK: - Public API

    /// Whether an image is available for this exercise (in the mapping).
    func hasImage(for exercise: RehabExercise) -> Bool {
        imageKey(for: exercise) != nil
    }

    /// Load the exercise image asynchronously.
    /// Returns nil if no image is available (caller should show SF Symbol fallback).
    func loadImage(for exercise: RehabExercise) async -> UIImage? {
        guard let key = imageKey(for: exercise) else { return nil }
        return await loadImage(forKey: key)
    }

    /// Preload all images for a rehab plan in the background.
    func preloadImages(for exercises: [RehabExercise]) {
        for exercise in exercises {
            guard let key = imageKey(for: exercise) else { continue }
            // Only preload if not already cached
            if memoryCache.object(forKey: key as NSString) == nil {
                Task {
                    _ = await loadImage(forKey: key)
                }
            }
        }
    }

    /// Returns exercises that do NOT have a matching image in the mapping.
    /// Useful for logging which exercises still need images generated.
    func exercisesWithoutImages(in exercises: [RehabExercise]) -> [RehabExercise] {
        exercises.filter { imageKey(for: $0) == nil }
    }

    /// Load animated image data (GIF/APNG) from cache or Firebase Storage.
    /// Returns raw Data so the caller can create an animated UIImageView.
    func loadAnimatedImageData(named filename: String) async -> Data? {
        // Check disk cache
        let diskPath = diskCacheURL.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: diskPath) {
            return data
        }

        // Try Firebase Storage
        let animRef = storageRef.child(filename)
        let maxSize: Int64 = 5 * 1024 * 1024 // 5 MB for animations

        do {
            let data = try await animRef.data(maxSize: maxSize)
            // Cache to disk
            try? data.write(to: diskPath, options: .atomic)
            return data
        } catch {
            // No animated version available — that's fine
            return nil
        }
    }

    // MARK: - Key Resolution

    /// Alias map: AI-generated exercise name variants → canonical image key.
    /// The AI often generates more specific exercise names (e.g., "Calf Raises (Bilateral, Eccentric Focus)")
    /// that don't exactly match our 178-exercise image set. This maps them to the closest image.
    private static let aliasMap: [String: String] = [
        // Calf raise variants → closest image
        "calf-raises-bilateral-eccentric-focus": "double-leg-calf-raise",
        "calf-raises-bilateral-to-single-leg-progression": "double-leg-calf-raise",
        "calf-raises-double-leg-eccentric-emphasis": "double-leg-calf-raise",
        // Band pull-apart variants
        "band-pull-apart": "band-pull-aparts",
        "half-kneeling-band-pull-aparts": "band-pull-aparts",
        // Bird dog variants
        "bird-dog-core-stabilizer": "bird-dog",
        // Child's pose variants
        "childs-pose-with-shoulder-reach": "childs-pose-with-side-reach",
        // Cat-cow variants
        "cat-cow-stretch-modified-for-lower-back-relief": "cat-cow-stretch",
        // Dead bug variants
        "dead-bug-modified-for-core-stability-and-l4-protection": "dead-bug",
        "dead-bug-core-stability-for-lower-back-support": "dead-bug",
        // Glute bridge variants
        "glute-bridge-with-core-hold": "glute-bridge-with-isometric-hold",
        "supine-glute-bridge-with-hamstring-activation": "glute-bridge",
        // Hamstring stretch variants
        "hamstring-and-calf-stretch-supine-strap-assist": "hamstring-stretch-with-strap",
        "supine-hamstring-stretch-with-strap": "hamstring-stretch-with-strap",
        "seated-forward-fold-hamstring-stretch": "seated-hamstring-stretch",
        "lying-hamstring-and-hip-flexor-stretch-modified": "lying-hip-flexor-stretch",
        // Lateral band walk variants
        "lateral-band-walk-glute-medius-hip-stability": "lateral-band-walks",
        // Monster walk variants
        "monster-walks-resistance-band": "monster-walks",
        // Pendulum variants
        "pendulum-shoulder-circles": "pendulum-swings",
        // Plantar/soleus stretch variants
        "plantar-fascia-and-soleus-stretch": "soleus-stretch",
        // Prone variants
        "prone-hamstring-isometric-hold": "prone-hamstring-curl",
        "prone-hip-extension-single-leg-for-glute-activation": "prone-hip-extension",
        "prone-shoulder-external-rotation-with-elbow-support": "side-lying-external-rotation",
        "prone-shoulder-i-y-t-raises": "prone-i-y-t-raises",
        "lower-back-quadriceps-tightness---prone-quad-stretch": "standing-quad-stretch",
        // Quad sets variants
        "quad-sets-with-glute-activation": "quad-sets",
        "quad-sets-with-vmo-focus": "quad-sets",
        "quadriceps-sets-isometric": "quad-sets",
        "quadriceps-sets-with-vmo-focus": "quad-sets",
        "quadriceps-and-patellar-tendon-eccentric-stretch": "standing-quad-stretch",
        // Quadruped cat-cow variants
        "quadruped-cat-cow-stretch": "cat-cow-stretch",
        "thoracic-spine-rotation-quadruped-cat-cow": "quadruped-thoracic-rotation",
        // External rotation variants
        "external-rotation-with-elbow-bent-90-90-position": "external-rotation",
        // Scapular push-up variants
        "scapular-push-up-hold": "wall-push-ups",
        "scapular-push-up-plus": "wall-push-ups",
        "scapular-push-up-plus-modified": "wall-push-ups",
        "serratus-anterior-push-up-plus": "wall-push-ups",
        // Single leg balance/deadlift variants
        "single-leg-stance-on-firm-surface": "single-leg-balance",
        "single-leg-romanian-deadlift-light-load": "single-leg-deadlift",
        // Standing hamstring curl variants
        "standing-hamstring-curl-progressive": "standing-hamstring-curl",
        // Straight leg raise variants
        "straight-leg-raise-slr---supine": "straight-leg-raises",
        // Supine stretch variants
        "supine-lower-back-stretch": "knee-to-chest-stretch",
        "supine-shoulder-external-rotation-90-90-position": "external-rotation",
        "supine-shoulder-external-rotation-with-towel-roll": "external-rotation",
        "supine-shoulder-flexion-with-dowel-or-pvc-pipe": "shoulder-flexion",
        // Nerve glide variants
        "sural-nerve-glide-neural-mobility-for-sural-nerve-irritation": "sciatic-nerve-glide",
        // Terminal knee extension variants
        "terminal-knee-extensions-tke": "terminal-knee-extension",
    ]

    /// Resolve the mapping key for an exercise.
    /// Priority: imageFileName field → normalized exercise name → alias → nil.
    func imageKey(for exercise: RehabExercise) -> String? {
        // 1. Explicit imageFileName from AI / Firestore
        if let fileName = exercise.imageFileName, mapping[fileName] != nil {
            return fileName
        }

        // 2. Normalize the exercise name and look up
        let normalized = normalizeName(exercise.name)
        if mapping[normalized] != nil {
            return normalized
        }

        // 3. Check alias map for AI-generated name variants
        if let alias = Self.aliasMap[normalized], mapping[alias] != nil {
            return alias
        }

        return nil
    }

    // MARK: - Image Loading Pipeline

    private func loadImage(forKey key: String) async -> UIImage? {
        // 1. Memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // 2. Disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        // 3. Download from Firebase Storage (deduplicate in-flight requests)
        if let existingTask = activeDownloads[key] {
            return await existingTask.value
        }

        let task = Task<UIImage?, Never> {
            let image = await downloadFromStorage(key: key)
            activeDownloads.removeValue(forKey: key)
            return image
        }

        activeDownloads[key] = task
        return await task.value
    }

    // MARK: - Disk Cache

    private func diskCachePath(for key: String) -> URL {
        diskCacheURL.appendingPathComponent("\(key).png")
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let path = diskCachePath(for: key)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        guard let data = try? Data(contentsOf: path) else { return nil }
        return UIImage(data: data)
    }

    private func saveToDisk(key: String, data: Data) {
        let path = diskCachePath(for: key)
        try? data.write(to: path, options: .atomic)
    }

    // MARK: - Firebase Storage Download

    private func downloadFromStorage(key: String) async -> UIImage? {
        guard let entry = mapping[key] else { return nil }
        let filename = entry.filename
        let imageRef = storageRef.child(filename)

        // Download up to 2 MB
        let maxSize: Int64 = 2 * 1024 * 1024

        do {
            let data = try await imageRef.data(maxSize: maxSize)
            guard let image = UIImage(data: data) else { return nil }

            // Cache
            memoryCache.setObject(image, forKey: key as NSString)
            saveToDisk(key: key, data: data)

            return image
        } catch {
            AppLogger.images.error("Download failed for \(filename): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Mapping Loader

    private func loadMapping() {
        guard let url = Bundle.main.url(forResource: "exercise_image_mapping", withExtension: "json") else {
            AppLogger.images.warning("No bundled exercise_image_mapping.json found — images disabled")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            mapping = try JSONDecoder().decode([String: ImageEntry].self, from: data)
            AppLogger.images.info("Loaded mapping with \(self.mapping.count) exercises")
        } catch {
            AppLogger.images.error("Failed to decode mapping: \(error.localizedDescription)")
        }
    }

    // MARK: - Name Normalization

    /// Convert exercise name to a normalized filename key.
    /// e.g. "Quad Sets" → "quad-sets", "Cat-Cow Stretch" → "cat-cow-stretch"
    func normalizeName(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
