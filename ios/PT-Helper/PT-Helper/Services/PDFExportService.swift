import UIKit

/// Generates a professional PDF from a RehabPlan.
enum PDFExportService {

    private static let pageWidth: CGFloat = 612   // US Letter
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 50
    private static let contentWidth: CGFloat = 612 - 100 // pageWidth - 2 * margin

    /// Generate a PDF Data object for a rehab plan
    static func generatePDF(for plan: RehabPlan) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        return renderer.pdfData { context in
            // Page 1: Header + Schedule
            context.beginPage()
            var yOffset: CGFloat = margin

            yOffset = drawHeader(plan: plan, yOffset: yOffset, context: context)
            yOffset = drawConditions(plan: plan, yOffset: yOffset, context: context)
            yOffset = drawSchedule(plan: plan, yOffset: yOffset, context: context)

            // Exercises
            for (index, exercise) in plan.exercises.enumerated() {
                // Check if we need a new page (leave 200pt for each exercise)
                if yOffset > pageHeight - 200 {
                    context.beginPage()
                    yOffset = margin
                }

                yOffset = drawExercise(exercise, index: index, yOffset: yOffset, context: context)
            }

            // Footer on last page
            drawFooter(context: context)
        }
    }

    // MARK: - Drawing Functions

    private static func drawHeader(plan: RehabPlan, yOffset: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = yOffset

        // App branding
        let brandAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.systemBlue
        ]
        "COIL".draw(at: CGPoint(x: margin, y: y), withAttributes: brandAttrs)
        y += 20

        // Plan name
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.black
        ]
        plan.planName.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
        y += 35

        // Date + duration
        let infoAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.darkGray
        ]
        let dateStr = plan.createdDate.formatted(date: .abbreviated, time: .omitted)
        "Created: \(dateStr)  |  Duration: \(plan.totalWeeks) weeks  |  \(plan.exercises.count) exercises".draw(
            at: CGPoint(x: margin, y: y),
            withAttributes: infoAttrs
        )
        y += 20

        // Divider line
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        UIColor.systemGray4.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        y += 15

        return y
    }

    private static func drawConditions(plan: RehabPlan, yOffset: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        guard !plan.conditions.isEmpty else { return yOffset }
        var y = yOffset

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.darkGray
        ]
        "Conditions:".draw(at: CGPoint(x: margin, y: y), withAttributes: labelAttrs)

        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black
        ]
        plan.conditions.joined(separator: ", ").draw(at: CGPoint(x: margin + 80, y: y), withAttributes: valueAttrs)
        y += 20

        return y
    }

    private static func drawSchedule(plan: RehabPlan, yOffset: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = yOffset + 5

        let sectionAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        "Weekly Schedule".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
        y += 22

        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let cellWidth: CGFloat = contentWidth / 7

        let dayAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: UIColor.darkGray
        ]
        let countAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.systemBlue
        ]

        for (index, dayName) in dayNames.enumerated() {
            let x = margin + cellWidth * CGFloat(index) + cellWidth / 2 - 10
            dayName.draw(at: CGPoint(x: x, y: y), withAttributes: dayAttrs)

            let count = plan.weeklySchedule.indices.contains(index) ? plan.weeklySchedule[index].count : 0
            let countText = count > 0 ? "\(count) ex." : "-"
            countText.draw(at: CGPoint(x: x, y: y + 14), withAttributes: countAttrs)
        }
        y += 40

        return y
    }

    private static func drawExercise(_ exercise: RehabExercise, index: Int, yOffset: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        var y = yOffset

        // Exercise number + name
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.black
        ]
        "\(index + 1). \(exercise.name)".draw(at: CGPoint(x: margin, y: y), withAttributes: nameAttrs)
        y += 18

        // Target area + difficulty
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.darkGray
        ]
        "Target: \(exercise.targetArea)  |  \(exercise.sets) sets \u{00D7} \(exercise.reps)  |  Rest: \(exercise.restSeconds)s  |  \(exercise.difficulty.rawValue.capitalized)".draw(
            at: CGPoint(x: margin + 15, y: y),
            withAttributes: detailAttrs
        )
        y += 16

        // Description
        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray
        ]
        let descRect = CGRect(x: margin + 15, y: y, width: contentWidth - 15, height: 40)
        let descStr = NSAttributedString(string: exercise.description, attributes: descAttrs)
        descStr.draw(with: descRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        y += 40

        // Tips
        if !exercise.tips.isEmpty {
            let tipAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.systemOrange
            ]
            for tip in exercise.tips.prefix(2) {
                "\u{2022} \(tip)".draw(at: CGPoint(x: margin + 15, y: y), withAttributes: tipAttrs)
                y += 13
            }
        }

        y += 10
        return y
    }

    private static func drawFooter(context: UIGraphicsPDFRendererContext) {
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.lightGray
        ]
        let disclaimer = "Generated by COIL. This is for informational purposes only and does not constitute medical advice. Consult your healthcare provider."
        let footerRect = CGRect(x: margin, y: pageHeight - 40, width: contentWidth, height: 30)
        disclaimer.draw(with: footerRect, options: .usesLineFragmentOrigin, attributes: footerAttrs, context: nil)
    }
}
