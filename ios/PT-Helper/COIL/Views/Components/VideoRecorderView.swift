import SwiftUI
import UIKit

/// UIKit camera wrapper for recording exercise videos.
/// Uses UIImagePickerController configured for front-facing video capture.
struct VideoRecorderView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onVideoRecorded: (URL) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.mediaTypes = ["public.movie"]
        picker.videoQuality = .typeMedium  // 720p — sufficient for pose detection
        picker.videoMaximumDuration = 30   // 30 seconds max
        picker.cameraCaptureMode = .video
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: VideoRecorderView

        init(parent: VideoRecorderView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let videoURL = info[.mediaURL] as? URL {
                parent.onVideoRecorded(videoURL)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
