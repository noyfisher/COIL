import SwiftUI

// MARK: - Container

struct IntroCarouselView: View {
    var onComplete: () -> Void
    @State private var page: Int = 0

    var body: some View {
        TabView(selection: $page) {
            IntroPrecisionRecovery(onSkip: onComplete)
                .tag(0)
            IntroFastTrack(onSkip: onComplete)
                .tag(1)
            IntroStartJourney(onStart: onComplete)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // No .ignoresSafeArea() here: it zeroes geo.safeAreaInsets inside the
        // pages, collapsing their status-bar spacers and pushing the nav bar
        // (incl. the xmark close button) under the status bar (F6). Page
        // backgrounds ignore the safe area themselves, so the bleed is kept.
        .trackScreen("IntroCarousel")
    }
}

// MARK: - Shared nav bar

private struct IntroNavBar: View {
    var showX: Bool = false
    var onSkip: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("MVVC")
                    .font(Font.custom("BarlowCondensed-Black", size: 24))
                    .italic()
                    .foregroundColor(AppColors.accent)
                Spacer()
                if showX {
                    Button(action: onSkip) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                } else {
                    Button(action: onSkip) {
                        Text("SKIP")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)

            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
        }
    }
}

// MARK: - Shared swipe indicator

private struct SwipeIndicator: View {
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 6) {
            Text("SWIPE")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.28))
                .kerning(1.5)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.28))
        }
        .offset(x: offset)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 0.9)
                .repeatForever(autoreverses: true)
            ) {
                offset = 7
            }
        }
    }
}

// MARK: - Page 1: Precision Recovery

private struct IntroPrecisionRecovery: View {
    var onSkip: () -> Void

    var body: some View {
        GeometryReader { geo in
            let heroH = geo.size.height * 0.50

            ZStack(alignment: .top) {
                Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Safe area spacer
                    Color.clear.frame(height: geo.safeAreaInsets.top)

                    IntroNavBar(showX: true, onSkip: onSkip)

                    // Hero image area
                    ZStack {
                        // Deep red radial background filling the hero zone
                        RadialGradient(
                            colors: [
                                Color(red: 0.35, green: 0.02, blue: 0.02),
                                Color(red: 0.13, green: 0.02, blue: 0.02),
                                Color(red: 0.067, green: 0.067, blue: 0.067)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: heroH * 0.72
                        )

                        BodySkeletonView()
                            .frame(width: heroH * 0.44, height: heroH * 0.80)
                    }
                    .frame(height: heroH)

                    // Content divider
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)

                    // Content block
                    VStack(alignment: .leading, spacing: 0) {
                        // AI engine chip
                        HStack(spacing: 7) {
                            Circle()
                                .fill(AppColors.accent)
                                .frame(width: 7, height: 7)
                            Text("AI ENGINE ACTIVE")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                                .kerning(0.8)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                        .padding(.top, 20)

                        // Headline
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PRECISION")
                                .font(Font.custom("BarlowCondensed-Black", size: 28))
                                .italic()
                                .foregroundColor(.white)
                            Text("RECOVERY")
                                .font(Font.custom("BarlowCondensed-Black", size: 28))
                                .italic()
                                .foregroundColor(AppColors.accent)
                        }
                        .padding(.top, 14)

                        // Body text
                        Text("Our AI analyzes your form in real-time to prevent injury and optimize recovery. Professional-grade physical therapy in the palm of your hand.")
                            .font(Font.custom("Inter-Regular", size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 12)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 0)

                    // Bottom: progress + swipe indicator
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 0.5)

                        HStack(alignment: .center) {
                            // 3-segment progress bar
                            HStack(spacing: 5) {
                                ForEach(0..<3) { i in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(i == 0 ? AppColors.accent : Color.white.opacity(0.22))
                                        .frame(width: i == 0 ? 36 : 28, height: 4)
                                }
                            }
                            Spacer()
                            Text("01 / 03")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                                .kerning(0.5)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                        SwipeIndicator()
                            .padding(.top, 16)
                            .padding(.bottom, geo.safeAreaInsets.bottom + 20)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page 2: Fast Track

private struct IntroFastTrack: View {
    var onSkip: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea()

                // Corner red glows
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.18), Color.clear],
                    center: .topTrailing, startRadius: 0, endRadius: 260
                )
                .ignoresSafeArea()
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.07), Color.clear],
                    center: .bottomLeading, startRadius: 0, endRadius: 200
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    Color.clear.frame(height: geo.safeAreaInsets.top)

