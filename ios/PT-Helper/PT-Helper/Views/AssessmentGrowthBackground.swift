import SwiftUI

// Pointed-oval leaf shape: tapers to a tip at top and bottom, bulges at the middle.
private struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let mx = rect.midX
        // control-point bulge — wider = more ovate, smaller = more narrow/willow-like
        let bulge = w * 0.52
        var p = Path()
        // start at top tip
        p.move(to: CGPoint(x: mx, y: 0))
        // right side curve to bottom tip
        p.addCurve(
            to: CGPoint(x: mx, y: h),
            control1: CGPoint(x: mx + bulge, y: h * 0.25),
            control2: CGPoint(x: mx + bulge, y: h * 0.75)
        )
        // left side curve back to top tip
        p.addCurve(
            to: CGPoint(x: mx, y: 0),
            control1: CGPoint(x: mx - bulge, y: h * 0.75),
            control2: CGPoint(x: mx - bulge, y: h * 0.25)
        )
        p.closeSubpath()
        return p
    }
}

// Scattered leaf shapes that shuffle to new positions on every step change.
struct AssessmentGrowthBackground: View {
    let step: Int

    private struct Leaf: Identifiable {
        let id: Int
        var x: CGFloat       // normalized 0–1
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var rotation: Double
        var colorIndex: Int
        var opacity: Double
    }

    private static let palette: [Color] = [
        Color(red: 0.28, green: 0.46, blue: 0.25),
        Color(red: 0.38, green: 0.58, blue: 0.34),
        Color(red: 0.47, green: 0.67, blue: 0.43),
        Color(red: 0.55, green: 0.72, blue: 0.48),
        Color(red: 0.62, green: 0.76, blue: 0.54),
        Color(red: 0.34, green: 0.52, blue: 0.31),
        Color(red: 0.70, green: 0.82, blue: 0.60),
    ]

    private static let bgTop    = Color(red: 0.949, green: 0.961, blue: 0.933)
    private static let bgBottom = Color(red: 0.867, green: 0.898, blue: 0.831)
    private static let leafCount = 18

    @State private var leaves: [Leaf] = []

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Self.bgTop, Self.bgBottom],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                ForEach(leaves) { leaf in
                    LeafShape()
                        .fill(Self.palette[leaf.colorIndex])
                        .frame(width: leaf.width, height: leaf.height)
                        .rotationEffect(.degrees(leaf.rotation))
                        .position(
                            x: leaf.x * geo.size.width,
                            y: leaf.y * geo.size.height
                        )
                        .opacity(leaf.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { scatter(animated: false) }
        .onChange(of: step) { _, _ in scatter(animated: true) }
    }

    private func scatter(animated: Bool) {
        var updated: [Leaf] = leaves

        // Seed with stable IDs so SwiftUI can animate existing leaves to new positions
        if updated.isEmpty {
            updated = (0..<Self.leafCount).map { i in
                Leaf(
                    id: i,
                    x: .random(in: 0.04...0.96),
                    y: .random(in: 0.04...0.96),
                    width: .random(in: 18...40),
                    height: .random(in: 30...64),
                    rotation: .random(in: -65...65),
                    colorIndex: Int.random(in: 0..<Self.palette.count),
                    opacity: .random(in: 0.20...0.45)
                )
            }
        } else {
            updated = updated.map { leaf in
                Leaf(
                    id: leaf.id,
                    x: .random(in: 0.04...0.96),
                    y: .random(in: 0.04...0.96),
                    width: .random(in: 18...40),
                    height: .random(in: 30...64),
                    rotation: .random(in: -65...65),
                    colorIndex: Int.random(in: 0..<Self.palette.count),
                    opacity: .random(in: 0.20...0.45)
                )
            }
        }

        if animated {
            withAnimation(.spring(duration: 0.70, bounce: 0.28)) {
                leaves = updated
            }
        } else {
            leaves = updated
        }
    }
}
