import SwiftUI

struct PainDetailView: View {
    @ObservedObject var viewModel: InjuryAnalysisViewModel
    @State private var painTypes: [String] = []
    @State private var customPainType: String = ""
    @State private var customPainDescription: String = ""
    @State private var painIntensity: Double = 5
    @State private var painDurations: [String] = []
    @State private var painFrequencies: [String] = []
    @State private var customFrequency: String = ""
    @State private var painOnsets: [String] = []
    @State private var customOnset: String = ""
    @State private var aggravatingFactors: [String] = []
    @State private var relievingFactors: [String] = []
    @State private var customAggravating: String = ""
    @State private var customRelieving: String = ""
    @State private var additionalNotes: String = ""
    @State private var showApplyToAllConfirmation: Bool = false
    @State private var showMoreDetails: Bool = false
    // Treatment history state
    @State private var hasSeenDoctor: Bool = false
    @State private var imagingDone: [String] = []
    @State private var hasDiagnosis: Bool = false
    @State private var diagnosisText: String = ""
    @State private var currentlyReceivingTreatment: Bool = false
    @State private var treatmentDetails: String = ""

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Progress indicator
                        if !viewModel.selectedRegionNames.isEmpty {
                            VStack(spacing: AppSpacing.sm) {
                                HStack {
                                    Text("Region \(viewModel.currentRegionIndex + 1) of \(viewModel.totalRegions)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, AppSpacing.md)
                                        .padding(.vertical, AppSpacing.xs)
                                        .background(AppColors.accent)
                                        .cornerRadius(AppCorners.medium)
                                    Spacer()
                                    // Encouraging micro-copy
                                    Text(encouragingText)
                                        .font(.caption)
                                        .foregroundColor(AppColors.secondaryText)
                                        .transition(.opacity)
                                        .animation(AppAnimations.smooth, value: formCompletionFields)
                                }

                                // Form completion mini-bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color(.systemGray5))
                                            .frame(height: 3)
                                        Capsule()
                                            .fill(AppColors.accent)
                                            .frame(width: geo.size.width * formCompletionProgress, height: 3)
                                            .animation(AppAnimations.smooth, value: formCompletionProgress)
                                    }
                                }
                                .frame(height: 3)
                            }
                            .id("top")
                        }

                        if let currentRegion = viewModel.currentRegion {
                            CardSection(icon: "figure.walk", color: AppColors.accent, title: "Assessing: \(currentRegion.name)") {
                                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                                    // Essential fields — always visible
                                    painTypeSelection
                                    painIntensitySlider
                                    painDurationPicker
                                    painFrequencyPicker
                                    painOnsetPicker
                                    aggravatingFactorsSelection
                                    relievingFactorsSelection

                                    // Collapsible section for optional details
                                    Button(action: {
                                        withAnimation(AppAnimations.springy) {
                                            showMoreDetails.toggle()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: showMoreDetails ? "chevron.up.circle.fill" : "plus.circle.fill")
                                                .foregroundColor(AppColors.accent)
                                            Text(showMoreDetails ? "Hide Additional Details" : "Add More Details")
                                                .font(.subheadline.weight(.medium))
                                                .foregroundColor(AppColors.accent)
                                            Spacer()
                                            if !showMoreDetails && hasOptionalContent {
                                                Text("Has content")
                                                    .font(.caption2)
                                                    .foregroundColor(AppColors.success)
                                            }
                                        }
                                        .padding(AppSpacing.md)
                                        .background(AppColors.accentTint)
                                        .cornerRadius(AppCorners.medium)
                                    }
                                    .buttonStyle(.plain)

                                    if showMoreDetails {
                                        customPainDescriptionField
                                        treatmentHistorySection
                                        additionalNotesField
                                    }
                                }
                            }
                            navigationButtons
                        } else {
                            Text("No region selected")
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.currentRegionIndex) { _, _ in
                    restoreFormState()
                    withAnimation {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Pain Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            restoreFormState()
        }
        .onDisappear {
            // Only reset if we're NOT currently navigating to the analyzing screen.
            // Without this guard, navigating TO the AnalyzingView kills the in-flight
            // analysis task because PainDetailView disappears from the nav stack.
            if !viewModel.showAnalyzingScreen && !viewModel.isAnalyzing {
                viewModel.resetAnalysisState()
            }
        }
        .navigationDestination(isPresented: $viewModel.showAnalyzingScreen) {
            AnalyzingView(viewModel: viewModel)
        }
        .trackScreen("PainDetail")
        .alert(
            "Apply to All Regions?",
            isPresented: $showApplyToAllConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Apply to All") {
                guard let assessment = buildAssessment() else { return }
                viewModel.applyToAllRegionsAndAnalyze(assessment)
            }
        } message: {
            Text("This will copy your current pain details to all \(viewModel.totalRegions) selected regions and start analysis.")
        }
    }

    // MARK: - Form State Management

    /// Build a PainAssessment from the current form values.
    private func buildAssessment() -> PainAssessment? {
        guard let region = viewModel.currentRegion else { return nil }
        let trimmedDescription = customPainDescription.trimmingCharacters(in: .whitespaces)
        let trimmedDiagnosis = diagnosisText.trimmingCharacters(in: .whitespaces)
        let trimmedTreatment = treatmentDetails.trimmingCharacters(in: .whitespaces)

        // Only include treatment if any data was entered
        let treatment: CurrentTreatment? = hasSeenDoctor || currentlyReceivingTreatment
            ? CurrentTreatment(
                hasSeenDoctor: hasSeenDoctor,
                imagingDone: imagingDone,
                hasDiagnosis: hasDiagnosis,
                diagnosisText: trimmedDiagnosis.isEmpty ? nil : trimmedDiagnosis,
                currentlyReceivingTreatment: currentlyReceivingTreatment,
                treatmentDetails: trimmedTreatment.isEmpty ? nil : trimmedTreatment
            )
            : nil

        return PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painTypes: painTypes,
            customPainDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
            painIntensity: Int(painIntensity),
            painDurations: painDurations,
            painFrequencies: painFrequencies,
            painOnsets: painOnsets,
            aggravatingFactors: aggravatingFactors,
            relievingFactors: relievingFactors,
            additionalNotes: additionalNotes,
            currentTreatment: treatment
        )
    }

    /// Restore form fields from a previously saved assessment, or reset to defaults.
    private func restoreFormState() {
        if let saved = viewModel.currentAssessment {
            painTypes = saved.painTypes
            customPainType = ""
            customPainDescription = saved.customPainDescription ?? ""
            painIntensity = Double(saved.painIntensity)
            painDurations = saved.painDurations
            painFrequencies = saved.painFrequencies
            customFrequency = ""
            painOnsets = saved.painOnsets
            customOnset = ""
            aggravatingFactors = saved.aggravatingFactors
            relievingFactors = saved.relievingFactors
            additionalNotes = saved.additionalNotes ?? ""
            // Treatment history
            hasSeenDoctor = saved.currentTreatment?.hasSeenDoctor ?? false
            imagingDone = saved.currentTreatment?.imagingDone ?? []
            hasDiagnosis = saved.currentTreatment?.hasDiagnosis ?? false
            diagnosisText = saved.currentTreatment?.diagnosisText ?? ""
            currentlyReceivingTreatment = saved.currentTreatment?.currentlyReceivingTreatment ?? false
            treatmentDetails = saved.currentTreatment?.treatmentDetails ?? ""
            // Auto-expand if optional sections have content
            showMoreDetails = !(saved.customPainDescription ?? "").isEmpty ||
                (saved.currentTreatment?.hasSeenDoctor ?? false) ||
                (saved.currentTreatment?.currentlyReceivingTreatment ?? false) ||
                !(saved.additionalNotes ?? "").isEmpty
        } else {
            painTypes = []
            customPainType = ""
            customPainDescription = ""
            painIntensity = 5
            painDurations = []
            painFrequencies = []
            customFrequency = ""
            painOnsets = []
            customOnset = ""
            aggravatingFactors = []
            relievingFactors = []
            additionalNotes = ""
            hasSeenDoctor = false
            imagingDone = []
            hasDiagnosis = false
            diagnosisText = ""
            currentlyReceivingTreatment = false
            treatmentDetails = ""
            showMoreDetails = false
        }
    }

    // MARK: - Form Completion Tracking

    /// Whether any optional (collapsed) fields have content
    private var hasOptionalContent: Bool {
        !customPainDescription.trimmingCharacters(in: .whitespaces).isEmpty ||
        hasSeenDoctor || currentlyReceivingTreatment ||
        !additionalNotes.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var formCompletionFields: Int {
        var count = 0
        if !painTypes.isEmpty { count += 1 }
        if painIntensity != 5 { count += 1 }  // intensity changed from default
        if !painDurations.isEmpty { count += 1 }
        if !painFrequencies.isEmpty { count += 1 }
        if !painOnsets.isEmpty { count += 1 }
        if !aggravatingFactors.isEmpty { count += 1 }
        if !relievingFactors.isEmpty { count += 1 }
        if !additionalNotes.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        if !customPainDescription.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        return count
    }

    private var formCompletionProgress: CGFloat {
        CGFloat(formCompletionFields) / 9.0  // 9 total fields
    }

    private var encouragingText: String {
        let factorCount = aggravatingFactors.count + relievingFactors.count
        if viewModel.currentRegionIndex == viewModel.totalRegions - 1 && viewModel.totalRegions > 1 {
            return "Last one!"
        } else if factorCount >= 4 {
            return "Great detail!"
        } else if formCompletionFields >= 7 {
            return "Almost done!"
        } else {
            return ""
        }
    }

    // MARK: - Pain Type (multi-select chips + custom)

    private var painTypeOptions: [String] {
        PainAssessment.PainType.allCases.map { $0.displayName }
    }

    private var customPainTypeEntries: [String] {
        painTypes.filter { !painTypeOptions.contains($0) }
    }

    private func addCustomPainType() {
        let trimmed = customPainType.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !painTypes.contains(trimmed) else { return }
        painTypes.append(trimmed)
        customPainType = ""
    }

    private var painTypeSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Type")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(painTypeOptions, id: \.self) { type in
                    ChipButton(
                        label: type,
                        isSelected: painTypes.contains(type),
                        action: {
                            if painTypes.contains(type) {
                                painTypes.removeAll { $0 == type }
                            } else {
                                painTypes.append(type)
                            }
                        }
                    )
                }
                ForEach(customPainTypeEntries, id: \.self) { entry in
                    ChipButton(
                        label: "✕ " + entry,
                        isSelected: true,
                        action: { painTypes.removeAll { $0 == entry } }
                    )
                }
            }
            HStack(spacing: AppSpacing.sm) {
                TextField("Add your own...", text: $customPainType)
                    .font(.subheadline)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
                    .submitLabel(.done)
                    .onSubmit { addCustomPainType() }
                Button(action: addCustomPainType) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(customPainType.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mutedText : AppColors.accent)
                }
                .disabled(customPainType.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Pain Intensity

    private var painIntensitySlider: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Intensity")
                .font(.headline)
            HStack {
                Text("\(Int(painIntensity))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(painColor)
                Text("/ 10")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text(painDescription)
                    .font(.caption.weight(.medium))
                    .foregroundColor(painColor)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(painColor.opacity(0.12))
                    .cornerRadius(AppCorners.small)
            }
            Slider(value: $painIntensity, in: 1...10, step: 1)
                .tint(painColor)
            HStack {
                Text("Mild")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
                Spacer()
                Text("Severe")
                    .font(.caption2)
                    .foregroundColor(AppColors.secondaryText)
            }
        }
    }

    // MARK: - Pain Duration (single-select chips)

    private var painDurationOptions: [String] {
        PainAssessment.PainDuration.allCases.map { $0.displayName }
    }

    private var painDurationPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Duration")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(painDurationOptions, id: \.self) { duration in
                    ChipButton(
                        label: duration,
                        isSelected: painDurations.contains(duration),
                        action: {
                            if painDurations.contains(duration) {
                                painDurations = []
                            } else {
                                painDurations = [duration]
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Pain Frequency (multi-select chips + custom)

    private var painFrequencyOptions: [String] {
        PainAssessment.PainFrequency.allCases.map { $0.displayName }
    }

    private var customFrequencyEntries: [String] {
        painFrequencies.filter { !painFrequencyOptions.contains($0) }
    }

    private func addCustomFrequency() {
        let trimmed = customFrequency.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !painFrequencies.contains(trimmed) else { return }
        painFrequencies.append(trimmed)
        customFrequency = ""
    }

    private var painFrequencyPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Frequency")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(painFrequencyOptions, id: \.self) { frequency in
                    ChipButton(
                        label: frequency,
                        isSelected: painFrequencies.contains(frequency),
                        action: {
                            if painFrequencies.contains(frequency) {
                                painFrequencies.removeAll { $0 == frequency }
                            } else {
                                painFrequencies.append(frequency)
                            }
                        }
                    )
                }
                ForEach(customFrequencyEntries, id: \.self) { entry in
                    ChipButton(
                        label: "✕ " + entry,
                        isSelected: true,
                        action: { painFrequencies.removeAll { $0 == entry } }
                    )
                }
            }
            HStack(spacing: AppSpacing.sm) {
                TextField("Add your own...", text: $customFrequency)
                    .font(.subheadline)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
                    .submitLabel(.done)
                    .onSubmit { addCustomFrequency() }
                Button(action: addCustomFrequency) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(customFrequency.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mutedText : AppColors.accent)
                }
                .disabled(customFrequency.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Pain Onset (multi-select chips + custom)

    private var painOnsetOptions: [String] {
        PainAssessment.PainOnset.allCases.map { $0.displayName }
    }

    private var customOnsetEntries: [String] {
        painOnsets.filter { !painOnsetOptions.contains($0) }
    }

    private func addCustomOnset() {
        let trimmed = customOnset.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !painOnsets.contains(trimmed) else { return }
        painOnsets.append(trimmed)
        customOnset = ""
    }

    private var painOnsetPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Onset")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(painOnsetOptions, id: \.self) { onset in
                    ChipButton(
                        label: onset,
                        isSelected: painOnsets.contains(onset),
                        action: {
                            if painOnsets.contains(onset) {
                                painOnsets.removeAll { $0 == onset }
                            } else {
                                painOnsets.append(onset)
                            }
                        }
                    )
                }
                ForEach(customOnsetEntries, id: \.self) { entry in
                    ChipButton(
                        label: "✕ " + entry,
                        isSelected: true,
                        action: { painOnsets.removeAll { $0 == entry } }
                    )
                }
            }
            HStack(spacing: AppSpacing.sm) {
                TextField("Add your own...", text: $customOnset)
                    .font(.subheadline)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
                    .submitLabel(.done)
                    .onSubmit { addCustomOnset() }
                Button(action: addCustomOnset) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(customOnset.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mutedText : AppColors.accent)
                }
                .disabled(customOnset.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Aggravating Factors (toggle chips, region-specific + custom)

    private var aggravatingFactorsSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("What Makes It Worse?")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(aggravatingOptions, id: \.self) { factor in
                    ChipButton(
                        label: factor,
                        isSelected: aggravatingFactors.contains(factor),
                        action: {
                            if aggravatingFactors.contains(factor) {
                                aggravatingFactors.removeAll { $0 == factor }
                            } else {
                                aggravatingFactors.append(factor)
                            }
                        }
                    )
                }
                // Show custom entries as removable chips
                ForEach(customAggravatingEntries, id: \.self) { factor in
                    ChipButton(
                        label: "✕ " + factor,
                        isSelected: true,
                        action: {
                            aggravatingFactors.removeAll { $0 == factor }
                        }
                    )
                }
            }
            // Custom input
            HStack(spacing: AppSpacing.sm) {
                TextField("Add your own...", text: $customAggravating)
                    .font(.subheadline)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
                    .submitLabel(.done)
                    .onSubmit { addCustomAggravating() }
                Button(action: addCustomAggravating) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(customAggravating.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mutedText : AppColors.accent)
                }
                .disabled(customAggravating.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Relieving Factors (toggle chips, region-specific + custom)

    private var relievingFactorsSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("What Helps?")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(relievingOptions, id: \.self) { factor in
                    ChipButton(
                        label: factor,
                        isSelected: relievingFactors.contains(factor),
                        action: {
                            if relievingFactors.contains(factor) {
                                relievingFactors.removeAll { $0 == factor }
                            } else {
                                relievingFactors.append(factor)
                            }
                        }
                    )
                }
                // Show custom entries as removable chips
                ForEach(customRelievingEntries, id: \.self) { factor in
                    ChipButton(
                        label: "✕ " + factor,
                        isSelected: true,
                        action: {
                            relievingFactors.removeAll { $0 == factor }
                        }
                    )
                }
            }
            // Custom input
            HStack(spacing: AppSpacing.sm) {
                TextField("Add your own...", text: $customRelieving)
                    .font(.subheadline)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.small)
                    .submitLabel(.done)
                    .onSubmit { addCustomRelieving() }
                Button(action: addCustomRelieving) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(customRelieving.trimmingCharacters(in: .whitespaces).isEmpty ? AppColors.mutedText : AppColors.accent)
                }
                .disabled(customRelieving.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Custom Factor Helpers

    /// Custom aggravating entries (ones the user typed, not from the preset list)
    private var customAggravatingEntries: [String] {
        aggravatingFactors.filter { !aggravatingOptions.contains($0) }
    }

    /// Custom relieving entries (ones the user typed, not from the preset list)
    private var customRelievingEntries: [String] {
        relievingFactors.filter { !relievingOptions.contains($0) }
    }

    private func addCustomAggravating() {
        let trimmed = customAggravating.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !aggravatingFactors.contains(trimmed) else { return }
        aggravatingFactors.append(trimmed)
        customAggravating = ""
    }

    private func addCustomRelieving() {
        let trimmed = customRelieving.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !relievingFactors.contains(trimmed) else { return }
        relievingFactors.append(trimmed)
        customRelieving = ""
    }

    // MARK: - Region-Specific Factor Options

    private var aggravatingOptions: [String] {
        guard let region = viewModel.currentRegion else {
            return ["Walking", "Sitting", "Lifting", "Running"]
        }
        switch region.zoneKey {
        case "head":
            return ["Looking at screens", "Bright lights", "Stress/tension", "Lack of sleep", "Bending forward", "Physical exertion", "Concentrating"]
        case "neck":
            return ["Turning head", "Looking up", "Looking down", "Sitting at desk", "Driving", "Sleeping position", "Stress/tension"]
        case "chest":
            return ["Deep breathing", "Coughing", "Pushing", "Lifting", "Reaching forward", "Lying flat", "Twisting torso"]
        case "abdomen":
            return ["Bending forward", "Coughing", "Lifting", "Sitting up", "Eating", "Twisting", "Standing long"]
        case "left_shoulder", "right_shoulder":
            return ["Reaching overhead", "Reaching behind back", "Throwing", "Pushing", "Pulling", "Sleeping on side", "Carrying bags", "Lifting"]
        case "left_upper_arm", "right_upper_arm":
            return ["Lifting", "Pushing", "Pulling", "Carrying", "Reaching overhead", "Throwing", "Push-ups"]
        case "left_elbow", "right_elbow":
            return ["Gripping", "Twisting forearm", "Lifting objects", "Typing", "Opening jars", "Pushing", "Pulling"]
        case "left_forearm", "right_forearm":
            return ["Gripping", "Twisting forearm", "Typing", "Writing", "Lifting", "Using tools", "Opening jars"]
        case "left_wrist_hand", "right_wrist_hand":
            return ["Gripping", "Typing", "Writing", "Twisting motion", "Pushing up", "Carrying", "Opening jars", "Using phone"]
        case "upper_back":
            return ["Sitting at desk", "Slouching", "Deep breathing", "Twisting", "Lifting overhead", "Reaching forward", "Driving"]
        case "lower_back":
            return ["Bending forward", "Lifting", "Sitting long", "Standing long", "Twisting", "Getting out of bed", "Walking", "Coughing/sneezing"]
        case "left_glute", "right_glute":
            return ["Sitting long", "Walking uphill", "Climbing stairs", "Running", "Squatting", "Lunging", "Standing from chair"]
        case "left_hip", "right_hip":
            return ["Walking", "Climbing stairs", "Sitting long", "Standing from chair", "Crossing legs", "Running", "Squatting", "Lying on side"]
        case "left_thigh", "right_thigh":
            return ["Walking", "Running", "Squatting", "Climbing stairs", "Kicking", "Lunging", "Stretching", "Sitting long"]
        case "left_hamstring", "right_hamstring":
            return ["Running", "Sprinting", "Bending forward", "Stretching", "Kicking", "Climbing stairs", "Sitting long"]
        case "left_knee", "right_knee":
            return ["Walking", "Climbing stairs", "Squatting", "Kneeling", "Running", "Jumping", "Going downstairs", "Sitting long"]
        case "left_calf_shin", "right_calf_shin":
            return ["Walking", "Running", "Jumping", "Climbing stairs", "Standing long", "Pointing toes", "Pushing off"]
        case "left_ankle_foot", "right_ankle_foot":
            return ["Walking", "Running", "Standing long", "Going up stairs", "Uneven surfaces", "Wearing shoes", "First steps in morning"]
        default:
            return ["Walking", "Sitting", "Lifting", "Running", "Twisting", "Standing long"]
        }
    }

    private var relievingOptions: [String] {
        guard let region = viewModel.currentRegion else {
            return ["Rest", "Ice", "Heat", "Stretching", "Medication"]
        }
        switch region.zoneKey {
        case "head":
            return ["Rest", "Quiet dark room", "Medication", "Cold compress", "Hydration", "Sleep", "Reducing screen time"]
        case "neck":
            return ["Rest", "Heat", "Gentle stretching", "Massage", "Medication", "Posture correction", "Neck support pillow"]
        case "chest":
            return ["Rest", "Ice", "Heat", "Medication", "Upright position", "Gentle breathing exercises"]
        case "abdomen":
            return ["Rest", "Heat", "Lying down", "Medication", "Gentle movement", "Avoiding triggers"]
        case "left_shoulder", "right_shoulder":
            return ["Rest", "Ice", "Heat", "Gentle stretching", "Arm support/sling", "Medication", "Avoiding overhead reach"]
        case "left_upper_arm", "right_upper_arm":
            return ["Rest", "Ice", "Heat", "Gentle stretching", "Medication", "Compression", "Avoiding lifting"]
        case "left_elbow", "right_elbow":
            return ["Rest", "Ice", "Brace/strap", "Stretching forearm", "Medication", "Avoiding gripping"]
        case "left_forearm", "right_forearm":
            return ["Rest", "Ice", "Stretching", "Forearm brace", "Medication", "Ergonomic adjustments", "Avoiding repetitive motion"]
        case "left_wrist_hand", "right_wrist_hand":
            return ["Rest", "Ice", "Wrist brace/splint", "Stretching", "Medication", "Elevation", "Ergonomic adjustments"]
        case "upper_back":
            return ["Rest", "Heat", "Stretching", "Posture correction", "Massage", "Medication", "Foam rolling"]
        case "lower_back":
            return ["Rest", "Ice", "Heat", "Gentle stretching", "Walking short", "Medication", "Lying with knees bent", "Lumbar support"]
        case "left_glute", "right_glute":
            return ["Rest", "Heat", "Stretching", "Foam rolling", "Massage", "Medication", "Gentle walking"]
        case "left_hip", "right_hip":
            return ["Rest", "Ice", "Heat", "Stretching", "Gentle walking", "Medication", "Avoiding sitting long"]
        case "left_thigh", "right_thigh":
            return ["Rest", "Ice", "Compression", "Stretching", "Foam rolling", "Medication", "Gentle walking"]
        case "left_hamstring", "right_hamstring":
            return ["Rest", "Ice", "Gentle stretching", "Compression", "Foam rolling", "Medication", "Gentle walking"]
        case "left_knee", "right_knee":
            return ["Rest", "Ice", "Elevation", "Compression wrap", "Stretching", "Medication", "Knee brace", "Avoiding stairs"]
        case "left_calf_shin", "right_calf_shin":
            return ["Rest", "Ice", "Elevation", "Compression", "Stretching calves", "Foam rolling", "Medication", "Massage"]
        case "left_ankle_foot", "right_ankle_foot":
            return ["Rest", "Ice", "Elevation", "Compression wrap", "Supportive shoes", "Medication", "Ankle brace", "Stretching calves"]
        default:
            return ["Rest", "Ice", "Heat", "Stretching", "Medication", "Elevation"]
        }
    }

    // MARK: - Treatment History

    private let imagingOptions = ["X-ray", "MRI", "CT Scan", "Ultrasound"]

    private var treatmentHistorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Treatment History")
                .font(.headline)
            Text("Optional — helps provide better recommendations")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)

            // Seen a doctor toggle
            Toggle("Have you seen a doctor for this pain?", isOn: $hasSeenDoctor)
                .font(.subheadline)
                .tint(AppColors.accent)

            if hasSeenDoctor {
                // Imaging
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Imaging done")
                        .font(.subheadline)
                        .foregroundColor(AppColors.secondaryText)
                    FlowLayout(spacing: AppSpacing.sm) {
                        ForEach(imagingOptions, id: \.self) { option in
                            ChipButton(
                                label: option,
                                isSelected: imagingDone.contains(option),
                                action: {
                                    if imagingDone.contains(option) {
                                        imagingDone.removeAll { $0 == option }
                                    } else {
                                        imagingDone.append(option)
                                    }
                                }
                            )
                        }
                    }
                }

                // Diagnosis
                Toggle("Were you given a diagnosis?", isOn: $hasDiagnosis)
                    .font(.subheadline)
                    .tint(AppColors.accent)

                if hasDiagnosis {
                    TextField("What was the diagnosis?", text: $diagnosisText)
                        .font(.subheadline)
                        .padding(AppSpacing.md)
                        .background(AppColors.inputBackground)
                        .cornerRadius(AppCorners.medium)
                }
            }

            // Currently receiving treatment
            Toggle("Currently receiving treatment?", isOn: $currentlyReceivingTreatment)
                .font(.subheadline)
                .tint(AppColors.accent)

            if currentlyReceivingTreatment {
                TextField("Describe your current treatment", text: $treatmentDetails, axis: .vertical)
                    .lineLimit(2...3)
                    .font(.subheadline)
                    .padding(AppSpacing.md)
                    .background(AppColors.inputBackground)
                    .cornerRadius(AppCorners.medium)
            }
        }
    }

    // MARK: - Additional Notes

    private var additionalNotesField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Additional Notes")
                .font(.headline)
            TextField("Enter any additional notes", text: $additionalNotes, axis: .vertical)
                .lineLimit(2...4)
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(AppCorners.medium)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        VStack(spacing: AppSpacing.sm) {
            // "Apply to All Regions" — shown on every region when multiple exist
            if viewModel.hasMultipleRegions {
                Button(action: {
                    showApplyToAllConfirmation = true
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "doc.on.doc")
                        Text("Apply to All \(viewModel.totalRegions) Regions & Analyze")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.healingGradient)
                    .cornerRadius(AppCorners.large)
                }
            }

            // Existing navigation row
            HStack(spacing: AppSpacing.md) {
                if viewModel.currentRegionIndex > 0 {
                    Button(action: {
                        guard let assessment = buildAssessment() else { return }
                        viewModel.saveAndGoBack(assessment)
                    }) {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                            Text("Back")
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                if viewModel.isLastRegion {
                    Button(action: {
                        guard let assessment = buildAssessment() else { return }
                        viewModel.saveAndAnalyze(assessment)
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: "sparkles")
                            Text("Review & Analyze")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(action: {
                        guard let assessment = buildAssessment() else { return }
                        viewModel.saveAndAdvance(assessment)
                    }) {
                        HStack(spacing: AppSpacing.sm) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: - Helpers

    private var customPainDescriptionField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Describe Your Pain")
                .font(.headline)
            Text("Optional — describe what your pain feels like in your own words")
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
            TextField("e.g., feels like pressure, stiffness in the morning...", text: $customPainDescription, axis: .vertical)
                .lineLimit(2...3)
                .padding(AppSpacing.md)
                .background(AppColors.inputBackground)
                .cornerRadius(AppCorners.medium)
        }
    }

    private func iconName(for type: PainAssessment.PainType) -> String {
        switch type {
        case .sharp: return "bolt.fill"
        case .dull: return "cloud.fill"
        case .burning: return "flame.fill"
        case .throbbing: return "waveform.path.ecg"
        case .aching: return "tortoise.fill"
        case .stabbing: return "scissors"
        case .tingling: return "sparkles"
        case .tightness: return "arrow.up.left.and.arrow.down.right"
        }
    }

    private var painColor: Color {
        switch Int(painIntensity) {
        case 1...3: return AppColors.success
        case 4...6: return AppColors.warning
        default: return AppColors.danger
        }
    }

    private var painDescription: String {
        switch Int(painIntensity) {
        case 1...3: return "Mild"
        case 4...6: return "Moderate"
        case 7...8: return "Severe"
        default: return "Extreme"
        }
    }
}

// ChipButton and FlowLayout moved to DesignSystem.swift