                    IntroNavBar(showX: false, onSkip: onSkip)

                    // Empty top breathing room (~30% of remaining height)
                    Spacer()
                        .frame(height: (geo.size.height - geo.safeAreaInsets.top - 52) * 0.28)

                    // Hero text block
                    VStack(spacing: 0) {
                        Text("FAST TRACK\nTO PERFORMANCE")
                            .font(Font.custom("BarlowCondensed-Black", size: 38))
                            .italic()
                            .multilineTextAlignment(.center)
                            .foregroundColor(AppColors.accent)
                            .lineSpacing(0)
                            .fixedSize(horizontal: false, vertical: true)

                        // Red rule
                        Rectangle()
                            .fill(AppColors.accent)
                            .frame(width: 80, height: 3)
                            .padding(.top, 16)

                        Text("MVVC uses professional-grade protocols to accelerate your body's natural healing process. We help you stay active, prevent injury, and return to performance faster.")
                            .font(Font.custom("Inter-Regular", size: 15))
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                            .padding(.horizontal, 32)
                            .padding(.top, 20)
                    }

                    Spacer()

                    // Swipe indicator pinned to bottom
                    SwipeIndicator()
                        .padding(.bottom, geo.safeAreaInsets.bottom + 28)
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Page 3: Start Your Journey

private struct IntroStartJourney: View {
    var onStart: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color(red: 0.067, green: 0.067, blue: 0.067).ignoresSafeArea()

                // Ambient corner glows
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.14), Color.clear],
                    center: .topLeading, startRadius: 0, endRadius: 240
                )
                .ignoresSafeArea()
                RadialGradient(
                    colors: [AppColors.accent.opacity(0.08), Color.clear],
                    center: .bottomTrailing, startRadius: 0, endRadius: 200
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Space: 38% of screen to center content slightly above mid
                    Spacer()
                        .frame(height: geo.size.height * 0.33)

                    // Progress dashes
                    HStack(spacing: 10) {
                        ForEach(0..<3) { i in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 2 ? AppColors.accent : Color.white.opacity(0.22))
                                .frame(
                                    width: i == 2 ? 28 : 20,
                                    height: 5
                                )
                                .shadow(
                                    color: i == 2 ? AppColors.accent.opacity(0.55) : .clear,
                                    radius: 6
                                )
                        }
                    }

                    // Headline
                    Text("START YOUR\nJOURNEY")
                        .font(Font.custom("BarlowCondensed-Black", size: 52))
                        .italic()
                        .multilineTextAlignment(.center)
                        .foregroundColor(AppColors.accent)
                        .lineSpacing(0)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)

                    // Body text
                    Text("Set your goals and let MVVC handle the rest. Your path to peak performance starts here.")
                        .font(Font.custom("Inter-Regular", size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, 40)
                        .padding(.top, 16)

                    Spacer()

                    // Bottom shell
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 0.5)

                        Button(action: onStart) {
                            Text("LET'S GO")
                                .font(Font.custom("BarlowCondensed-Black", size: 20))
                                .italic()
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(AppColors.accent)
                                .cornerRadius(14)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        HStack(spacing: 8) {
                            Text("PHASE 03")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.35))
                                .kerning(0.5)
                            Circle()
                                .fill(Color.white.opacity(0.25))
                                .frame(width: 3, height: 3)
                            Text("READY TO MOVE")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(AppColors.accent.opacity(0.85))
                                .kerning(0.5)
                        }
                        .padding(.top, 14)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Body Skeleton View

