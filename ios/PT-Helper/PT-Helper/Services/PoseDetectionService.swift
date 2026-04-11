import Foundation
import Vision
import AVFoundation

// MARK: - Pose Detection Service

/// On-device 3D body pose detection using Apple Vision framework.
/// Processes video frames and returns 3D joint positions for each frame.
class PoseDetectionService {
    static let shared = PoseDetectionService()

    /// Minimum confidence threshold for a joint to be considered valid
    private let minimumConfidence: Float = 0.1

    /// Process every Nth frame. Adaptive: 1 for short videos (≤15s), 2 for longer.
    private let defaultSubsampleRate: Int = 2
    private let shortVideoSubsampleRate: Int = 1
    private let shortVideoThresholdSeconds: Double = 15.0

    private init() {}

    // MARK: - Public API

    /// Detect 3D body poses from a video file.
    /// - Parameters:
    ///   - videoURL: URL to the video file
    ///   - onProgress: Optional progress callback (0.0–1.0)
    /// - Returns: Array of PoseFrame with 3D joint positions
    func detectPoses(
        from videoURL: URL,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> [PoseFrame] {
        let asset = AVURLAsset(url: videoURL)

        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw PoseDetectionError.noVideoTrack
        }

        let duration = try await asset.load(.duration)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let durationSeconds = CMTimeGetSeconds(duration)
        let totalFrames = Int(durationSeconds * Double(nominalFrameRate))

        guard totalFrames > 0 else {
            throw PoseDetectionError.emptyVideo
        }

        // Adaptive subsampling: process every frame for short videos, subsample longer ones
        let subsampleRate = durationSeconds <= shortVideoThresholdSeconds
            ? shortVideoSubsampleRate
            : defaultSubsampleRate

        // Configure asset reader
        let reader = try AVAssetReader(asset: asset)

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false

        guard reader.canAdd(trackOutput) else {
            throw PoseDetectionError.readerConfigError
        }
        reader.add(trackOutput)

        guard reader.startReading() else {
            throw PoseDetectionError.readerStartError(reader.error?.localizedDescription ?? "Unknown error")
        }

        // Process frames
        var poseFrames: [PoseFrame] = []
        var frameIndex = 0
        let fps = Double(nominalFrameRate)

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            // Subsample: skip frames for efficiency
            if frameIndex % subsampleRate != 0 {
                frameIndex += 1
                continue
            }

            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

            // Detect 3D pose in this frame
            if let poseFrame = try await detectPose3D(in: sampleBuffer, timestamp: timestamp) {
                poseFrames.append(poseFrame)
            }

            frameIndex += 1

            // Report progress
            if let onProgress = onProgress {
                let progress = min(Double(frameIndex) / Double(totalFrames), 1.0)
                await MainActor.run {
                    onProgress(progress)
                }
            }
        }

        if reader.status == .failed {
            throw PoseDetectionError.readingFailed(reader.error?.localizedDescription ?? "Unknown error")
        }

        guard !poseFrames.isEmpty else {
            throw PoseDetectionError.noPoseDetected
        }

        // Post-process: compute proxy confidence for each joint
        let refinedFrames = computeProxyConfidence(for: poseFrames, fps: fps)

        AppLogger.api.info("PoseDetection: Processed \(refinedFrames.count) frames from \(totalFrames) total (subsample: \(subsampleRate)x)")

