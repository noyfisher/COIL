import SwiftUI

/// Tab 0: Assess — "What do you need?"
/// Dual gateway with two hero cards: "Something Hurts" (pain path) and "Improve My Life" (wellness path).
/// Both paths lead to AI analysis → plan generation → save to My Plan tab.
struct AssessTab: View {
    @EnvironmentObject private var tabSelection: TabSelection
    @ObservedObject private var profileService = UserProfileService.shared

    // Health check state for inactivity detection
    @State private var showQuickUpdate = false
    @State private var healthCheckDismissed = false

    private var needsHealthCheck: Bool {
        guard !healthCheckDismissed else { return false }
        if let months = profileService.monthsSinceLastActivity(), months >= 3 {
            return true
        }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Health check banner for inactive users
                        if needsHealthCheck {
                            healthCheckBanner
                        }

                        // Personalized greeting
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text(greetingText)
                                .font(.subheadline)
                                .foregroundColor(AppColors.secondaryText)
                            Text(greetingName)
                                .font(AppFonts.heroTitle)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Gateway header
                        Text("What can we help with?")
                            .font(AppFonts.sectionTitle)
                            .foregroundColor(AppColors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Dual gateway cards
                        HStack(spacing: AppSpacing.md) {
                            // Pain pathway
                            NavigationLink(destination: BodyMap3DView()) {
                                gatewayCard(
                                    icon: "figure.run.circle",
                                    title: "Something Hurts",
                                    subtitle: "Assess pain and get a recovery plan",
                                    accentColor: AppColors.danger
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("assess.somethingHurtsButton")

                            // Wellness pathway
                            if let profile = profileService.profile {
                                NavigationLink(destination: WellnessGoalPickerView(userProfile: profile)) {
                                    gatewayCard(
                                        icon: "sparkles",
                                        title: "Improve My Life",
                                        subtitle: "Sleep, posture, mobility & more",
                                        accentColor: AppColors.accent
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("assess.improveLifeButton")
                            }
                        }

                        // Helpful context
                        Text("Both paths create a personalized plan with guided workouts")
                            .font(.caption)
                            .foregroundColor(AppColors.mutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.lg)
                }
            }
            .navigationTitle("Assess")
            .navigationBarTitleDisplayMode(.large)
        }
        .fullScreenCover(isPresented: $showQuickUpdate) {
            QuickHealthUpdateView {
                showQuickUpdate = false
                healthCheckDismissed = true
            }
        }
        .trackScreen("AssessTab")
    }

    // MARK: - Gateway Card

    private func gatewayCard(icon: String, title: String, subtitle: String, accentColor: Color) -> some View {
        VStack(spacing: AppSpacing.md) {
            Spacer(minLength: AppSpacing.md)

            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(accentColor)
                .frame(width: 72, height: 72)
                .background(Circle().fill(accentColor.opacity(0.10)))

            Text(title)
                .font(.system(.title3, design: .serif).weight(.bold))
                .foregroundColor(AppColors.primaryText)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: AppSpacing.md)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.horizontal, AppSpacing.md)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.card)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    // MARK: - Greeting Helpers

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
                .font(.caption)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: AppSpacing.md) {
                Button("Update Profile") {
                    showQuickUpdate = true
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(AppColors.accent)

                Button("Skip") {
                    healthCheckDismissed = true
                    UserProfileService.shared.recordActivity()
                }
                .font(.caption)
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