private struct BodySkeletonView: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Soft glow behind figure
                Ellipse()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: w * 1.1, height: h * 0.7)
                    .blur(radius: 28)
                    .offset(y: -h * 0.05)

                // Dark silhouette fill
                Image(systemName: "figure.stand")
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(Color(red: 0.15, green: 0.04, blue: 0.04).opacity(0.9))

                // Skeleton lines
                SkeletonLines(w: w, h: h)
                    .stroke(
                        AppColors.accent.opacity(0.9),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                // Joint nodes
                SkeletonJoints(w: w, h: h)
                    .fill(AppColors.accent)
            }
        }
    }
}

private struct SkeletonLines: Shape {
    let w: CGFloat
    let h: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Head to chest
        p.move(to:    .init(x: w * 0.50, y: h * 0.12))
        p.addLine(to: .init(x: w * 0.50, y: h * 0.34))
        // Shoulder bar
        p.move(to:    .init(x: w * 0.23, y: h * 0.22))
        p.addLine(to: .init(x: w * 0.77, y: h * 0.22))
        // Left arm: shoulder → elbow → wrist
        p.move(to:    .init(x: w * 0.23, y: h * 0.22))
        p.addLine(to: .init(x: w * 0.13, y: h * 0.41))
        p.addLine(to: .init(x: w * 0.17, y: h * 0.57))
        // Right arm
        p.move(to:    .init(x: w * 0.77, y: h * 0.22))
        p.addLine(to: .init(x: w * 0.87, y: h * 0.41))
        p.addLine(to: .init(x: w * 0.83, y: h * 0.57))
        // Spine to pelvis
        p.move(to:    .init(x: w * 0.50, y: h * 0.34))
        p.addLine(to: .init(x: w * 0.50, y: h * 0.54))
        // Hip bar
        p.move(to:    .init(x: w * 0.33, y: h * 0.54))
        p.addLine(to: .init(x: w * 0.67, y: h * 0.54))
        // Left leg: hip → knee → ankle
        p.move(to:    .init(x: w * 0.33, y: h * 0.54))
        p.addLine(to: .init(x: w * 0.29, y: h * 0.74))
        p.addLine(to: .init(x: w * 0.31, y: h * 0.95))
        // Right leg
        p.move(to:    .init(x: w * 0.67, y: h * 0.54))
        p.addLine(to: .init(x: w * 0.71, y: h * 0.74))
        p.addLine(to: .init(x: w * 0.69, y: h * 0.95))
        return p
    }
}

private struct SkeletonJoints: Shape {
    let w: CGFloat
    let h: CGFloat
    private let r: CGFloat = 3.5

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let joints: [(CGFloat, CGFloat)] = [
            (0.50, 0.11),  // head
            (0.50, 0.22),  // neck/chest
            (0.23, 0.22),  // l-shoulder
            (0.77, 0.22),  // r-shoulder
            (0.50, 0.34),  // sternum
            (0.13, 0.41),  // l-elbow
            (0.87, 0.41),  // r-elbow
            (0.17, 0.57),  // l-wrist
            (0.83, 0.57),  // r-wrist
            (0.50, 0.54),  // pelvis
            (0.33, 0.54),  // l-hip
            (0.67, 0.54),  // r-hip
            (0.29, 0.74),  // l-knee
            (0.71, 0.74),  // r-knee
            (0.31, 0.95),  // l-ankle
            (0.69, 0.95),  // r-ankle
        ]
        for (fx, fy) in joints {
            p.addEllipse(in: CGRect(x: w * fx - r, y: h * fy - r, width: r * 2, height: r * 2))
        }
        return p
    }
}
