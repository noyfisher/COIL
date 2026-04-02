import SwiftUI

/// Four-question lifestyle questionnaire that feeds the body risk AI analysis.
struct BodyRiskAssessmentView: View {
    @ObservedObject var vm: BodyRiskViewModel
    let profile: UserProfile

    @State private var navigateToResult = false

    var body: some View {
        ZStack {
            AppColors.bgGradient.ignoresSafeArea()

            if vm.isAnalyzing {
                analyzingView
            } else {
                formView
            }
        }
        .navigationTitle("Risk Assessment")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(vm.isAnalyzing)
        .navigationDestination(isPresented: $navigateToResult) {
            if let result = vm.result {
                BodyRiskResultView(result: result, profile: profile, vm: vm)
            }
        }
        .onChange(of: vm.result?.id) { _, resultId in
            navigateToResult = resultId != nil
        }
    }

    // MARK: - Form

    private var formView: some View {
        ScrollView {
            VStack(spacing: AppSpacing.xl) {
                headerSection
                activitySection
                seatedHoursSection
                sportSection
                historySection
                errorSection
                analyzeButton
            }
            .padding(AppSpacing.lg)
            .padding(.bottom, AppSpacing.xxxl)
        }
    }

    private var headerSection: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 36))
                .foregroundColor(AppColors.accent)
            Text("Discover Your Risk Areas")
                .font(AppFonts.sectionTitle)
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.center)
            Text("Answer 4 quick questions and we'll identify the body regions most likely to need attention — before they become a problem.")
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, AppSpacing.md)
    }

    private var activitySection: some View {
        CardSection(icon: "figure.stand.dress", color: AppColors.accent, title: "Primary Daily Activity", required: true) {
            VStack(spacing: AppSpacing.sm) {
                ForEach(PrimaryActivity.allCases, id: \.self) { activity in
                    Button {
                        vm.primaryActivity = activity
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: activity.icon)
                                .frame(width: 24)
                                .foregroundColor(vm.primaryActivity == activity ? AppColors.accent : AppColors.mutedText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.displayName)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(AppColors.primaryText)
                                Text(activity.description)
                                    .font(.caption)
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            Spacer()
                            if vm.primaryActivity == activity {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(AppColors.accent)
                            }
                        }
                        .padding(AppSpacing.md)
                        .background(
                            vm.primaryActivity == activity
                                ? AppColors.accentTint
                                : AppColors.inputBackground
                        )
                        .cornerRadius(AppCorners.medium)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.medium)
                                .stroke(
                                    vm.primaryActivity == activity ? AppColors.accent : AppColors.subtleBorder,
                                    lineWidth: vm.primaryActivity == activity ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var seatedHoursSection: some View {
        CardSection(icon: "chair.lounge.fill", color: AppColors.warning, title: "Hours Seated Per Day") {
            VStack(spacing: AppSpacing.md) {
                HStack {
                    Text("0 hrs")
                        .font(.caption)
                        .foregroundColor(AppColors.mutedText)
                    Spacer()
                    Text("\(Int(vm.hoursSeated)) hrs / day")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Text("12 hrs")
                        .font(.caption)
                        .foregroundColor(AppColors.mutedText)
                }
                Slider(value: $vm.hoursSeated, in: 0...12, step: 0.5)
                    .tint(AppColors.accent)
            }
        }
    }

    private var sportSection: some View {
        CardSection(icon: "sportscourt.fill", color: AppColors.accent, title: "Dominant Sport or Hobby") {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                StyledTextField(placeholder: "e.g. Running, Tennis, Cycling (optional)", text: $vm.sportOrHobby)
                Text("Leave blank if you don't have a regular sport or hobby.")
                    .font(.caption)
                    .foregroundColor(AppColors.mutedText)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        let allInjuries = profile.injuries + profile.surgeries.compactMap { s -> UserProfile.Injury? in
            guard let area = s.bodyArea, !area.isEmpty else { return nil }
            return UserProfile.Injury(
                bodyArea: "\(s.name) (surgery)",
                description: s.name,
                isCurrent: s.recoveryStatus == "Still recovering",
                year: s.year
            )
        }

        if !allInjuries.isEmpty {
            CardSection(icon: "clock.arrow.circlepath", color: AppColors.secondaryText, title: "Your Health History") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("We'll factor in your history when assessing risk.")
                        .font(.caption)
                        .foregroundColor(AppColors.mutedText)
                    FlowLayout(spacing: AppSpacing.sm) {
                        ForEach(allInjuries.prefix(8), id: \.bodyArea) { injury in
                            Text(injury.bodyArea)
                                .font(.caption.weight(.medium))
                                .foregroundColor(AppColors.secondaryText)
                                .padding(.horizontal, AppSpacing.sm)
                                .padding(.vertical, 4)
                                .background(AppColors.elevatedSurface)
                                .cornerRadius(AppCorners.pill)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = vm.error {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.danger)
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(AppColors.danger)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.danger.opacity(0.08))
            .cornerRadius(AppCorners.medium)
        }
    }

    private var analyzeButton: some View {
        Button {
            Task { await vm.analyze(profile: profile) }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass.circle.fill")
                Text("Assess My Risk")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.lg)
            .background(AppColors.ctaBackground)
            .foregroundColor(AppColors.ctaText)
            .cornerRadius(AppCorners.large)
        }
        .accessibilityIdentifier("prevention.startRiskAssessmentButton")
    }

    // MARK: - Analyzing View

    private var analyzingView: some View {
        VStack(spacing: AppSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.accentTint)
                    .frame(width: 100, height: 100)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppColors.accent)
                    .symbolEffect(.pulse)
            }

            VStack(spacing: AppSpacing.sm) {
                Text("Analyzing your risk profile…")
                    .font(AppFonts.sectionTitle)
                    .foregroundColor(AppColors.primaryText)
                Text("We're reviewing your lifestyle and history to identify areas that need attention.")
                    .font(.subheadline)
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xl)
            }

            ProgressView()
                .tint(AppColors.accent)
                .scaleEffect(1.2)

            Spacer()
        }
        .padding(AppSpacing.xl)
    }
}

