import SwiftUI

struct RehabPlanView: View {
    var analysisResult: AnalysisResult? = nil
    var existingPlan: RehabPlan? = nil
    @ObservedObject var viewModel: RehabPlanViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showReAssessment = false
    @State private var showReAssessmentComparison = false
    @StateObject private var reAssessmentVM = ReAssessmentViewModel()
    @State private var reAssessmentPain: Double = 3
    @State private var reAssessmentRegionPain: [String: Double] = [:]
    /// Cached PDF data to avoid regenerating on every view body evaluation
    @State private var cachedPDFData: Data?

    /// Init for analysis flow — accepts a prefetched ViewModel (generation already in progress)
    init(viewModel: RehabPlanViewModel, analysisResult: AnalysisResult) {
        self.analysisResult = analysisResult
        self.existingPlan = nil
        self._viewModel = ObservedObject(wrappedValue: viewModel)
    }

    /// Init for saved plans — loads an existing plan without API call
    init(existingPlan: RehabPlan) {
        self.existingPlan = existingPlan
        self.analysisResult = nil
        let vm = RehabPlanViewModel()
        vm.rehabPlan = existingPlan
        self._viewModel = ObservedObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            if viewModel.isGenerating {
                generatingView
            } else if let error = viewModel.generationError {
                errorView(error)
            } else if let plan = viewModel.rehabPlan {
                ScrollView {
                    VStack(spacing: 16) {
                        // Safety warnings from validation pipeline
                        if !viewModel.rehabPlanWarnings.isEmpty {
                            rehabWarningsBanner
                        }

                        // Week progress banner (for saved plans with startDate)
                        if analysisResult == nil, let week = plan.currentWeek {
                            weekProgressBanner(week: week, totalWeeks: plan.totalWeeks)
                        }

                        // Start Plan button (for saved plans not yet started)
                        if analysisResult == nil && plan.startDate == nil {
                            startPlanBanner
                        }

                        // Re-assessment prompt
                        if analysisResult == nil,
                           reAssessmentVM.shouldShowReAssessment(for: plan),
                           let assessmentType = reAssessmentVM.assessmentType(for: plan) {
                            ReAssessmentPromptView(
                                plan: plan,
                                assessmentType: assessmentType,
                                onStartAssessment: { showReAssessment = true }
                            )
                        }

                        // Show comparison if available
                        if analysisResult == nil,
                           let comparison = reAssessmentVM.comparison(for: plan.id) {
                            NavigationLink(destination: ReAssessmentComparisonView(
                                initial: comparison.initial,
                                latest: comparison.latest
                            )) {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "chart.bar.xaxis")
                                    Text("View Progress Comparison")
                                }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.blue)
                                .padding(AppSpacing.md)
                                .frame(maxWidth: .infinity)
                                .background(Color.blue.opacity(0.08))
                                .cornerRadius(AppCorners.medium)
                            }
                        }

                        planHeader(plan: plan)
                        weeklyCalendar(plan: plan)
                        exerciseList(for: plan)

                        // Guided workout button (only for saved plans, not during generation)
                        if analysisResult == nil {
                            NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                                HStack(spacing: AppSpacing.sm) {
                                    Image(systemName: "play.fill")
                                    Text("Start Guided Workout")
                                }
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.coolGradient)
                                .cornerRadius(AppCorners.large)
                                .shadow(color: .blue.opacity(0.2), radius: 8, y: 4)
                            }
                        }

                        if analysisResult != nil {
                            savePlanButton
                            homeButton
                        }
                    }
                    .padding(20)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Rehab Plan")
        .toolbar {
            if analysisResult == nil, let plan = viewModel.rehabPlan {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: AppSpacing.sm) {
                        if let pdfData = cachedPDFData {
                            ShareLink(
                                item: pdfData,
                                preview: SharePreview(plan.planName, icon: "doc.fill")
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }

                        Button(action: { showEditSheet = true }) {
                            Image(systemName: "pencil.circle")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if var plan = viewModel.rehabPlan {
                EditRehabPlanView(
                    plan: Binding(
                        get: { viewModel.rehabPlan ?? plan },
                        set: { viewModel.rehabPlan = $0 }
                    ),
                    onSave: { updatedPlan in
                        viewModel.rehabPlan = updatedPlan
                        savedPlansVM.updatePlan(updatedPlan)
                        // Regenerate cached PDF after edits
                        cachedPDFData = PDFExportService.generatePDF(for: updatedPlan)
                    }
                )
            }
        }
        .sheet(isPresented: $showReAssessment) {
            reAssessmentSheet
        }
        .onAppear {
            if viewModel.rehabPlan == nil && !viewModel.isGenerating {
                if let existing = existingPlan {
                    viewModel.rehabPlan = existing
                } else if let analysis = analysisResult {
                    viewModel.generateRehabPlan(from: analysis)
                }
            }
            Task { await reAssessmentVM.loadAssessments() }
        }
        .onChange(of: viewModel.rehabPlan?.id) { _, _ in
            // Generate PDF once when plan becomes available (not on every render)
            if analysisResult == nil, let plan = viewModel.rehabPlan {
                cachedPDFData = PDFExportService.generatePDF(for: plan)
            }
        }
        .trackScreen("RehabPlan")
    }

    // MARK: - Re-Assessment Sheet

    private var reAssessmentSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    Text("Rate your current pain levels")
                        .font(.headline)
                        .padding(.top, AppSpacing.lg)

                    // Overall pain
                    CardSection(icon: "waveform.path.ecg", color: .blue, title: "Overall Pain") {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Text("\(Int(reAssessmentPain))")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(reAssessmentPainColor)
                                Text("/ 10").font(.title3).foregroundColor(.secondary)
                                Spacer()
                            }
                            Slider(value: $reAssessmentPain, in: 0...10, step: 1)
                                .tint(reAssessmentPainColor)
                        }
                    }

                    // Per-region pain
                    RegionPainInputView(
                        regionPainLevels: $reAssessmentRegionPain,
                        suggestedRegions: viewModel.rehabPlan?.exercises.map {
                            $0.targetArea.lowercased().replacingOccurrences(of: " ", with: "_")
                        } ?? []
                    )

                    // Save
                    Button(action: saveReAssessment) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save Assessment")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
            }
            .navigationTitle("Re-Assessment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showReAssessment = false }
                }
            }
        }
    }

    private func saveReAssessment() {
        guard let plan = viewModel.rehabPlan,
              let assessmentType = reAssessmentVM.assessmentType(for: plan) else { return }

        let snapshot = AssessmentSnapshot(
            id: UUID(),
            planId: plan.id,
            assessmentType: assessmentType,
            date: Date(),
            regionPainLevels: reAssessmentRegionPain,
            overallPain: reAssessmentPain
        )

        Task {
            await reAssessmentVM.saveAssessment(snapshot)
            showReAssessment = false
            reAssessmentPain = 3
            reAssessmentRegionPain = [:]
        }
    }

    private var reAssessmentPainColor: Color {
        switch Int(reAssessmentPain) {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }

    // MARK: - Loading State

    private var generatingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Building Your Plan")
                    .font(.title2.weight(.bold))

                Text("Creating a personalized exercise program based on your conditions and fitness level...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            ProgressView()
                .scaleEffect(1.2)
                .tint(.green)

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(AppColors.warning)

            VStack(spacing: AppSpacing.sm) {
                Text("Plan Generation Failed")
                    .font(.title3.weight(.bold))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }

            if let analysis = analysisResult {
                Button(action: {
                    viewModel.generateRehabPlan(from: analysis)
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, AppSpacing.xxl)
            }

            Spacer()
            Spacer()
        }
        .padding(AppSpacing.xl)
    }

    // MARK: - Plan Display

    private func planHeader(plan: RehabPlan) -> some View {
        CardSection(icon: "calendar", color: .blue, title: plan.planName) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Conditions: \(plan.conditions.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Duration: \(plan.totalWeeks) weeks")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack {
                    Text("Start Date:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    DatePicker("", selection: Binding(
                        get: { viewModel.rehabPlan?.createdDate ?? Date() },
                        set: { viewModel.rehabPlan?.createdDate = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                }
                if let notes = plan.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, AppSpacing.xs)
                }
            }
        }
    }

    private func weeklyCalendar(plan: RehabPlan) -> some View {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        return VStack(spacing: AppSpacing.md) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { day in
                    let hasExercises = plan.weeklySchedule.indices.contains(day) && !plan.weeklySchedule[day].isEmpty
                    let exerciseCount = hasExercises ? plan.weeklySchedule[day].count : 0

                    VStack(spacing: AppSpacing.sm) {
                        Text(dayNames[day])
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)

                        ZStack {
                            Circle()
                                .fill(hasExercises ? Color.blue.opacity(0.12) : Color.clear)
                                .frame(width: 36, height: 36)

                            if hasExercises {
                                Text("\(exerciseCount)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.blue)
                            } else {
                                Text("-")
                                    .font(.caption)
                                    .foregroundColor(Color(.systemGray4))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Legend
            HStack(spacing: AppSpacing.lg) {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 8, height: 8)
                    Text("Exercise day")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: AppSpacing.xs) {
                    Text("-")
                        .font(.caption2)
                        .foregroundColor(Color(.systemGray4))
                    Text("Rest day")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func exerciseList(for plan: RehabPlan) -> some View {
        VStack(spacing: 16) {
            // Verification summary banner (only show if verification has been performed)
            if !viewModel.exerciseVerifications.isEmpty {
                verificationSummaryBanner
            }

            ForEach(plan.exercises) { exercise in
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                    exerciseCard(for: exercise)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func exerciseCard(for exercise: RehabExercise) -> some View {
        HStack(spacing: AppSpacing.lg) {
            // Compact exercise image with SF Symbol fallback
            ExerciseImageView(exercise: exercise, isCompact: true)

            // Exercise info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: AppSpacing.xs) {
                    Text(exercise.name)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Spacer()

                    // Verification badge
                    if let status = viewModel.exerciseVerifications[exercise.name] {
                        verificationBadge(for: status)
                    }
                }

                Text("Target: \(exercise.targetArea)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Position preview teaser
                if let start = exercise.startPosition {
                    Text(start)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .italic()
                }

                HStack(spacing: AppSpacing.sm) {
                    Text("\(exercise.sets) sets \u{00D7} \(exercise.reps)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    DifficultyBadge(difficulty: exercise.difficulty)
                }

                // Show concern text for flagged exercises
                if let status = viewModel.exerciseVerifications[exercise.name],
                   case .crossModelFlagged(let concerns) = status,
                   let firstConcern = concerns.first {
                    Text(firstConcern)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(2)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.5))
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    // MARK: - Verification UI

    @ViewBuilder
    private func verificationBadge(for status: ExerciseVerificationStatus) -> some View {
        switch status {
        case .verified:
            Label("Verified", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(.green)
        case .contraindicated:
            Label("Warning", systemImage: "xmark.octagon.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(.red)
        case .crossModelVerified:
            Label("Checked", systemImage: "checkmark.seal")
                .font(.caption2.weight(.medium))
                .foregroundColor(.blue)
        case .crossModelFlagged:
            Label("Review", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(.orange)
        case .crossModelFailed:
            Label("Unreviewed", systemImage: "questionmark.circle")
                .font(.caption2.weight(.medium))
                .foregroundColor(.gray)
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Checking...")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }

    private var verificationSummaryBanner: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: viewModel.isVerifyingUnknowns ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                .foregroundColor(viewModel.flaggedCount > 0 ? .orange : .green)
                .font(.subheadline)

            if viewModel.isVerifyingUnknowns {
                Text("Verifying exercises...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                let verified = viewModel.verifiedCount
                let flagged = viewModel.flaggedCount
                let total = viewModel.totalExerciseCount

                if flagged > 0 {
                    Text("\(verified) of \(total) verified \u{2022} \(flagged) flagged for review")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(verified) of \(total) exercises verified")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .background(
            (viewModel.flaggedCount > 0 ? Color.orange : Color.green)
                .opacity(0.08)
        )
        .cornerRadius(AppCorners.medium)
    }

    private var savePlanButton: some View {
        VStack(spacing: AppSpacing.sm) {
            if let error = viewModel.saveError {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.warning)
                    Text("Failed to save: \(error)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Button(action: { viewModel.savePlanToFirestore() }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Save")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            } else if viewModel.showSaveSuccess {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.success)
                    Text("Plan saved successfully!")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.success)
                }
            } else {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    viewModel.savePlanToFirestore()
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        if viewModel.isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(viewModel.isSaving ? "Saving..." : "Save Plan")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(viewModel.isSaving)
            }
        }
    }

    private var rehabWarningsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            let urgentWarnings = viewModel.rehabPlanWarnings.filter { $0.severity == .urgent }
            let cautionWarnings = viewModel.rehabPlanWarnings.filter { $0.severity == .caution }

            if !urgentWarnings.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.white)
                    Text("Safety Notice")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                }
                ForEach(Array(urgentWarnings.enumerated()), id: \.offset) { _, warning in
                    Text("• \(warning.message)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.95))
                }
            }

            if !cautionWarnings.isEmpty {
                if urgentWarnings.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(urgentWarnings.isEmpty ? .orange : .white)
                        Text("Things to Keep in Mind")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(urgentWarnings.isEmpty ? .primary : .white)
                    }
                }
                ForEach(Array(cautionWarnings.enumerated()), id: \.offset) { _, warning in
                    Text("• \(warning.message)")
                        .font(.caption)
                        .foregroundColor(urgentWarnings.isEmpty ? .secondary : .white.opacity(0.9))
                }
            }
        }
        .padding()
        .background(viewModel.rehabPlanWarnings.contains(where: { $0.severity == .urgent }) ? Color.red : Color.orange.opacity(0.08))
        .cornerRadius(AppCorners.card)
    }

    private var homeButton: some View {
        Button(action: {
            NotificationCenter.default.post(name: .popToRoot, object: nil)
        }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "house")
                Text("Home")
            }
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    // MARK: - Week Progress

    private func weekProgressBanner(week: Int, totalWeeks: Int) -> some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.blue)
                Text("Week \(week) of \(totalWeeks)")
                    .font(.headline)
                Spacer()
                if let note = ProgressionRule.progressionNote(week: week, totalWeeks: totalWeeks) {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(week) / CGFloat(max(totalWeeks, 1)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var startPlanBanner: some View {
        Button(action: {
            if var plan = viewModel.rehabPlan {
                plan.startDate = Date()
                viewModel.rehabPlan = plan
                savedPlansVM.updatePlan(plan)
            }
        }) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "flag.fill")
                Text("Start This Plan")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Track your weekly progress")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .foregroundColor(.white)
            .padding(AppSpacing.lg)
            .background(AppColors.healingGradient)
            .cornerRadius(AppCorners.card)
        }
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "figure.walk",
            title: "No Plan Available",
            subtitle: "Generate a plan from your analysis results"
        )
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - DateFormatter extensions

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()

    static let shortWeekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
