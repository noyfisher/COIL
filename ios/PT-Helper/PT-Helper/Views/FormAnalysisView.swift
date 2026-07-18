import SwiftUI

/// Main form analysis flow — handles recording, processing, and displaying feedback.
/// Can be presented from GuidedWorkoutView (exercise pre-selected) or standalone (exercise picker).
struct FormAnalysisView: View {
    @StateObject private var vm: FormAnalysisViewModel
    @Environment(\.dismiss) private var dismiss

    let exercise: RehabExercise
    @State private var showCamera = false

    init(exercise: RehabExercise, apiService: ClaudeAPIServiceProtocol = ClaudeAPIService.shared) {
        self.exercise = exercise
        _vm = StateObject(wrappedValue: FormAnalysisViewModel(apiService: apiService))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                switch vm.state {
                case .idle:
                    readyToRecordView
                case .recording:
                    // Camera sheet handles this
                    recordingPlaceholder
                case .processing:
                    processingView
                case .analyzing:
                    analyzingView
                case .complete(let validated):
                    feedbackResultView(validated.feedback, validation: validated.validation, dataQuality: validated.dataQuality)
                case .error(let message):
                    errorView(message)
                }
            }
            .navigationTitle("Form Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                VideoRecorderView { videoURL in
                    Task {
                        await vm.analyzeVideo(url: videoURL, exercise: exercise)
                    }
                }
            }
            .trackScreen("FormAnalysis")
        }
    }

    // MARK: - Ready to Record

    private var readyToRecordView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                Spacer().frame(height: AppSpacing.lg)

                // Exercise info
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "figure.mixed.cardio")
                        .font(.system(size: 50))
                        .foregroundStyle(AppColors.accent)

                    Text(exercise.name)
                        .font(AppFonts.title)

                    Text("Record yourself performing this exercise and get AI-powered form feedback.")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                }

                // Tips card
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Label("Recording Tips", systemImage: "lightbulb.fill")
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.warning)

                    tipRow(icon: "person.fill", text: "Ensure your full body is visible in frame")
                    tipRow(icon: "camera.fill", text: "Prop your phone up at a stable angle")
                    tipRow(icon: "sun.max.fill", text: "Use good lighting for best results")
                    tipRow(icon: "timer", text: "Record 1–2 sets (up to 30 seconds)")
                }
                .padding(AppSpacing.lg)
                .background(AppColors.cardBackground)
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                // Record button
                Button(action: { showCamera = true }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "video.fill")
                        Text("Record Exercise")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("formAnalysis.recordButton")

                Spacer()
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }

    // MARK: - Recording Placeholder

    private var recordingPlaceholder: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Recording...")
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.secondaryText)
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(AppColors.accent.opacity(0.15), lineWidth: 8)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: vm.processingProgress)
                    .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.3), value: vm.processingProgress)

                VStack(spacing: AppSpacing.xs) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 36))
                        .foregroundColor(AppColors.accent)
                        .symbolEffect(.pulse)

                    Text("\(Int(vm.processingProgress * 100))%")
                        .font(AppFonts.sectionTitle)
                        .foregroundColor(AppColors.accent)
                }
            }

            VStack(spacing: AppSpacing.sm) {
                Text("Analyzing Your Form")
                    .font(AppFonts.sectionTitle)

                Text("Detecting body pose and computing joint angles...")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Analyzing View (AI Call)

    private var analyzingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            VStack(spacing: AppSpacing.sm) {
                Text("Getting AI Feedback")
                    .font(AppFonts.sectionTitle)

                Text("Our AI is reviewing your form metrics...")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Feedback Result

    private func feedbackResultView(_ feedback: FormFeedback, validation: FormValidationResult, dataQuality: DataQualityReport) -> some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                // Score badge with confidence indicator
                scoreHeader(feedback, confidenceLevel: validation.confidenceLevel)

                // Honest framing of what the score is — a coaching aid, not a
                // diagnosis — so users don't over-read a big number (audit #91).
                Text("This score estimates your technique from on-device pose tracking — a coaching aid, not a medical assessment.")
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // Surface the AI-returned data limitations we already parse but
                // previously discarded (audit #91).
                if !feedback.dataLimitations.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Label("What this couldn't fully assess", systemImage: "eye.trianglebadge.exclamationmark")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.secondaryText)
                        ForEach(Array(feedback.dataLimitations.enumerated()), id: \.offset) { _, limitation in
                            Text("• \(limitation)")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.medium)
                }

                // Contraindication / serious+ warnings (red banner). Covers .serious, .urgent,
                // and .emergency — all are high-priority and get the same strong banner here,
                // since form analysis doesn't navigate to an emergency redirect.
                let blockingWarnings = validation.warnings.filter { $0.severity >= .serious }
                if !blockingWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Label("Important", systemImage: "exclamationmark.triangle.fill")
                            .font(AppFonts.cardTitle)
                            .foregroundColor(AppColors.ctaText)
                        ForEach(blockingWarnings.map { $0.message }, id: \.self) { msg in
                            Text(msg)
                                .font(AppFonts.body)
                                .foregroundColor(AppColors.ctaText.opacity(0.9))
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.danger)
                    .cornerRadius(AppCorners.card)
                }

                // Data quality note (if low) — surface the concrete, fixable
                // warnings the scorer already computed (too short / poor lighting /
                // joints out of frame) instead of one vague line (audit #88).
                if validation.confidenceLevel == .low || validation.confidenceLevel == .insufficient {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Label(validation.confidenceLevel == .insufficient
                              ? "Limited data — results may not be reliable"
                              : "Some feedback may be less accurate",
                              systemImage: "info.circle.fill")
                            .font(AppFonts.captionSemiBold)
                            .foregroundColor(AppColors.warning)

                        if dataQuality.warnings.isEmpty {
                            Text("Record again with better lighting and your whole body in frame.")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.secondaryText)
                        } else {
                            Text("How to get a better result:")
                                .font(AppFonts.caption)
                                .foregroundColor(AppColors.secondaryText)
                            ForEach(Array(dataQuality.warnings.enumerated()), id: \.offset) { _, warning in
                                Text("• \(warning)")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                    .background(AppColors.warning.opacity(0.1))
                    .cornerRadius(AppCorners.medium)
                }

                // Progress over time (cross-session agent insights)
                if let insights = feedback.progressInsights {
                    progressInsightsCard(insights)
                }

                // Corrections
                if !feedback.corrections.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Label("Areas to Improve", systemImage: "exclamationmark.triangle.fill")
                            .font(AppFonts.cardTitle)
                            .foregroundColor(AppColors.warning)

                        ForEach(Array(feedback.corrections.enumerated()), id: \.offset) { _, correction in
                            correctionCard(correction)
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
                }

                // Positive points
                if !feedback.positivePoints.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Label("What You're Doing Well", systemImage: "checkmark.seal.fill")
                            .font(AppFonts.cardTitle)
                            .foregroundColor(AppColors.success)

                        ForEach(feedback.positivePoints, id: \.self) { point in
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.success)
                                Text(point)
                                    .font(AppFonts.body)
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
                }

                // Safety notes
                if !feedback.safetyNotes.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Label("Safety Notes", systemImage: "heart.text.square.fill")
                            .font(AppFonts.cardTitle)
                            .foregroundColor(AppColors.danger)

                        ForEach(feedback.safetyNotes, id: \.self) { note in
                            HStack(alignment: .top, spacing: AppSpacing.sm) {
                                Image(systemName: "exclamationmark.shield.fill")
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.danger)
                                Text(note)
                                    .font(AppFonts.body)
                            }
                        }
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
                }

                // Action buttons
                VStack(spacing: AppSpacing.md) {
                    Button(action: {
                        vm.reset()
                        showCamera = true
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Record Again")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button(action: { dismiss() }) {
                        Text("Done")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
    }

    // MARK: - Progress Insights (Cross-Session)

    private func progressInsightsCard(_ insights: FormProgressInsights) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Label("Progress Over Time", systemImage: "chart.line.uptrend.xyaxis")
                .font(AppFonts.cardTitle)
                .foregroundColor(AppColors.accent)

            // How today compares to the user's own prior sessions
            Text(insights.sessionComparison)
                .font(AppFonts.small)
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Per-metric trends
            if !insights.progressTrends.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(insights.progressTrends.enumerated()), id: \.offset) { _, trend in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Image(systemName: trendIcon(for: trend.direction))
                                .font(.caption)
                                .foregroundColor(trendColor(for: trend.direction))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trend.metric)
                                    .font(AppFonts.smallSemiBold)
                                Text(trend.description)
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            // Recurring issues
            if !insights.recurringIssues.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("Recurring Patterns")
                        .font(AppFonts.smallSemiBold)
                        .foregroundColor(AppColors.warning)

                    ForEach(Array(insights.recurringIssues.enumerated()), id: \.offset) { _, issue in
                        HStack(alignment: .top, spacing: AppSpacing.sm) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundColor(AppColors.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(issue.issue) — \(issue.sessionsObserved) sessions")
                                    .font(AppFonts.smallSemiBold)
                                Text(issue.description)
                                    .font(AppFonts.caption)
                                    .foregroundColor(AppColors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(AppColors.warning.opacity(0.08))
                .cornerRadius(AppCorners.medium)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
        .accessibilityIdentifier("formAnalysis.progressInsights")
    }

    private func trendIcon(for direction: FormProgressInsights.ProgressTrend.Direction) -> String {
        switch direction {
        case .improving: return "arrow.up.right.circle.fill"
        case .stable: return "arrow.right.circle.fill"
        case .declining: return "arrow.down.right.circle.fill"
        }
    }

    private func trendColor(for direction: FormProgressInsights.ProgressTrend.Direction) -> Color {
        switch direction {
        case .improving: return AppColors.success
        case .stable: return AppColors.secondaryText
        case .declining: return AppColors.warning
        }
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Analysis Failed")
                    .font(AppFonts.sectionTitle)

                Text(message)
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            // A short actionable checklist so a cryptic failure becomes a clear
            // "do this and record again" instead of a dead end (audit #92).
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Before you try again:")
                    .font(AppFonts.captionSemiBold)
                    .foregroundColor(AppColors.primaryText)
                ForEach([
                    "Record in a well-lit space",
                    "Stand back so your whole body fits in frame",
                    "Keep the camera steady",
                    "Check your internet connection"
                ], id: \.self) { tip in
                    Label(tip, systemImage: "checkmark.circle")
                        .font(AppFonts.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.medium)
            .padding(.horizontal, AppSpacing.lg)

            VStack(spacing: AppSpacing.md) {
                Button(action: {
                    vm.reset()
                    showCamera = true
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: { dismiss() }) {
                    Text("Cancel")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
    }

    // MARK: - Components

    private func scoreHeader(_ feedback: FormFeedback, confidenceLevel: FormConfidenceLevel = .high) -> some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .stroke(scoreColor(feedback.verdict).opacity(0.2), lineWidth: 10)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: Double(feedback.overallScore) / 100.0)
                    .stroke(scoreColor(feedback.verdict), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: AppSpacing.nano) {
                    Text("\(feedback.overallScore)")
                        .font(AppFonts.display)
                        .foregroundColor(scoreColor(feedback.verdict))

                    Text("/ 100")
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            Text(verdictText(feedback.verdict))
                .font(AppFonts.sectionTitle)
                .foregroundColor(scoreColor(feedback.verdict))

            Text(exercise.name)
                .font(AppFonts.body)
                .foregroundColor(AppColors.secondaryText)

            // Confidence level indicator
            HStack(spacing: AppSpacing.xs) {
                Circle()
                    .fill(confidenceLevelColor(confidenceLevel))
                    .frame(width: 8, height: 8)
                Text(confidenceLevelText(confidenceLevel))
                    .font(AppFonts.captionMedium)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    private func correctionCard(_ correction: FormFeedback.Correction) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: bodyPartIcon(correction.bodyPart))
                    .font(AppFonts.caption)
                    .foregroundColor(severityColor(correction.severity))

                Text(correction.bodyPart.capitalized)
                    .font(AppFonts.bodySemiBold)

                Spacer()

                Text(correction.severity.rawValue.capitalized)
                    .font(AppFonts.captionMedium)
                    .foregroundColor(severityColor(correction.severity))
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 2)
                    .background(severityColor(correction.severity).opacity(0.15))
                    .cornerRadius(AppCorners.small)
            }

            Text(correction.issue)
                .font(AppFonts.body)
                .foregroundColor(AppColors.primaryText)

            HStack(alignment: .top, spacing: AppSpacing.xs) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.caption2)
                    .foregroundColor(AppColors.accent)
                Text(correction.howToFix)
                    .font(AppFonts.caption)
                    .foregroundColor(AppColors.secondaryText)
            }

            if let ref = correction.dataReference, !ref.isEmpty {
                HStack(alignment: .top, spacing: AppSpacing.xs) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.caption2)
                        .foregroundColor(AppColors.accent.opacity(0.7))
                    Text("Based on: \(ref)")
                        .font(AppFonts.micro)
                        .foregroundColor(.secondary.opacity(0.8))
                        .italic()
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.elevatedSurface)
        .cornerRadius(AppCorners.medium)
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(AppFonts.caption)
                .foregroundColor(AppColors.accent)
                .frame(width: 20)
            Text(text)
                .font(AppFonts.body)
                .foregroundColor(AppColors.secondaryText)
        }
    }

    // MARK: - Helpers

    private func scoreColor(_ verdict: FormFeedback.Verdict) -> Color {
        switch verdict {
        case .excellent: return AppColors.success
        case .good: return AppColors.accent
        case .needsWork: return AppColors.warning
        case .concern: return AppColors.danger
        }
    }

    private func verdictText(_ verdict: FormFeedback.Verdict) -> String {
        switch verdict {
        case .excellent: return "Excellent Form!"
        case .good: return "Good Form"
        case .needsWork: return "Needs Improvement"
        case .concern: return "Form Concern"
        }
    }

    private func severityColor(_ severity: FormFeedback.Correction.Severity) -> Color {
        switch severity {
        case .minor: return AppColors.accent
        case .moderate: return AppColors.warning
        case .major: return AppColors.danger
        }
    }

    private func bodyPartIcon(_ bodyPart: String) -> String {
        let lower = bodyPart.lowercased()
        if lower.contains("knee") { return "figure.walk" }
        if lower.contains("hip") { return "figure.stand" }
        if lower.contains("shoulder") { return "figure.arms.open" }
        if lower.contains("elbow") || lower.contains("arm") { return "figure.boxing" }
        if lower.contains("back") || lower.contains("spine") || lower.contains("trunk") { return "figure.core.training" }
        return "figure.mixed.cardio"
    }

    private func confidenceLevelColor(_ level: FormConfidenceLevel) -> Color {
        switch level {
        case .high: return AppColors.success
        case .moderate: return AppColors.accent
        case .low: return AppColors.warning
        case .insufficient: return AppColors.danger
        }
    }

    private func confidenceLevelText(_ level: FormConfidenceLevel) -> String {
        switch level {
        case .high: return "High confidence"
        case .moderate: return "Moderate confidence"
        case .low: return "Low confidence"
        case .insufficient: return "Insufficient data"
        }
    }
}