        return refinedFrames
    }

    /// Get the video's frame rate.
    func getVideoFPS(from videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw PoseDetectionError.noVideoTrack
        }
        let rate = try await track.load(.nominalFrameRate)
        return Double(rate)
    }

    /// Get the video's duration in seconds.
    func getVideoDuration(from videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    // MARK: - Proxy Confidence

    /// Bone segments used for link-length stability checks.
    private static let boneSegments: [(from: BodyJoint3D, to: BodyJoint3D)] = [
        (.leftShoulder, .leftElbow),
        (.rightShoulder, .rightElbow),
        (.leftElbow, .leftWrist),
        (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee),
        (.rightHip, .rightKnee),
        (.leftKnee, .leftAnkle),
        (.rightKnee, .rightAnkle),
        (.neck, .root),
    ]

    /// Compute proxy confidence for each joint based on link-length stability and velocity.
    /// Replaces the hardcoded 1.0 values with meaningful per-joint confidence scores.
    private func computeProxyConfidence(for poses: [PoseFrame], fps: Double) -> [PoseFrame] {
        guard poses.count >= 3 else { return poses }

        // Step 1: Compute per-joint link-length coefficient of variation.
        // For each joint, average the CV of all bone segments it participates in.
        var jointBoneCVs: [String: [Double]] = [:]

        for segment in Self.boneSegments {
            let fromKey = segment.from.rawValue
            let toKey = segment.to.rawValue

            let lengths: [Double] = poses.compactMap { frame in
                guard let from = frame.joints[fromKey],
                      let to = frame.joints[toKey] else { return nil }
                let dx = from.x - to.x, dy = from.y - to.y, dz = from.z - to.z
                return sqrt(dx * dx + dy * dy + dz * dz)
            }
            guard lengths.count >= 3 else { continue }

            let mean = lengths.reduce(0, +) / Double(lengths.count)
            guard mean > 0.01 else { continue }
            let variance = lengths.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(lengths.count)
            let cv = sqrt(variance) / mean

            jointBoneCVs[fromKey, default: []].append(cv)
            jointBoneCVs[toKey, default: []].append(cv)
        }

        // Step 2: Build updated frames with proxy confidence from link stability + velocity.
        var updatedPoses: [PoseFrame] = []

        for i in 0..<poses.count {
            var newJoints: [String: JointPoint3D] = [:]

            for (jointName, joint) in poses[i].joints {
                var confidence = 1.0

                // Link-length stability factor (0.1–1.0).
                // CV < 0.05 → full confidence; CV > 0.25 → minimum.
                if let cvs = jointBoneCVs[jointName], !cvs.isEmpty {
                    let avgCV = cvs.reduce(0, +) / Double(cvs.count)
                    let linkFactor = max(0.1, min(1.0, 1.0 - (avgCV - 0.05) / 0.20))
                    confidence *= linkFactor
                }

                // Velocity factor (0.1–1.0): penalize sudden jumps.
                if i > 0 && i < poses.count - 1 {
                    if let prev = poses[i - 1].joints[jointName],
                       let next = poses[i + 1].joints[jointName] {
                        let dt = max(poses[i].timestamp - poses[i - 1].timestamp, 1.0 / fps)
                        let dx = joint.x - prev.x, dy = joint.y - prev.y, dz = joint.z - prev.z
                        let velocity = sqrt(dx * dx + dy * dy + dz * dz) / dt

                        let dt2 = max(poses[i + 1].timestamp - poses[i].timestamp, 1.0 / fps)
                        let dx2 = next.x - joint.x, dy2 = next.y - joint.y, dz2 = next.z - joint.z
                        let velocity2 = sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2) / dt2
                        let accel = abs(velocity2 - velocity) / ((dt + dt2) / 2)

                        // > 3 m/s is suspicious for rehab exercises; > 10 m/s² accel is likely a glitch
                        let velocityFactor = max(0.1, min(1.0, 1.0 - (velocity - 3.0) / 5.0))
                        let accelFactor = max(0.1, min(1.0, 1.0 - (accel - 10.0) / 20.0))
                        confidence *= min(velocityFactor, accelFactor)
                    }
                }

                newJoints[jointName] = JointPoint3D(
                    x: joint.x, y: joint.y, z: joint.z,
                    confidence: confidence
                )
            }

            updatedPoses.append(PoseFrame(
                timestamp: poses[i].timestamp,
                joints: newJoints,
                bodyHeight: poses[i].bodyHeight
            ))
        }

        return updatedPoses
    }

    // MARK: - Private

    /// Detect 3D body pose in a single frame.
    private func detectPose3D(
        in sampleBuffer: CMSampleBuffer,
        timestamp: Double
    ) async throws -> PoseFrame? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let request = VNDetectHumanBodyPose3DRequest()

        try requestHandler.perform([request])

        guard let observation = request.results?.first else {
            return nil  // No person detected in this frame
        }

        // Extract joints
        var joints: [String: JointPoint3D] = [:]
        var bodyHeight: Double?

        // Extract body height if available (Float, in meters)
        bodyHeight = Double(observation.bodyHeight)

        // Map Vision 3D joint names to our BodyJoint3D enum
        let jointMappings: [(BodyJoint3D, VNHumanBodyPose3DObservation.JointName)] = [
            (.root, .root),
            (.head, .centerHead),
            (.topHead, .topHead),
            (.neck, .centerShoulder),  // Vision uses centerShoulder as neck equivalent
            (.spine, .spine),
            (.leftShoulder, .leftShoulder),
            (.rightShoulder, .rightShoulder),
            (.leftElbow, .leftElbow),
            (.rightElbow, .rightElbow),
            (.leftWrist, .leftWrist),
            (.rightWrist, .rightWrist),
            (.leftHip, .leftHip),
            (.rightHip, .rightHip),
            (.leftKnee, .leftKnee),
            (.rightKnee, .rightKnee),
            (.leftAnkle, .leftAnkle),
            (.rightAnkle, .rightAnkle),
        ]

        for (bodyJoint, visionJoint) in jointMappings {
            do {
                let point = try observation.recognizedPoint(visionJoint)
                // VNHumanBodyRecognizedPoint3D has localPosition (simd_float4x4)
                // and inherits from VNRecognizedPoint3D which has position (simd_float4x4)
                let position = point.localPosition

                // Use a default confidence of 1.0 since 3D points don't expose per-joint confidence
                // If the point was detectable, Vision returns it; otherwise recognizedPoint throws
                joints[bodyJoint.rawValue] = JointPoint3D(
                    x: Double(position.columns.3.x),
                    y: Double(position.columns.3.y),
                    z: Double(position.columns.3.z),
                    confidence: 1.0
                )
            } catch {
                // Joint not available in this frame — skip
                continue
            }
        }

        guard !joints.isEmpty else {
            return nil
        }

        return PoseFrame(
            timestamp: timestamp,
            joints: joints,
            bodyHeight: bodyHeight
        )
    }
}

// MARK: - Errors

enum PoseDetectionError: LocalizedError {
    case noVideoTrack
    case emptyVideo
    case readerConfigError
    case readerStartError(String)
    case readingFailed(String)
    case noPoseDetected

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in the file."
        case .emptyVideo:
            return "The video appears to be empty."
        case .readerConfigError:
            return "Failed to configure video reader."
        case .readerStartError(let detail):
            return "Failed to start reading video: \(detail)"
        case .readingFailed(let detail):
            return "Video reading failed: \(detail)"
        case .noPoseDetected:
            return "No body pose was detected in the video. Please ensure your full body is visible."
        }
    }
}
