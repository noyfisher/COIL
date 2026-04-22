import SwiftUI
import UIKit

/// Displays an animated GIF/APNG for an exercise using UIKit's UIImageView.
/// Falls back to the static image if no animated version is available.
struct AnimatedExerciseView: UIViewRepresentable {
    let imageData: Data

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        // Try to create an animated image from the data
        if let source = CGImageSourceCreateWithData(imageData as CFData, nil) {
            let count = CGImageSourceGetCount(source)
            if count > 1 {
                // Multi-frame image (GIF/APNG)
                var images: [UIImage] = []
                var totalDuration: Double = 0

                for i in 0..<count {
                    if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                        images.append(UIImage(cgImage: cgImage))

                        // Get frame duration
                        if let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                           let gifProps = properties[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                            let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
                                ?? gifProps[kCGImagePropertyGIFDelayTime as String] as? Double
                                ?? 0.1
                            totalDuration += delay
                        } else {
                            totalDuration += 0.1
                        }
                    }
                }

                uiView.animationImages = images
                uiView.animationDuration = totalDuration
                uiView.animationRepeatCount = 0 // Loop forever
                uiView.startAnimating()
            } else {
                // Single frame — just show it
                uiView.image = UIImage(data: imageData)
            }
        }
    }
}

/// View that loads and displays an animated exercise image if available.
struct ExerciseAnimationView: View {
    let exercise: RehabExercise
    @State private var animatedData: Data?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let data = animatedData {
                AnimatedExerciseView(imageData: data)
            } else if isLoading {
                ProgressView()
            } else {
                // Fallback to static image
                ExerciseImageView(exercise: exercise, isCompact: false)
            }
        }
        .task {
            await loadAnimatedImage()
        }
    }

    private func loadAnimatedImage() async {
        guard let fileName = exercise.imageFileName else { return }

        // Check for animated version (append _anim.gif)
        let animatedFileName = fileName
            .replacingOccurrences(of: ".png", with: "_anim.gif")
            .replacingOccurrences(of: ".jpg", with: "_anim.gif")

        isLoading = true
        if let data = await ExerciseImageService.shared.loadAnimatedImageData(named: animatedFileName) {
            animatedData = data
        }
        isLoading = false
    }
}
