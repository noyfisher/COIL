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

    /// Process every Nth frame (2 = every other frame for 30fps → 15 frames/sec)
    private let frameSubsampleRate: Int = 2

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
        let totalFrames = Int(CMTimeGetSeconds(duration) * Double(nominalFrameRate))

        guard totalFrames > 0 else {
            throw PoseDetectionError.emptyVideo
        }

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
            if frameIndex % frameSubsampleRate != 0 {
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

        AppLogger.api.info("PoseDetection: Processed \(poseFrames.count) frames from \(totalFrames) total (subsample: \(self.frameSubsampleRate)x)")

        return poseFrames
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
