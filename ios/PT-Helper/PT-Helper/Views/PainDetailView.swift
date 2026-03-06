import SwiftUI

struct PainDetailView: View {
    @ObservedObject var viewModel: InjuryAnalysisViewModel
    @State private var selectedPainType: PainAssessment.PainType = .sharp
    @State private var customPainDescription: String = ""
    @State private var painIntensity: Double = 5
    @State private var selectedPainDuration: PainAssessment.PainDuration = .today
    @State private var selectedPainFrequency: PainAssessment.PainFrequency = .constant
    @State private var selectedPainOnset: PainAssessment.PainOnset = .sudden
    @State private var aggravatingFactors: [String] = []
    @State private var relievingFactors: [String] = []
    @State private var customAggravating: String = ""
    @State private var customRelieving: String = ""
    @State private var additionalNotes: String = ""
    @State private var showApplyToAllConfirmation: Bool = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

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
                                        .background(Color.blue)
                                        .cornerRadius(AppCorners.medium)
                                    Spacer()
                                    // Encouraging micro-copy
                                    Text(encouragingText)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
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
                                            .fill(Color.blue)
                                            .frame(width: geo.size.width * formCompletionProgress, height: 3)
                                            .animation(AppAnimations.smooth, value: formCompletionProgress)
                                    }
                                }
                                .frame(height: 3)
                            }
                            .id("top")
                        }

                        if let currentRegion = viewModel.currentRegion {
                            CardSection(icon: "figure.walk", color: .blue, title: "Assessing: \(currentRegion.name)") {
                                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                                    painTypeSelection
                                    customPainDescriptionField
                                    painIntensitySlider
                                    painDurationPicker
                                    painFrequencyPicker
                                    painOnsetPicker
                                    aggravatingFactorsSelection
                                    relievingFactorsSelection
                                    additionalNotesField
                                }
                            }
                            navigationButtons
                        } else {
                            Text("No region selected")
                                .foregroundColor(.secondary)
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
        return PainAssessment(
            id: UUID(),
            selectedRegion: region,
            painType: selectedPainType,
            customPainDescription: trimmedDescription.isEmpty ? nil : trimmedDescription,
            painIntensity: Int(painIntensity),
            painDuration: selectedPainDuration,
            painFrequency: selectedPainFrequency,
            painOnset: selectedPainOnset,
            aggravatingFactors: aggravatingFactors,
            relievingFactors: relievingFactors,
            additionalNotes: additionalNotes
        )
    }

    /// Restore form fields from a previously saved assessment, or reset to defaults.
    private func restoreFormState() {
        if let saved = viewModel.currentAssessment {
            selectedPainType = saved.painType
            customPainDescription = saved.customPainDescription ?? ""
            painIntensity = Double(saved.painIntensity)
            selectedPainDuration = saved.painDuration
            selectedPainFrequency = saved.painFrequency
            selectedPainOnset = saved.painOnset
            aggravatingFactors = saved.aggravatingFactors
            relievingFactors = saved.relievingFactors
            additionalNotes = saved.additionalNotes ?? ""
        } else {
            selectedPainType = .sharp
            customPainDescription = ""
            painIntensity = 5
            selectedPainDuration = .today
            selectedPainFrequency = .constant
            selectedPainOnset = .sudden
            aggravatingFactors = []
            relievingFactors = []
            additionalNotes = ""
        }
    }

    // MARK: - Form Completion Tracking

    private var formCompletionFields: Int {
        var count = 0
        if painIntensity != 5 { count += 1 }  // intensity changed from default
        if !aggravatingFactors.isEmpty { count += 1 }
        if !relievingFactors.isEmpty { count += 1 }
        if !additionalNotes.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        if !customPainDescription.trimmingCharacters(in: .whitespaces).isEmpty { count += 1 }
        count += 1 // pain type always selected
        count += 1 // duration always selected
        count += 1 // frequency always selected
        count += 1 // onset always selected
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

    // MARK: - Pain Type (grid of icon+label chips)

    private var painTypeSelection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Type")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppSpacing.sm) {
                ForEach(PainAssessment.PainType.allCases, id: \.self) { type in
                    let isSelected = selectedPainType == type
                    Button(action: { selectedPainType = type }) {
                        VStack(spacing: AppSpacing.xs) {
                            Image(systemName: iconName(for: type))
                                .font(.system(size: 18))
                            Text(type.displayName)
                                .font(.caption2)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundColor(isSelected ? .white : .blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.sm)
                        .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                        .cornerRadius(AppCorners.small)
                    }
                }
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
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
                Spacer()
                Text("Severe")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Pain Duration (chip selector)

    private var painDurationPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Duration")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(PainAssessment.PainDuration.allCases, id: \.self) { duration in
                    ChipButton(
                        label: duration.displayName,
                        isSelected: selectedPainDuration == duration,
                        action: { selectedPainDuration = duration }
                    )
                }
            }
        }
    }

    // MARK: - Pain Frequency (chip selector)

    private var painFrequencyPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Frequency")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(PainAssessment.PainFrequency.allCases, id: \.self) { frequency in
                    ChipButton(
                        label: frequency.displayName,
                        isSelected: selectedPainFrequency == frequency,
                        action: { selectedPainFrequency = frequency }
                    )
                }
            }
        }
    }

    // MARK: - Pain Onset (chip selector)

    private var painOnsetPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Pain Onset")
                .font(.headline)
            FlowLayout(spacing: AppSpacing.sm) {
                ForEach(PainAssessment.PainOnset.allCases, id: \.self) { onset in
                    ChipButton(
                        label: onset.displayName,
                        isSelected: selectedPainOnset == onset,
                        action: { selectedPainOnset = onset }
                    )
                }
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
                        .foregroundColor(customAggravating.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
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
                        .foregroundColor(customRelieving.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
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
            // "Apply to All Regions" — only on first region when multiple exist
            if viewModel.isFirstRegion && viewModel.hasMultipleRegions {
                Button(action: {
                    showApplyToAllConfirmation = true
                }) {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "doc.on.doc")
                        Text("Apply to All \(viewModel.totalRegions) Regions")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
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
                .foregroundColor(.secondary)
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
        case 1...3: return .green
        case 4...6: return .orange
        default: return .red
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

// MARK: - Chip Button

private struct ChipButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(isSelected ? Color.blue : AppColors.inputBackground)
                .cornerRadius(AppCorners.small)
                .overlay(
                    RoundedRectangle(cornerRadius: AppCorners.small)
                        .stroke(isSelected ? Color.clear : AppColors.subtleBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: ProposedViewSize(width: bounds.width, height: bounds.height), subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangementResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + rowHeight
        return ArrangementResult(
            size: CGSize(width: maxWidth, height: totalHeight),
            positions: positions,
            sizes: sizes
        )
    }

    private struct ArrangementResult {
        let size: CGSize
        let positions: [CGPoint]
        let sizes: [CGSize]
    }
}
