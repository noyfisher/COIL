import SwiftUI

/// Tab 0: Assess — "What do you need?"
/// Dual gateway with two hero cards: "Something Hurts" (pain path) and "Improve My Life" (wellness path).
struct AssessTab: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @EnvironmentObject private var analysisStore: AnalysisResultStore
    @ObservedObject private var profileService = UserProfileService.shared

    @State private var showQuickUpdate = false
    @State private var healthCheckDismissed = false
    @State private var navigateToBodyMap = false
    @State private var navigateToWellness = false
    @State private var navigateToLastAnalysis = false

    private var needsHealthCheck: Bool {
        guard !healthCheckDismissed else { return false }
        if let months = profileService.monthsSinceLastActivity(), months >= 3 { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {

                        if needsHealthCheck { healthCheckBanner }

                        // Greeting
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greetingText)
                                .font(Font.custom("Inter-Regular", size: 12))
                                .foregroundColor(AppColors.mutedText)
                            Text(greetingName)
                                .font(Font.custom("BarlowCondensed-Black", size: 28))
                                .textCase(.uppercase)
                                .kerning(0.5)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Section header
                        MVVCDividerHeader(title: "What Can We Help With?")

                        // Gateway cards
                        HStack(alignment: .top, spacing: AppSpacing.md) {
                            Button {
                                AnalyticsService.shared.log(.assessmentGatewayChosen,
                                    parameters: ["path": "injury"])
                                SessionLogger.shared.logUserAction(.buttonTapped,
                                    action: "assessmentGatewayChosen",
                                    metadata: ["path": "injury"])
                                navigateToBodyMap = true
                            } label: {
                                darkGatewayCard(
                                    icon: "figure.run.circle",
                                    badge: "Start Assessment",
                                    title: "Something Hurts",
                                    subtitle: "Assess pain and get a recovery plan"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("assess.somethingHurtsButton")

                            if let profile = profileService.profile {
                                Button {
                                    AnalyticsService.shared.log(.assessmentGatewayChosen,
                                        parameters: ["path": "wellness"])
                                    SessionLogger.shared.logUserAction(.buttonTapped,
                                        action: "assessmentGatewayChosen",
                                        metadata: ["path": "wellness"])
                                    navigateToWellness = true
                                } label: {
                                    lightGatewayCard(
                                        icon: "sparkles",
                                        label: "Get Started",
                                        title: "Improve My Life",
                                        subtitle: "Sleep, posture, mobility & more"
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("assess.improveLifeButton")
                            }
                        }
                        .navigationDestination(isPresented: $navigateToBodyMap) {
                            BodyMap3DView()
                        }
                        .navigationDestination(isPresented: $navigateToWellness) {
                            if let profile = profileService.profile {
                                WellnessGoalPickerView(userProfile: profile)
                            }
                        }

                        Text("Both paths create a personalized plan with guided workouts")
                            .font(Font.custom("Inter-Regular", size: 11))
                            .foregroundColor(AppColors.mutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        // Last analysis re-entry point — a completed analysis persists
                        // across relaunches and must stay reachable (F2).
                        if let lastResult = analysisStore.lastResult {
                            MVVCDividerHeader(title: "Your Last Analysis")

                            Button {
                                SessionLogger.shared.logUserAction(.buttonTapped,
                                    action: "lastAnalysisOpened",
                                    metadata: ["topCondition": lastResult.conditions.first?.commonName ?? "none"])
                                navigateToLastAnalysis = true
                            } label: {
                                lastAnalysisCard(for: lastResult)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("assess.lastAnalysisCard")
                            .navigationDestination(isPresented: $navigateToLastAnalysis) {
                                AnalysisResultView(analysisResult: lastResult)
                            }
                        }

                        // Quick actions
                        MVVCDividerHeader(title: "Quick Actions")

                        VStack(spacing: AppSpacing.sm) {
                            QuickActionButton(
                                icon: "person.crop.circle",
                                gradientColors: [AppColors.accent],
                                title: "Update Health Info",
                                subtitle: "Keep your profile current",
                                action: { showQuickUpdate = true }
                            )

                            NavigationLink(destination: NotesView()) {
                                QuickActionCard(
                                    icon: "note.text",
                                    gradientColors: [AppColors.warning],
                                    title: "Recovery Notes",
                                    subtitle: "Log symptoms and observations",
                                    destination: NotesView()
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: WorkoutSessionView()) {
                                QuickActionCard(
                                    icon: "figure.strengthtraining.traditional",
                                    gradientColors: [Color.purple],
                                    title: "Log Workout",
                                    subtitle: "Record a session",
                                    destination: WorkoutSessionView()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.xxxl)
                }
            }
            .navigationTitle("Assess")
            .navigationBarTitleDisplayMode(.inline)
            .mvvcNavBar()
        }
        .fullScreenCover(isPresented: $showQuickUpdate) {
            QuickHealthUpdateView {
                showQuickUpdate = false
                healthCheckDismissed = true
            }
        }
        .trackScreen("AssessTab")
    }

    // MARK: - Dark Gateway Card ("Something Hurts")

    private func darkGatewayCard(icon: String, badge: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AppColors.accent.frame(height: 4)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.accent)
                    .padding(.top, AppSpacing.xs)

                Spacer(minLength: AppSpacing.sm)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Font.custom("BarlowCondensed-Black", size: 16))
                        .textCase(.uppercase)
                        .kerning(0.3)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(Font.custom("Inter-Regular", size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    MVVCRedBadge(text: badge)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(AppColors.darkSurface)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.14), radius: 16, y: 4)
    }

    // MARK: - Light Gateway Card ("Improve My Life")

    private func lightGatewayCard(icon: String, label: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AppColors.accent.opacity(0.10).frame(height: 4)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.accent)
                    .padding(.top, AppSpacing.xs)

                Spacer(minLength: AppSpacing.sm)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Font.custom("BarlowCondensed-Black", size: 16))
                        .textCase(.uppercase)
                        .kerning(0.3)
                        .foregroundColor(AppColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(Font.custom("Inter-Regular", size: 11))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(label)
                        .font(Font.custom("BarlowCondensed-Bold", size: 12))
                        .textCase(.uppercase)
                        .kerning(0.5)
                        .foregroundColor(AppColors.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.accent)
                }
            }
            .padding(AppSpacing.lg)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    // MARK: - Last Analysis Card

    private func lastAnalysisCard(for result: AnalysisResult) -> some View {
        let topCondition = result.conditions.first
        let strength = topCondition.map { ConfidenceCalibrator.matchStrength(for: $0.confidence) }

        return HStack(spacing: 14) {
            Image(systemName: "stethoscope")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppColors.accent)
                .frame(width: 40, height: 40)
                .background(AppColors.accent.opacity(0.12))
                .cornerRadius(AppCorners.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(topCondition?.commonName ?? "Analysis Results")
                    .font(Font.custom("Inter-SemiBold", size: 14))
                    .foregroundColor(AppColors.primaryText)

                HStack(spacing: AppSpacing.xs) {
                    if let strength {
                        Text(strength.rawValue)
                            .font(Font.custom("Inter-SemiBold", size: 12))
                            .foregroundColor(matchColor(strength))
                        Text("•")
                            .font(Font.custom("Inter-Regular", size: 12))
                            .foregroundColor(AppColors.mutedText)
                    }
                    Text(result.generatedDate.formatted(.relative(presentation: .named)))
                        .font(Font.custom("Inter-Regular", size: 12))
                        .foregroundColor(AppColors.secondaryText)
                }

                Text("View results & build a rehab plan")
                    .font(Font.custom("Inter-Regular", size: 11))
                    .foregroundColor(AppColors.mutedText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.accent)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 14)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    private func matchColor(_ strength: MatchStrength) -> Color {
        switch strength {
        case .strong: return AppColors.success
        case .moderate: return AppColors.warning
        case .weak: return AppColors.mutedText
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private var greetingName: String {
        let name = profileService.profile?.firstName ?? ""
        return name.isEmpty ? "Welcome!" : "Hi, \(name)!"
    }

    // MARK: - Health Check Banner

    private var healthCheckBanner: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "hand.wave.fill")
                    .foregroundColor(AppColors.warning)
                Text("Welcome back!")
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)
            }

            Text("It's been a while. Would you like to update your health profile before starting?")
                .font(Font.custom("Inter-Regular", size: 12))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: AppSpacing.md) {
                Button("Update Profile") { showQuickUpdate = true }
                    .font(Font.custom("Inter-SemiBold", size: 12))
                    .foregroundColor(AppColors.accent)

                Button("Skip") {
                    healthCheckDismissed = true
                    UserProfileService.shared.recordActivity()
                }
                .font(Font.custom("Inter-Regular", size: 12))
                .foregroundColor(AppColors.mutedText)
            }
        }
        .padding(AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(AppColors.warning.opacity(0.3), lineWidth: 1)
        )
    }
}
