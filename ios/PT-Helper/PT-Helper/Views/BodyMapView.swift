import SwiftUI

struct BodyMapView: View {
    @StateObject private var viewModel = BodyMapViewModel()
    @State private var navigateToPainDetail = false
    @State private var showPulseHint = true

    var body: some View {
        ZStack {
            AppColors.bgGradient
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                VStack(spacing: 6) {
                    Text("Where does it hurt?")
                        .font(.title2.weight(.bold))
                        .foregroundColor(AppColors.primaryText)
                    Text("Tap all areas where you feel pain or discomfort")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 20)

                // Front / Back picker
                Picker("Body Side", selection: $viewModel.currentSide) {
                    Text("Front").tag(BodySide.front)
                    Text("Back").tag(BodySide.back)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                // Body map
                GeometryReader { geometry in
                    ZStack {
                        // Gender-specific body silhouette
                        BodySilhouetteView(
                            sex: viewModel.userProfile.sex,
                            side: viewModel.currentSide
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // "Back View" label when on back side
                        if viewModel.currentSide == .back {
                            VStack {
                                Text("BACK VIEW")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(AppCorners.small)
                                Spacer()
                            }
                        }

                        // Tappable region hotspots for current side
                        ForEach(viewModel.regionsForCurrentSide) { region in
                            if let relPos = region.position(for: viewModel.currentSide) {
                                let position = CGPoint(
                                    x: relPos.x * geometry.size.width,
                                    y: relPos.y * geometry.size.height
                                )

                                Button(action: {
                                    let style: UIImpactFeedbackGenerator.FeedbackStyle = region.isSelected ? .soft : .light
                                    let impact = UIImpactFeedbackGenerator(style: style)
                                    impact.impactOccurred()
                                    withAnimation(.spring(response: 0.3)) {
                                        viewModel.toggleSelection(for: region)
                                    }
                                    showPulseHint = false
                                }) {
                                    VStack(spacing: 2) {
                                        ZStack {
                                            // Pulse ring hint for unselected on first view
                                            if showPulseHint && !region.isSelected {
                                                Circle()
                                                    .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                                                    .frame(width: 56, height: 56)
                                                    .scaleEffect(showPulseHint ? 1.15 : 1.0)
                                                    .opacity(showPulseHint ? 0.6 : 0)
                                                    .animation(
                                                        .easeInOut(duration: 1.2).repeatCount(3, autoreverses: true),
                                                        value: showPulseHint
                                                    )
                                            }

                                            Circle()
                                                .fill(region.isSelected ? AppColors.accent : AppColors.accentTint)
                                                .frame(width: 48, height: 48)
                                                .overlay(
                                                    Circle()
                                                        .stroke(AppColors.accent, lineWidth: region.isSelected ? 0 : 1.5)
                                                )
                                                .overlay(
                                                    Image(systemName: region.isSelected ? "checkmark" : "plus")
                                                        .font(.system(size: 15, weight: .bold))
                                                        .foregroundColor(region.isSelected ? .white : AppColors.accent)
                                                )
                                                .scaleEffect(region.isSelected ? 1.1 : 1.0)
                                        }

                                        Text(region.name)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(region.isSelected ? AppColors.accent : .secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .position(position)
                                .accessibilityLabel("\(region.name)\(region.isSelected ? ", selected" : "")")
                                .accessibilityHint(region.isSelected ? "Double tap to deselect this pain area" : "Double tap to select this pain area")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.currentSide)
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.large)
                .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                .padding(.horizontal, 20)

                // Summary bar and actions
                VStack(spacing: 12) {
                    HStack {
                        Text("\(viewModel.selectedRegions.count) area(s) selected")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(AppColors.primaryText)
                        Spacer()
                        if !viewModel.selectedRegions.isEmpty {
                            Button(action: { viewModel.clearAll() }) {
                                Text("Clear All")
                            }
                            .buttonStyle(DestructiveButtonStyle())
                        }
                    }

                    Button(action: { navigateToPainDetail = true }) {
                        HStack(spacing: AppSpacing.sm) {
                            Text("Continue")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(isDisabled: viewModel.selectedRegions.isEmpty))
                    .disabled(viewModel.selectedRegions.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("Body Map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToPainDetail) {
            PainDetailView(
                viewModel: InjuryAnalysisViewModel(
                    userProfile: viewModel.userProfile,
                    selectedRegions: viewModel.selectedRegions
                )
            )
        }
    }
}
