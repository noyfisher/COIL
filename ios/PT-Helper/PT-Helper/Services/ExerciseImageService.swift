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

    /// Lock protecting mutable dictionaries from concurrent access.
    private let lock = NSLock()

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
        "calf-raise-with-hamstring-co-activation-weeks-3-6": "double-leg-calf-raise",
        "calf-raises-bilateral": "double-leg-calf-raise",
        // Band pull-apart variants
        "band-pull-apart": "band-pull-aparts",
        "half-kneeling-band-pull-aparts": "band-pull-aparts",
        "band-pull-apart-external-rotation": "resistance-band-external-rotation-at-90-90",
        // Bird dog variants
        "bird-dog-core-stabilizer": "bird-dog",
        "quadruped-bird-dog": "bird-dog",
        "quadruped-spinal-extensions-bird-dogs": "bird-dog",
        // Child's pose variants
        "childs-pose-with-shoulder-reach": "childs-pose-with-side-reach",
        // Cat-cow variants
        "cat-cow-stretch-modified-for-lower-back-relief": "cat-cow-stretch",
        "cat-cow-stretch-prone-hold-variation": "cat-cow-stretch",
        "cat-cow-stretch-sequence": "cat-cow-stretch",
        "cat-cow-stretch-spine-mobility": "cat-cow-stretch",
        // Clamshell variants
        "clamshells-left-side-emphasis": "clamshells",
        "clamshells-side-lying-hip-abduction": "clamshells",
        // Dead bug variants
        "dead-bug-modified-for-core-stability-and-l4-protection": "dead-bug",
        "dead-bug-core-stability-for-lower-back-support": "dead-bug",
        "dead-bug-core-stability-hamstring-protection": "dead-bug",
        "dead-bug-modified": "dead-bug",
        // Glute bridge variants
        "glute-bridge-with-core-hold": "glute-bridge-with-isometric-hold",
        "supine-glute-bridge-with-hamstring-activation": "glute-bridge",
        "glute-bridge-with-hamstring-engagement": "glute-bridge",
        "glute-bridges-bilateral": "glute-bridges",
        "supine-hip-bridge": "glute-bridge",
        "banded-glute-kickbacks-standing-hip-extension": "standing-hip-extension",
        // Hamstring stretch variants
        "hamstring-and-calf-stretch-supine-strap-assist": "hamstring-stretch-with-strap",
        "supine-hamstring-stretch-with-strap": "hamstring-stretch-with-strap",
        "seated-forward-fold-hamstring-stretch": "seated-hamstring-stretch",
        "lying-hamstring-and-hip-flexor-stretch-modified": "lying-hip-flexor-stretch",
        "hamstring-stretch": "supine-hamstring-stretch",
        "supine-hamstring-stretch-with-towel-strap": "supine-hamstring-stretch",
        "nordic-hamstring-curl-assisted-weeks-4-6": "hamstring-curls",
        "standing-hamstring-flexibility-walk": "walking",
        // Lateral band walk variants
        "lateral-band-walk-glute-medius-hip-stability": "lateral-band-walks",
        // Monster walk variants
        "monster-walks-resistance-band": "monster-walks",
        // Pendulum variants
        "pendulum-shoulder-circles": "pendulum-swings",
        "right-shoulder-pendulum-circles": "pendulum-swings",
        "seated-shoulder-pendulum-circles": "pendulum-swings",
        // Plantar/soleus stretch variants
        "plantar-fascia-and-soleus-stretch": "soleus-stretch",
        // Plank variants
        "planks-modified-wall-or-incline": "plank",
        "prone-plank-hold-beginner-progression": "plank",
        "tall-plank-with-shoulder-blade-protraction": "plank",
        // Prone variants
        "prone-hamstring-isometric-hold": "prone-hamstring-curl",
        "prone-hip-extension-single-leg-for-glute-activation": "prone-hip-extension",
        "prone-hip-extension-single-leg": "prone-hip-extension",
        "prone-shoulder-external-rotation-with-elbow-support": "side-lying-external-rotation",
        "prone-shoulder-i-y-t-raises": "prone-i-y-t-raises",
        "prone-y-t-w-shoulder-activation": "prone-i-y-t-raises",
        "lower-back-quadriceps-tightness---prone-quad-stretch": "standing-quad-stretch",
        "prone-cobra-modified-sphinx": "prone-press-up",
        "prone-cobra-or-modified-sphinx-lower-back-extension": "prone-press-up",
        "prone-sphinx-stretch": "prone-press-up",
        "prone-scapular-squeeze": "prone-scapular-retraction",
        "prone-hip-internal-rotation-piriformis-stretch": "supine-piriformis-stretch",
        "prone-quadriceps-stretch": "standing-quad-stretch",
        // Quad sets variants
        "quad-sets-with-glute-activation": "quad-sets",
        "quad-sets-with-vmo-focus": "quad-sets",
        "quadriceps-sets-isometric": "quad-sets",
        "quadriceps-sets-with-vmo-focus": "quad-sets",
        "quadriceps-sets-bilateral": "quad-sets",
        "quadriceps-strengthening": "quad-sets",
        "quadriceps-and-patellar-tendon-eccentric-stretch": "standing-quad-stretch",
        "quadriceps-eccentric-lowering-controlled-strength": "long-arc-quads",
        "quadriceps-stretch": "standing-quad-stretch",
        "quadriceps-stretch-standing": "standing-quad-stretch",
        "quadriceps-hip-flexor-stretch-kneeling-lunge": "hip-flexor-stretch",
        // Quadruped variants
        "quadruped-cat-cow-stretch": "cat-cow-stretch",
        "thoracic-spine-rotation-quadruped-cat-cow": "quadruped-thoracic-rotation",
        "quadruped-glute-squeeze-activation-endurance": "prone-glute-squeeze-holds",
        "quadruped-hip-extension-glute-activation": "fire-hydrants",
        "quadruped-hip-shoulder-rocks": "quadruped-rocking",
        "quadruped-rocking-with-spinal-extension": "quadruped-rocking",
        // External rotation variants
        "external-rotation-with-elbow-bent-90-90-position": "external-rotation",
        "right-shoulder-external-rotation-prone": "side-lying-external-rotation",
        // Scapular variants
        "scapular-push-up-hold": "wall-push-ups",
        "scapular-push-up-plus": "wall-push-ups",
        "scapular-push-up-plus-modified": "wall-push-ups",
        "serratus-anterior-push-up-plus": "wall-push-ups",
        "scapular-wall-slides": "wall-slides",
        // Single leg balance/deadlift variants
        "single-leg-stance-on-firm-surface": "single-leg-balance",
        "single-leg-balance-left-leg-emphasis": "single-leg-balance",
        "single-leg-romanian-deadlift-light-load": "single-leg-deadlift",
        "standing-single-leg-balance-with-hip-hinge": "single-leg-deadlift",
        // Standing variants
        "standing-hamstring-curl-progressive": "standing-hamstring-curl",
        "standing-chest-doorway-stretch": "doorway-stretch",
        "standing-hip-flexor-stretch": "hip-flexor-stretch",
        // Shoulder variants
        "shoulder-rolls": "shoulder-shrugs",
        // Straight leg raise variants
        "straight-leg-raise-slr---supine": "straight-leg-raises",
        "straight-leg-raise-left-leg": "straight-leg-raises",
        "straight-leg-raises-supine": "straight-leg-raises",
        // Supine stretch variants
        "supine-lower-back-stretch": "knee-to-chest-stretch",
        "supine-lower-back-rotation-stretch": "lumbar-rotation-stretch",
        "supine-lower-back-rotation-stretch-spinal-mobility": "lumbar-rotation-stretch",
        "supine-shoulder-external-rotation-90-90-position": "external-rotation",
        "supine-shoulder-external-rotation-with-towel-roll": "external-rotation",
        "supine-shoulder-flexion-with-dowel-or-pvc-pipe": "shoulder-flexion",
        "supine-hip-flexor-stretch": "lying-hip-flexor-stretch",
        "supine-figure-4-stretch-alternative-piriformis-stretch": "supine-figure-4-stretch-with-pelvic-mobilization",
        // Seated variants
        "seated-knee-extension-with-asthma-pacing": "seated-knee-extension",
        // Wrist/forearm variants
        "eccentric-wrist-extensor-curls": "reverse-wrist-curls",
        "forearm-pronation-supination": "wrist-pronation-supination",
        "isometric-wrist-extensions": "reverse-wrist-curls",
        "isometric-wrist-strengthening-4-direction": "wrist-curls",
        "wrist-flexor-extensor-stretches": "wrist-extensor-stretch",
        "wrist-flexor-stretches": "wrist-flexor-stretch",
        // Thoracic variants
        "half-kneeling-thoracic-rotation-with-post": "quadruped-thoracic-rotation",
        "thoracic-spine-extensions": "thoracic-extension",
        // Pigeon pose → piriformis stretch
        "pigeon-pose-deep-hip-flexor-piriformis-stretch": "piriformis-stretch",
        // Nerve glide variants
        "sural-nerve-glide-neural-mobility-for-sural-nerve-irritation": "sciatic-nerve-glide",
        // Terminal knee extension variants
        "terminal-knee-extensions-tke": "terminal-knee-extension",
    ]

    /// Cache for fuzzy-matched keys to avoid redundant computation.
    private var fuzzyMatchCache: [String: String?] = [:]

    /// Body-part synonyms for token-level replacement.
    private static let synonyms: [String: String] = [
        "quadriceps": "quad",
        "quadricep": "quad",
        "hamstrings": "hamstring",
        "calves": "calf",
        "abdominals": "abdominal",
    ]

    /// Resolve the mapping key for an exercise.
    /// Priority: imageFileName → normalized name → alias → fuzzy match → nil.
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

        // 4-7. Fuzzy matching (cached)
        return lock.withLock {
            if let cached = fuzzyMatchCache[normalized] {
                return cached
            }
            let result = fuzzyMatch(normalized)
            fuzzyMatchCache[normalized] = result
            return result
        }
    }

    // MARK: - Fuzzy Matching

    /// Layers 4-7: progressively looser matching strategies.
    private func fuzzyMatch(_ normalized: String) -> String? {
        // Layer 4: Longest prefix match
        // e.g. "cat-cow-stretch-modified-for-lower-back-relief" starts with "cat-cow-stretch-"
        if let match = longestPrefixMatch(normalized) { return match }

        // Layer 5: Suffix match — AI omits position prefix
        // e.g. "calf-raises" is a suffix of "standing-calf-raises"
        if let match = suffixMatch(normalized) { return match }

        // Layer 6: Plural/singular toggle, then retry layers 4-5
        let toggled = normalized.hasSuffix("s") ? String(normalized.dropLast()) : normalized + "s"
        if mapping[toggled] != nil { return toggled }
        if let match = longestPrefixMatch(toggled) { return match }
        if let match = suffixMatch(toggled) { return match }

        // Layer 7: Synonym expansion, then retry layers 2+4+5
        let expanded = applySynonyms(normalized)
        if expanded != normalized {
            if mapping[expanded] != nil { return expanded }
            if let match = longestPrefixMatch(expanded) { return match }
            if let match = suffixMatch(expanded) { return match }
            // Also try plural toggle on expanded form
            let expandedToggled = expanded.hasSuffix("s") ? String(expanded.dropLast()) : expanded + "s"
            if mapping[expandedToggled] != nil { return expandedToggled }
            if let match = longestPrefixMatch(expandedToggled) { return match }
            if let match = suffixMatch(expandedToggled) { return match }
        }

        return nil
    }

    /// Find the longest mapping key that is a prefix of `name` at a hyphen boundary.
    private func longestPrefixMatch(_ name: String) -> String? {
        mapping.keys
            .filter { name.hasPrefix($0 + "-") }
            .max(by: { $0.count < $1.count })
    }

    /// Find a mapping key where `name` appears as a suffix at a hyphen boundary.
    /// Prefers the shortest (least specialized) key on ambiguity.
    private func suffixMatch(_ name: String) -> String? {
        let matches = mapping.keys.filter { $0.hasSuffix("-" + name) }
        return matches.min(by: { $0.count < $1.count })
    }

    /// Replace body-part synonym tokens in a hyphen-delimited name.
    private func applySynonyms(_ name: String) -> String {
        var tokens = name.split(separator: "-").map(String.init)
        var changed = false
        for i in tokens.indices {
            if let replacement = Self.synonyms[tokens[i]] {
                tokens[i] = replacement
                changed = true
            }
        }
        return changed ? tokens.joined(separator: "-") : name
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
        let task: Task<UIImage?, Never> = lock.withLock {
            if let existingTask = activeDownloads[key] {
                return existingTask
            }

            let newTask = Task<UIImage?, Never> {
                let image = await self.downloadFromStorage(key: key)
                self.lock.withLock { self.activeDownloads.removeValue(forKey: key) }
                return image
            }

            activeDownloads[key] = newTask
            return newTask
        }

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
