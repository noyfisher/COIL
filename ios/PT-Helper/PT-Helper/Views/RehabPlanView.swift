import SwiftUI

struct RehabPlanView: View {
    var analysisResult: AnalysisResult? = nil
    var existingPlan: RehabPlan? = nil
    @ObservedObject var viewModel: RehabPlanViewModel
    @EnvironmentObject private var savedPlansVM: SavedPlansViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showSwapSheet = false
    @State private var exerciseToSwap: RehabExercise?
    @State private var showReAssessment = false
    @State private var showReAssessmentComparison = false
    @StateObject private var reAssessmentVM = ReAssessmentViewModel()
    @State private var reAssessmentPain: Double = 3
    @State private var reAssessmentRegionPain: [String: Double] = [:]
    /// Cached PDF data to avoid regenerating on every view body evaluation
    @State private var cachedPDFData: Data?
    /// Adaptive progression recommendation
    @State private var adaptiveRecommendation: ProgressionRecommendation?
    @State private var showProgressionBanner = true

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
            AppColors.bgGradient.ignoresSafeArea()

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

                        // Adaptive progression recommendation
                        if analysisResult == nil,
                           plan.startDate != nil,
                           showProgressionBanner,
                           let recommendation = adaptiveRecommendation,
                           recommendation.action != .insufficientData {
                            AdaptiveProgressionBannerView(
                                recommendation: recommendation,
                                onApply: { applyProgression() },
                                onDismiss: { withAnimation { showProgressionBanner = false } }
                            )
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
                                .foregroundColor(AppColors.accent)
                                .padding(AppSpacing.md)
                                .frame(maxWidth: .infinity)
                                .background(AppColors.accentTint)
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
                                .foregroundColor(AppColors.primaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.coolGradient)
                                .cornerRadius(AppCorners.large)
                                .shadow(color: AppColors.cardShadowColor, radius: 8, y: 4)
                            }
                        }

                        if analysisResult != nil {
                            savePlanButton
                            homeButton
                        }
                    }
                    .padding(AppSpacing.xl)
                }
            } else {
                emptyState
            }
        }
        .navigationTitle("Rehab Plan")
        .navigationBarBackButtonHidden(viewModel.isGenerating)
        .interactiveDismissDisabled(viewModel.isGenerating)
        .gesture(viewModel.isGenerating ? DragGesture() : nil)
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
                            .accessibilityIdentifier("rehabPlan.shareButton")
                        }

                        Button(action: { showEditSheet = true }) {
                            Image(systemName: "pencil.circle")
                        }
                        .accessibilityIdentifier("rehabPlan.editButton")
                    }
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let plan = viewModel.rehabPlan {
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
        .sheet(isPresented: $showSwapSheet) {
            if let exercise = exerciseToSwap, let plan = viewModel.rehabPlan {
                ExerciseSwapSheet(exercise: exercise, plan: plan) { _, updatedPlan in
                    viewModel.rehabPlan = updatedPlan
                    showSwapSheet = false
                    // Regenerate cached PDF after swap
                    cachedPDFData = PDFExportService.generatePDF(for: updatedPlan)
                }
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
            // Adaptive progression: analyze sessions for saved plans with a start date
            if let plan = viewModel.rehabPlan, plan.startDate != nil, analysisResult == nil {
                adaptiveRecommendation = AdaptiveProgressionAnalyzer.analyze(
                    sessions: workoutViewModel.sessions,
                    plan: plan
                )
            }
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
                    CardSection(icon: "waveform.path.ecg", color: AppColors.accent, title: "Overall Pain") {
                        VStack(spacing: AppSpacing.md) {
                            HStack {
                                Text("\(Int(reAssessmentPain))")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(reAssessmentPainColor)
                                Text("/ 10").font(.title3).foregroundColor(AppColors.secondaryText)
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
        case 0...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
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
                        colors: [AppColors.success, AppColors.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .symbolEffect(.pulse.byLayer, options: .repeating)

            VStack(spacing: AppSpacing.sm) {
                Text("Building Your Plan")
                    .font(.system(.title2, design: .serif).weight(.bold))

                Text("Creating a personalized exercise program based on your conditions and fitness level...")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            ProgressView()
                .scaleEffect(1.2)
                .tint(AppColors.success)

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
                    .font(.system(.title3, design: .serif).weight(.bold))

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
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
        CardSection(icon: "calendar", color: AppColors.accent, title: plan.planName) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Conditions: \(plan.conditions.joined(separator: ", "))")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                Text("Duration: \(plan.totalWeeks) weeks")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                HStack {
                    Text("Start Date:")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
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
                        .foregroundColor(AppColors.secondaryText)
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
                            .foregroundColor(AppColors.secondaryText)

                        ZStack {
                            Circle()
                                .fill(hasExercises ? AppColors.accentTint : Color.clear)
                                .frame(width: 36, height: 36)

                            if hasExercises {
                                Text("\(exerciseCount)")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(AppColors.accent)
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
                        .fill(AppColors.accentTint)
                        .frame(width: 8, height: 8)
                    Text("Exercise day")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }
                HStack(spacing: AppSpacing.xs) {
                    Text("-")
                        .font(.caption2)
                        .foregroundColor(Color(.systemGray4))
                    Text("Rest day")
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
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
                .contextMenu {
                    Button(action: {
                        exerciseToSwap = exercise
                        showSwapSheet = true
                    }) {
                        Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
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
                        .foregroundColor(AppColors.primaryText)
                        .lineLimit(2)

                    Spacer()

                    // Verification badge
                    if let status = viewModel.exerciseVerifications[exercise.name] {
                        verificationBadge(for: status)
                    }
                }

                Text("Target: \(exercise.targetArea)")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)

                // Position preview teaser
                if let start = exercise.startPosition {
                    Text(start)
                        .font(.caption2)
                        .foregroundColor(AppColors.secondaryText)
                        .lineLimit(1)
                        .italic()
                }

                HStack(spacing: AppSpacing.sm) {
                    Text("\(exercise.sets) sets \u{00D7} \(exercise.reps)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(AppColors.secondaryText)

                    Spacer()

                    DifficultyBadge(difficulty: exercise.difficulty)
                }

                // Show concern text for flagged exercises
                if let status = viewModel.exerciseVerifications[exercise.name],
                   case .crossModelFlagged(let concerns) = status,
                   let firstConcern = concerns.first {
                    Text(firstConcern)
                        .font(.caption2)
                        .foregroundColor(AppColors.warning)
                        .lineLimit(2)
                }
            }

            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.mutedText)

                // Visible swap button (only for saved plans)
                if analysisResult == nil {
                    Button(action: {
                        exerciseToSwap = exercise
                        showSwapSheet = true
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(AppColors.accent)
                            .frame(width: 28, height: 28)
                            .background(AppColors.accentTint)
                            .clipShape(Circle())
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
                    .buttonStyle(.plain)
                    .accessibilityLabel("Swap exercise")
                    .accessibilityIdentifier("rehabPlan.swapExerciseButton")
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Verification UI

    @ViewBuilder
    private func verificationBadge(for status: ExerciseVerificationStatus) -> some View {
        switch status {
        case .verified:
            Label("Verified", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.success)
        case .contraindicated:
            Label("Warning", systemImage: "xmark.octagon.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.danger)
        case .crossModelVerified:
            Label("Checked", systemImage: "checkmark.seal")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.accent)
        case .crossModelFlagged:
            Label("Review", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.warning)
        case .crossModelFailed:
            Label("Unreviewed", systemImage: "questionmark.circle")
                .font(.caption2.weight(.medium))
                .foregroundColor(AppColors.mutedText)
        case .checking:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("Checking...")
                    .font(.caption2)
                    .foregroundColor(AppColors.mutedText)
            }
        }
    }

    private var verificationSummaryBanner: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: viewModel.isVerifyingUnknowns ? "arrow.triangle.2.circlepath" : "checkmark.shield")
                .foregroundColor(viewModel.flaggedCount > 0 ? AppColors.warning : AppColors.success)
                .font(.subheadline)

            if viewModel.isVerifyingUnknowns {
                Text("Verifying exercises...")
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                let verified = viewModel.verifiedCount
                let flagged = viewModel.flaggedCount
                let total = viewModel.totalExerciseCount

                if flagged > 0 {
                    Text("\(verified) of \(total) verified \u{2022} \(flagged) flagged for review")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                } else {
                    Text("\(verified) of \(total) exercises verified")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            Spacer()
        }
        .padding(AppSpacing.md)
        .background(
            (viewModel.flaggedCount > 0 ? AppColors.warning : AppColors.success)
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
                        .foregroundColor(AppColors.secondaryText)
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
                                .tint(AppColors.ctaText)
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
                        .foregroundColor(AppColors.ctaText)
                    Text("Safety Notice")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.ctaText)
                }
                ForEach(Array(urgentWarnings.enumerated()), id: \.offset) { _, warning in
                    Text("• \(warning.message)")
                        .font(.caption)
                        .foregroundColor(AppColors.ctaText.opacity(0.95))
                }
            }

            if !cautionWarnings.isEmpty {
                if urgentWarnings.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(urgentWarnings.isEmpty ? AppColors.warning : .white)
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
        .background(viewModel.rehabPlanWarnings.contains(where: { $0.severity == .urgent }) ? AppColors.danger : AppColors.warning.opacity(0.08))
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

    // MARK: - Adaptive Progression

    private func applyProgression() {
        guard let recommendation = adaptiveRecommendation,
              var plan = viewModel.rehabPlan else { return }
        plan = AdaptiveProgressionAnalyzer.applyProgression(recommendation.action, to: plan)
        viewModel.rehabPlan = plan
        savedPlansVM.updatePlan(plan)
        cachedPDFData = PDFExportService.generatePDF(for: plan)
        adaptiveRecommendation = nil

        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        SessionLogger.shared.logUserAction(.buttonTapped, action: "applyProgression",
                                            metadata: ["action": recommendation.action.rawValue,
                                                        "confidence": recommendation.confidence.rawValue])
    }

    // MARK: - Week Progress

    private func weekProgressBanner(week: Int, totalWeeks: Int) -> some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(AppColors.accent)
                Text("Week \(week) of \(totalWeeks)")
                    .font(.headline)
                Spacer()
                if let note = ProgressionRule.progressionNote(week: week, totalWeeks: totalWeeks) {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppColors.accent)
                        .frame(width: geometry.size.width * CGFloat(week) / CGFloat(max(totalWeeks, 1)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
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
                    .foregroundColor(AppColors.primaryText.opacity(0.7))
            }
            .foregroundColor(AppColors.primaryText)
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
