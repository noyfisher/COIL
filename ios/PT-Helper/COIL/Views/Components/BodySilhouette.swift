import SwiftUI

// MARK: - Body Silhouette View

/// Draws a gender-specific human body silhouette using SwiftUI Path.
/// Supports male, female, and neutral body types with front/back views.
struct BodySilhouetteView: View {
    let sex: String
    let side: BodySide

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Body silhouette fill — adapts to dark mode
                bodyShape(for: sex, in: geometry.size)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.label).opacity(colorScheme == .dark ? 0.08 : 0.06),
                                Color(.label).opacity(colorScheme == .dark ? 0.15 : 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Body silhouette stroke
                bodyShape(for: sex, in: geometry.size)
                    .stroke(Color(.label).opacity(colorScheme == .dark ? 0.35 : 0.25), lineWidth: 1.5)

                // Back view spine line
                if side == .back {
                    spineLine(in: geometry.size)
                        .stroke(
                            Color(.label).opacity(colorScheme == .dark ? 0.20 : 0.15),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sex.isEmpty ? "Neutral" : sex) body silhouette, \(side == .front ? "front" : "back") view")
    }

    // MARK: - Shape Selection

    private func bodyShape(for sex: String, in size: CGSize) -> Path {
        switch sex {
        case "Male":
            return maleBodyPath(in: size)
        case "Female":
            return femaleBodyPath(in: size)
        default:
            return neutralBodyPath(in: size)
        }
    }

    // MARK: - Male Body Shape
    // Broader shoulders, narrower hips, straight torso

    private func maleBodyPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let cx = w * 0.5 // center x

        return Path { p in
            // Head (circle-ish)
            let headCY = h * 0.06
            let headR = w * 0.06
            p.addEllipse(in: CGRect(
                x: cx - headR, y: headCY - headR,
                width: headR * 2, height: headR * 2.2
            ))

            // Neck
            p.move(to: CGPoint(x: cx - w * 0.025, y: h * 0.10))
            p.addLine(to: CGPoint(x: cx - w * 0.025, y: h * 0.13))

            // Left shoulder/arm + torso + right arm (connected outline)
            p.move(to: CGPoint(x: cx, y: h * 0.115))

            // Neck to left shoulder
            p.addLine(to: CGPoint(x: cx - w * 0.03, y: h * 0.13))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.17, y: h * 0.175),
                control: CGPoint(x: cx - w * 0.14, y: h * 0.13)
            )

            // Left shoulder to left arm
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.20, y: h * 0.20),
                control: CGPoint(x: cx - w * 0.19, y: h * 0.18)
            )

            // Left upper arm
            p.addLine(to: CGPoint(x: cx - w * 0.22, y: h * 0.32))

            // Left elbow
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.23, y: h * 0.36),
                control: CGPoint(x: cx - w * 0.235, y: h * 0.34)
            )

            // Left forearm
            p.addLine(to: CGPoint(x: cx - w * 0.24, y: h * 0.48))

            // Left hand
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.22, y: h * 0.52),
                control: CGPoint(x: cx - w * 0.25, y: h * 0.51)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.20, y: h * 0.48),
                control: CGPoint(x: cx - w * 0.21, y: h * 0.51)
            )

            // Left inner forearm back up
            p.addLine(to: CGPoint(x: cx - w * 0.19, y: h * 0.36))

            // Left inner elbow
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.18, y: h * 0.32),
                control: CGPoint(x: cx - w * 0.185, y: h * 0.34)
            )

            // Left inner upper arm back to torso
            p.addLine(to: CGPoint(x: cx - w * 0.16, y: h * 0.22))

            // Left torso (straight for male)
            p.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.35))
            p.addLine(to: CGPoint(x: cx - w * 0.13, y: h * 0.45))

            // Left hip
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.13, y: h * 0.52),
                control: CGPoint(x: cx - w * 0.14, y: h * 0.49)
            )

            // Left groin / inner thigh split
            p.addLine(to: CGPoint(x: cx - w * 0.12, y: h * 0.55))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.04, y: h * 0.58),
                control: CGPoint(x: cx - w * 0.08, y: h * 0.58)
            )

            // Left inner thigh
            p.addLine(to: CGPoint(x: cx - w * 0.05, y: h * 0.68))

            // Left inner knee
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.045, y: h * 0.72),
                control: CGPoint(x: cx - w * 0.04, y: h * 0.70)
            )

            // Left inner calf
            p.addLine(to: CGPoint(x: cx - w * 0.04, y: h * 0.85))

            // Left ankle
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.06, y: h * 0.91),
                control: CGPoint(x: cx - w * 0.035, y: h * 0.89)
            )

            // Left foot
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.10, y: h * 0.94),
                control: CGPoint(x: cx - w * 0.09, y: h * 0.91)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.08, y: h * 0.96),
                control: CGPoint(x: cx - w * 0.11, y: h * 0.96)
            )
            p.addLine(to: CGPoint(x: cx - w * 0.03, y: h * 0.96))

            // Left outer ankle
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.06, y: h * 0.88),
                control: CGPoint(x: cx - w * 0.04, y: h * 0.93)
            )

            // Left outer calf
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.08, y: h * 0.76),
                control: CGPoint(x: cx - w * 0.09, y: h * 0.82)
            )

            // Left outer knee
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.09, y: h * 0.70),
                control: CGPoint(x: cx - w * 0.09, y: h * 0.73)
            )

            // Left outer thigh
            p.addLine(to: CGPoint(x: cx - w * 0.13, y: h * 0.58))

            // --- Right side (mirror) ---

            // Right inner thigh split
            p.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.58))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.12, y: h * 0.55),
                control: CGPoint(x: cx + w * 0.08, y: h * 0.58)
            )

            // Right hip
            p.addLine(to: CGPoint(x: cx + w * 0.13, y: h * 0.52))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.13, y: h * 0.45),
                control: CGPoint(x: cx + w * 0.14, y: h * 0.49)
            )

            // Right torso (straight)
            p.addLine(to: CGPoint(x: cx + w * 0.14, y: h * 0.35))
            p.addLine(to: CGPoint(x: cx + w * 0.16, y: h * 0.22))

            // Right inner upper arm
            p.addLine(to: CGPoint(x: cx + w * 0.18, y: h * 0.32))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.19, y: h * 0.36),
                control: CGPoint(x: cx + w * 0.185, y: h * 0.34)
            )

            // Right inner forearm
            p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.48))

            // Right hand
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.22, y: h * 0.52),
                control: CGPoint(x: cx + w * 0.21, y: h * 0.51)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.24, y: h * 0.48),
                control: CGPoint(x: cx + w * 0.25, y: h * 0.51)
            )

            // Right outer forearm
            p.addLine(to: CGPoint(x: cx + w * 0.23, y: h * 0.36))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.22, y: h * 0.32),
                control: CGPoint(x: cx + w * 0.235, y: h * 0.34)
            )

            // Right outer upper arm
            p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.20))

            // Right shoulder
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.17, y: h * 0.175),
                control: CGPoint(x: cx + w * 0.19, y: h * 0.18)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.03, y: h * 0.13),
                control: CGPoint(x: cx + w * 0.14, y: h * 0.13)
            )

            // Back to neck
            p.addLine(to: CGPoint(x: cx, y: h * 0.115))

            // Right leg
            p.move(to: CGPoint(x: cx + w * 0.13, y: h * 0.58))

            // Right outer thigh
            p.addLine(to: CGPoint(x: cx + w * 0.09, y: h * 0.70))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.08, y: h * 0.76),
                control: CGPoint(x: cx + w * 0.09, y: h * 0.73)
            )

            // Right outer calf
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.06, y: h * 0.88),
                control: CGPoint(x: cx + w * 0.09, y: h * 0.82)
            )

            // Right outer ankle
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.03, y: h * 0.96),
                control: CGPoint(x: cx + w * 0.04, y: h * 0.93)
            )

            // Right foot
            p.addLine(to: CGPoint(x: cx + w * 0.08, y: h * 0.96))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.10, y: h * 0.94),
                control: CGPoint(x: cx + w * 0.11, y: h * 0.96)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.06, y: h * 0.91),
                control: CGPoint(x: cx + w * 0.09, y: h * 0.91)
            )

            // Right inner ankle
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.04, y: h * 0.85),
                control: CGPoint(x: cx + w * 0.035, y: h * 0.89)
            )

            // Right inner calf
            p.addLine(to: CGPoint(x: cx + w * 0.045, y: h * 0.72))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.05, y: h * 0.68),
                control: CGPoint(x: cx + w * 0.04, y: h * 0.70)
            )

            // Right inner thigh
            p.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.58))
        }
    }

    // MARK: - Female Body Shape
    // Narrower shoulders, wider hips, tapered waist, slightly curvier

    private func femaleBodyPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let cx = w * 0.5

        return Path { p in
            // Head
            let headCY = h * 0.06
            let headR = w * 0.055
            p.addEllipse(in: CGRect(
                x: cx - headR, y: headCY - headR,
                width: headR * 2, height: headR * 2.2
            ))

            // Body outline
            p.move(to: CGPoint(x: cx, y: h * 0.115))

            // Neck to left shoulder (narrower)
            p.addLine(to: CGPoint(x: cx - w * 0.03, y: h * 0.13))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.14, y: h * 0.18),
                control: CGPoint(x: cx - w * 0.11, y: h * 0.13)
            )

            // Left shoulder to left arm
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.17, y: h * 0.21),
                control: CGPoint(x: cx - w * 0.16, y: h * 0.19)
            )

            // Left upper arm
            p.addLine(to: CGPoint(x: cx - w * 0.19, y: h * 0.32))

            // Left elbow
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.20, y: h * 0.36),
                control: CGPoint(x: cx - w * 0.205, y: h * 0.34)
            )

            // Left forearm
            p.addLine(to: CGPoint(x: cx - w * 0.21, y: h * 0.48))

            // Left hand
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.19, y: h * 0.52),
                control: CGPoint(x: cx - w * 0.22, y: h * 0.51)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.17, y: h * 0.48),
                control: CGPoint(x: cx - w * 0.18, y: h * 0.51)
            )

            // Left inner forearm
            p.addLine(to: CGPoint(x: cx - w * 0.16, y: h * 0.36))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.15, y: h * 0.32),
                control: CGPoint(x: cx - w * 0.155, y: h * 0.34)
            )

            // Left inner upper arm back to torso
            p.addLine(to: CGPoint(x: cx - w * 0.13, y: h * 0.22))

            // Left torso — waist taper (female)
            p.addLine(to: CGPoint(x: cx - w * 0.12, y: h * 0.30))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.10, y: h * 0.40),
                control: CGPoint(x: cx - w * 0.10, y: h * 0.35)
            )

            // Left waist to hip (wider)
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.15, y: h * 0.52),
                control: CGPoint(x: cx - w * 0.16, y: h * 0.46)
            )

            // Left hip
            p.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.55))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.04, y: h * 0.59),
                control: CGPoint(x: cx - w * 0.09, y: h * 0.59)
            )

            // Left inner thigh
            p.addLine(to: CGPoint(x: cx - w * 0.05, y: h * 0.69))

            // Left inner knee
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.04, y: h * 0.73),
                control: CGPoint(x: cx - w * 0.035, y: h * 0.71)
            )

            // Left inner calf
            p.addLine(to: CGPoint(x: cx - w * 0.035, y: h * 0.86))

            // Left ankle
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.05, y: h * 0.91),
                control: CGPoint(x: cx - w * 0.03, y: h * 0.89)
            )

            // Left foot
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.09, y: h * 0.94),
                control: CGPoint(x: cx - w * 0.08, y: h * 0.91)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.07, y: h * 0.96),
                control: CGPoint(x: cx - w * 0.10, y: h * 0.96)
            )
            p.addLine(to: CGPoint(x: cx - w * 0.025, y: h * 0.96))

            // Left outer ankle
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.05, y: h * 0.88),
                control: CGPoint(x: cx - w * 0.03, y: h * 0.93)
            )

            // Left outer calf
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.07, y: h * 0.76),
                control: CGPoint(x: cx - w * 0.08, y: h * 0.82)
            )

            // Left outer knee
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.08, y: h * 0.70),
                control: CGPoint(x: cx - w * 0.08, y: h * 0.73)
            )

            // Left outer thigh
            p.addLine(to: CGPoint(x: cx - w * 0.14, y: h * 0.58))

            // --- Right side (mirror) ---

            p.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.59))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.14, y: h * 0.55),
                control: CGPoint(x: cx + w * 0.09, y: h * 0.59)
            )

            p.addLine(to: CGPoint(x: cx + w * 0.15, y: h * 0.52))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.10, y: h * 0.40),
                control: CGPoint(x: cx + w * 0.16, y: h * 0.46)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.12, y: h * 0.30),
                control: CGPoint(x: cx + w * 0.10, y: h * 0.35)
            )

            p.addLine(to: CGPoint(x: cx + w * 0.13, y: h * 0.22))
            p.addLine(to: CGPoint(x: cx + w * 0.15, y: h * 0.32))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.16, y: h * 0.36),
                control: CGPoint(x: cx + w * 0.155, y: h * 0.34)
            )

            p.addLine(to: CGPoint(x: cx + w * 0.17, y: h * 0.48))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.19, y: h * 0.52),
                control: CGPoint(x: cx + w * 0.18, y: h * 0.51)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.21, y: h * 0.48),
                control: CGPoint(x: cx + w * 0.22, y: h * 0.51)
            )

            p.addLine(to: CGPoint(x: cx + w * 0.20, y: h * 0.36))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.19, y: h * 0.32),
                control: CGPoint(x: cx + w * 0.205, y: h * 0.34)
            )

            p.addLine(to: CGPoint(x: cx + w * 0.17, y: h * 0.21))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.14, y: h * 0.18),
                control: CGPoint(x: cx + w * 0.16, y: h * 0.19)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.03, y: h * 0.13),
                control: CGPoint(x: cx + w * 0.11, y: h * 0.13)
            )
            p.addLine(to: CGPoint(x: cx, y: h * 0.115))

            // Right leg
            p.move(to: CGPoint(x: cx + w * 0.14, y: h * 0.58))
            p.addLine(to: CGPoint(x: cx + w * 0.08, y: h * 0.70))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.07, y: h * 0.76),
                control: CGPoint(x: cx + w * 0.08, y: h * 0.73)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.05, y: h * 0.88),
                control: CGPoint(x: cx + w * 0.08, y: h * 0.82)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.025, y: h * 0.96),
                control: CGPoint(x: cx + w * 0.03, y: h * 0.93)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.07, y: h * 0.96))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.09, y: h * 0.94),
                control: CGPoint(x: cx + w * 0.10, y: h * 0.96)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.05, y: h * 0.91),
                control: CGPoint(x: cx + w * 0.08, y: h * 0.91)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.035, y: h * 0.86),
                control: CGPoint(x: cx + w * 0.03, y: h * 0.89)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.73))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.05, y: h * 0.69),
                control: CGPoint(x: cx + w * 0.035, y: h * 0.71)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.59))
        }
    }

    // MARK: - Neutral Body Shape
    // Midpoint between male and female proportions

    private func neutralBodyPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let cx = w * 0.5

        return Path { p in
            // Head
            let headCY = h * 0.06
            let headR = w * 0.058
            p.addEllipse(in: CGRect(
                x: cx - headR, y: headCY - headR,
                width: headR * 2, height: headR * 2.2
            ))

            // Body outline
            p.move(to: CGPoint(x: cx, y: h * 0.115))

            // Neck to left shoulder (medium width)
            p.addLine(to: CGPoint(x: cx - w * 0.03, y: h * 0.13))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.155, y: h * 0.178),
                control: CGPoint(x: cx - w * 0.125, y: h * 0.13)
            )

            // Left shoulder
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.185, y: h * 0.205),
                control: CGPoint(x: cx - w * 0.175, y: h * 0.185)
            )

            // Left upper arm
            p.addLine(to: CGPoint(x: cx - w * 0.205, y: h * 0.32))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.215, y: h * 0.36),
                control: CGPoint(x: cx - w * 0.22, y: h * 0.34)
            )

            // Left forearm
            p.addLine(to: CGPoint(x: cx - w * 0.225, y: h * 0.48))

            // Left hand
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.205, y: h * 0.52),
                control: CGPoint(x: cx - w * 0.235, y: h * 0.51)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.185, y: h * 0.48),
                control: CGPoint(x: cx - w * 0.195, y: h * 0.51)
            )

            // Left inner arm back up
            p.addLine(to: CGPoint(x: cx - w * 0.175, y: h * 0.36))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.165, y: h * 0.32),
                control: CGPoint(x: cx - w * 0.17, y: h * 0.34)
            )
            p.addLine(to: CGPoint(x: cx - w * 0.145, y: h * 0.22))

            // Left torso (slight waist taper)
            p.addLine(to: CGPoint(x: cx - w * 0.13, y: h * 0.32))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.12, y: h * 0.42),
                control: CGPoint(x: cx - w * 0.12, y: h * 0.37)
            )

            // Left hip
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.135, y: h * 0.53),
                control: CGPoint(x: cx - w * 0.14, y: h * 0.48)
            )
            p.addLine(to: CGPoint(x: cx - w * 0.13, y: h * 0.56))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.04, y: h * 0.585),
                control: CGPoint(x: cx - w * 0.085, y: h * 0.585)
            )

            // Left inner thigh
            p.addLine(to: CGPoint(x: cx - w * 0.05, y: h * 0.685))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.042, y: h * 0.725),
                control: CGPoint(x: cx - w * 0.037, y: h * 0.705)
            )

            // Left inner calf
            p.addLine(to: CGPoint(x: cx - w * 0.037, y: h * 0.855))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.055, y: h * 0.91),
                control: CGPoint(x: cx - w * 0.032, y: h * 0.89)
            )

            // Left foot
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.095, y: h * 0.94),
                control: CGPoint(x: cx - w * 0.085, y: h * 0.91)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.075, y: h * 0.96),
                control: CGPoint(x: cx - w * 0.105, y: h * 0.96)
            )
            p.addLine(to: CGPoint(x: cx - w * 0.028, y: h * 0.96))
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.055, y: h * 0.88),
                control: CGPoint(x: cx - w * 0.035, y: h * 0.93)
            )

            // Left outer calf
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.075, y: h * 0.76),
                control: CGPoint(x: cx - w * 0.085, y: h * 0.82)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx - w * 0.085, y: h * 0.70),
                control: CGPoint(x: cx - w * 0.085, y: h * 0.73)
            )

            // Left outer thigh
            p.addLine(to: CGPoint(x: cx - w * 0.135, y: h * 0.58))

            // --- Right side (mirror) ---
            p.move(to: CGPoint(x: cx + w * 0.04, y: h * 0.585))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.13, y: h * 0.56),
                control: CGPoint(x: cx + w * 0.085, y: h * 0.585)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.135, y: h * 0.53))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.12, y: h * 0.42),
                control: CGPoint(x: cx + w * 0.14, y: h * 0.48)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.13, y: h * 0.32),
                control: CGPoint(x: cx + w * 0.12, y: h * 0.37)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.145, y: h * 0.22))
            p.addLine(to: CGPoint(x: cx + w * 0.165, y: h * 0.32))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.175, y: h * 0.36),
                control: CGPoint(x: cx + w * 0.17, y: h * 0.34)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.185, y: h * 0.48))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.205, y: h * 0.52),
                control: CGPoint(x: cx + w * 0.195, y: h * 0.51)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.225, y: h * 0.48),
                control: CGPoint(x: cx + w * 0.235, y: h * 0.51)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.215, y: h * 0.36))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.205, y: h * 0.32),
                control: CGPoint(x: cx + w * 0.22, y: h * 0.34)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.185, y: h * 0.205))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.155, y: h * 0.178),
                control: CGPoint(x: cx + w * 0.175, y: h * 0.185)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.03, y: h * 0.13),
                control: CGPoint(x: cx + w * 0.125, y: h * 0.13)
            )
            p.addLine(to: CGPoint(x: cx, y: h * 0.115))

            // Right leg
            p.move(to: CGPoint(x: cx + w * 0.135, y: h * 0.58))
            p.addLine(to: CGPoint(x: cx + w * 0.085, y: h * 0.70))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.075, y: h * 0.76),
                control: CGPoint(x: cx + w * 0.085, y: h * 0.73)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.055, y: h * 0.88),
                control: CGPoint(x: cx + w * 0.085, y: h * 0.82)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.028, y: h * 0.96),
                control: CGPoint(x: cx + w * 0.035, y: h * 0.93)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.075, y: h * 0.96))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.095, y: h * 0.94),
                control: CGPoint(x: cx + w * 0.105, y: h * 0.96)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.055, y: h * 0.91),
                control: CGPoint(x: cx + w * 0.085, y: h * 0.91)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.037, y: h * 0.855),
                control: CGPoint(x: cx + w * 0.032, y: h * 0.89)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.042, y: h * 0.725))
            p.addQuadCurve(
                to: CGPoint(x: cx + w * 0.05, y: h * 0.685),
                control: CGPoint(x: cx + w * 0.037, y: h * 0.705)
            )
            p.addLine(to: CGPoint(x: cx + w * 0.04, y: h * 0.585))
        }
    }

    // MARK: - Spine Line (Back View)

    private func spineLine(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let cx = w * 0.5

        return Path { p in
            p.move(to: CGPoint(x: cx, y: h * 0.12))
            p.addQuadCurve(
                to: CGPoint(x: cx, y: h * 0.30),
                control: CGPoint(x: cx + w * 0.005, y: h * 0.21)
            )
            p.addQuadCurve(
                to: CGPoint(x: cx, y: h * 0.50),
                control: CGPoint(x: cx - w * 0.005, y: h * 0.40)
            )
        }
    }
}
