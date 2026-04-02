import SwiftUI
import PhotosUI

// MARK: - Camera Image Picker Wrapper

private struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .camera

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType)
            ? sourceType
            : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Posture Check View

/// Entry point for the Posture Check-In feature. Users select their current context,
/// take or upload a photo, and receive AI-powered alignment feedback.
struct PostureCheckView: View {
    @StateObject private var vm = PostureCheckViewModel.shared
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage?
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bgGradient.ignoresSafeArea()

                switch vm.state {
                case .idle:
                    idleView
                case .analyzing:
                    analyzingView
                case .complete(let result):
                    resultView(result)
                case .error(let msg):
                    errorView(msg)
                }
            }
            .navigationTitle("Posture Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if case .complete = vm.state {
                        NavigationLink(destination: PostureHistoryView()) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundColor(AppColors.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraImagePicker(image: $capturedImage)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, image in
                guard let image else { return }
                Task { await vm.analyze(image: image) }
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        capturedImage = image
                        await vm.analyze(image: image)
                    }
                }
            }
        }
        .trackScreen("PostureCheck")
    }

    // MARK: - Idle State

    private var idleView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Spacer().frame(height: AppSpacing.lg)

                // Hero
                VStack(spacing: AppSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accentTint)
                            .frame(width: 80, height: 80)
                        Image(systemName: "person.fill.viewfinder")
                            .font(.system(size: 36))
                            .foregroundColor(AppColors.accent)
                    }

                    Text("Posture Check-In")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.primaryText)

                    Text("Take a quick photo and get personalised alignment feedback in seconds.")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                }

                // Context picker
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("What are you doing right now?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)

                    HStack(spacing: AppSpacing.sm) {
                        ForEach(PostureContext.allCases) { context in
                            contextChip(context)
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)

                // Tips
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Label("Tips for best results", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.warning)

                    tipRow(icon: "sun.max.fill", text: "Good lighting with your full upper body visible")
                    tipRow(icon: "iphone.landscape", text: "Side view OR front view both work well")
                    tipRow(icon: "figure.stand", text: "Natural posture — don't adjust before taking the photo")
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 4, x: 0, y: 1)

                // Action buttons
                VStack(spacing: AppSpacing.md) {
                    Button(action: { showCamera = true }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "camera.fill")
                            Text("Take Photo")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("postureCheck.startButton")

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "photo.on.rectangle")
                            Text("Choose from Library")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                        .background(AppColors.elevatedSurface)
                        .foregroundColor(AppColors.accent)
                        .cornerRadius(AppCorners.large)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    private func contextChip(_ context: PostureContext) -> some View {
        Button {
            vm.selectedContext = context
        } label: {
            VStack(spacing: 4) {
                Image(systemName: context.icon)
                    .font(.system(size: 16))
                Text(context.displayName)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.md)
            .background(vm.selectedContext == context ? AppColors.accent : AppColors.elevatedSurface)
            .foregroundColor(vm.selectedContext == context ? .white : AppColors.secondaryText)
            .cornerRadius(AppCorners.medium)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(AppColors.accent)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
        }
    }

    // MARK: - Analyzing State

    private var analyzingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(AppColors.accent.opacity(0.15), lineWidth: 6)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: true)

                Image(systemName: "person.fill.viewfinder")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.accent)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: AppSpacing.sm) {
                Text("Analysing Your Posture")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                Text("Reading your alignment from the image…")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Result State

    private func resultView(_ result: PostureCheckResult) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                Spacer().frame(height: AppSpacing.sm)

                // Score ring
                scoreRing(result)

                // Observations card
                if !result.observations.isEmpty {
                    observationsCard(result.observations)
                }

                // Corrective cues card
                if !result.correctiveCues.isEmpty {
                    correctiveCuesCard(result.correctiveCues)
                }

                // Actions
                VStack(spacing: AppSpacing.md) {
                    Button {
                        vm.reset()
                        capturedImage = nil
                    } label: {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Check Again")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    NavigationLink(destination: PostureHistoryView()) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                            Text("View History")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(AppSpacing.lg)
                        .background(AppColors.elevatedSurface)
                        .foregroundColor(AppColors.accent)
                        .cornerRadius(AppCorners.large)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func scoreRing(_ result: PostureCheckResult) -> some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .stroke(scoreColor(result).opacity(0.15), lineWidth: 10)
                    .frame(width: 130, height: 130)

                Circle()
                    .trim(from: 0, to: Double(result.score) / 100.0)
                    .stroke(scoreColor(result), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))
                    .animation(AppAnimations.smooth, value: result.score)

                VStack(spacing: 2) {
                    Text("\(result.score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor(result))
                        .accessibilityIdentifier("postureCheck.scoreLabel")
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            Text(result.scoreLabel)
                .font(.title3.weight(.semibold))
                .foregroundColor(scoreColor(result))

            HStack(spacing: AppSpacing.xs) {
                Image(systemName: result.context.icon)
                    .font(.caption)
                    .foregroundColor(AppColors.mutedText)
                Text(result.context.displayName)
                    .font(.caption)
                    .foregroundColor(AppColors.mutedText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    private func observationsCard(_ observations: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("What I noticed", systemImage: "eye.fill")
                .font(.headline)
                .foregroundColor(AppColors.primaryText)

            ForEach(observations, id: \.self) { obs in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(obs)
                        .font(.subheadline)
                        .foregroundColor(AppColors.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    private func correctiveCuesCard(_ cues: [String]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Try this now", systemImage: "arrow.right.circle.fill")
                .font(.headline)
                .foregroundColor(AppColors.success)

            ForEach(cues, id: \.self) { cue in
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(AppColors.success)
                        .padding(.top, 2)
                    Text(cue)
                        .font(.subheadline)
                        .foregroundColor(AppColors.primaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Analysis Failed")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundColor(AppColors.primaryText)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            VStack(spacing: AppSpacing.md) {
                Button {
                    vm.reset()
                    capturedImage = nil
                    showCamera = true
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button { dismiss() } label: { Text("Cancel") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Helpers

    private func scoreColor(_ result: PostureCheckResult) -> Color {
        switch result.score {
        case 80...100: return AppColors.success
        case 60..<80:  return AppColors.accent
        case 40..<60:  return AppColors.warning
        default:       return AppColors.danger
        }
    }
}
