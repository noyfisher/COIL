import SwiftUI
import FirebaseAuth

struct HomeTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var workoutViewModel: WorkoutViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @ObservedObject private var streakService = StreakService.shared
    @State private var showOnboarding = false
    @State private var showSettings = false
    @State private var animateEntrance = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Hero greeting card
                        heroGreeting
                            .padding(.horizontal, AppSpacing.xl)
                            .opacity(animateEntrance ? 1 : 0)
                            .offset(y: animateEntrance ? 0 : 20)

                        // At-a-glance stats
                        statsRow
                            .padding(.horizontal, AppSpacing.xl)
                            .opacity(animateEntrance ? 1 : 0)
                            .offset(y: animateEntrance ? 0 : 20)
                            .animation(AppAnimations.smooth.delay(0.1), value: animateEntrance)

                        // Quick Actions
                        SectionHeader(icon: "bolt.fill", color: .blue, title: "Quick Actions")
                            .padding(.horizontal, AppSpacing.xl)
                            .opacity(animateEntrance ? 1 : 0)
                            .animation(AppAnimations.smooth.delay(0.2), value: animateEntrance)

                        VStack(spacing: AppSpacing.md) {
                            QuickActionButton(
                                icon: "heart.text.clipboard",
                                gradientColors: [.blue, .cyan],
                                title: "Update Health Info",
                                subtitle: "Review or update your health profile",
                                action: { showOnboarding = true }
                            )
                            .opacity(animateEntrance ? 1 : 0)
                            .offset(y: animateEntrance ? 0 : 15)
                            .animation(AppAnimations.smooth.delay(0.25), value: animateEntrance)

                            QuickActionCard(
                                icon: "note.text",
                                gradientColors: [.green, .mint],
                                title: "Recovery Notes",
                                subtitle: "Track your recovery journey",
                                destination: NotesView()
                            )
                            .opacity(animateEntrance ? 1 : 0)
                            .offset(y: animateEntrance ? 0 : 15)
                            .animation(AppAnimations.smooth.delay(0.35), value: animateEntrance)

                            QuickActionCard(
                                icon: "figure.strengthtraining.traditional",
                                gradientColors: [.purple, .indigo],
                                title: "Log Workout",
                                subtitle: "Record a workout session",
                                destination: WorkoutSessionView()
                            )
                            .opacity(animateEntrance ? 1 : 0)
                            .offset(y: animateEntrance ? 0 : 15)
                            .animation(AppAnimations.smooth.delay(0.45), value: animateEntrance)
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        // Recent Plans preview (compact)
                        if !savedPlansViewModel.rehabPlans.isEmpty {
                            recentPlansPreview
                                .padding(.horizontal, AppSpacing.xl)
                                .opacity(animateEntrance ? 1 : 0)
                                .offset(y: animateEntrance ? 0 : 15)
                                .animation(AppAnimations.smooth.delay(0.55), value: animateEntrance)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, AppSpacing.md)
                }
                .refreshable {
                    savedPlansViewModel.fetchRehabPlans()
                    await UserProfileService.shared.reload()
                    let haptic = UINotificationFeedbackGenerator()
                    haptic.notificationOccurred(.success)
                }
            }
            .navigationTitle("PT Helper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        // Profile avatar
                        Text(avatarInitials)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(AppColors.coolGradient)
                            )
                    }
                }
            }
            .onAppear {
                withAnimation(AppAnimations.smooth) {
                    animateEntrance = true
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingEditView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    userName: profileName,
                    onEditProfile: { showOnboarding = true }
                )
            }
        }
        .id(tabSelection.homeNavigationId)
        .trackScreen("Home")
    }

    // MARK: - Hero Greeting

    private var heroGreeting: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(greetingText)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
            Text(profileName.isEmpty ? "Welcome!" : "Hi, \(profileName)!")
                .font(AppFonts.heroTitle)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppCorners.xl)
                .fill(AppColors.coolGradient)
        )
        .shadow(color: .blue.opacity(0.15), radius: 12, y: 6)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: AppSpacing.md) {
            miniStatCard(
                icon: "list.clipboard.fill",
                color: .purple,
                value: "\(savedPlansViewModel.rehabPlans.count)",
                label: "Active Plans"
            )

            miniStatCard(
                icon: "waveform.path.ecg",
                color: lastPainColor,
                value: lastPainText,
                label: "Last Pain"
            )

            NavigationLink(destination: AchievementsView(streakService: streakService)) {
                StreakBadgeView(streakService: streakService)
            }
            .buttonStyle(.plain)
        }
    }

    private func miniStatCard(icon: String, color: Color, value: String, label: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            Text(value)
                .font(AppFonts.statNumber)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private var lastPainText: String {
        guard let lastSession = workoutViewModel.sessions.last else { return "-" }
        return "\(Int(lastSession.painLevel))"
    }

    private var lastPainColor: Color {
        guard let lastSession = workoutViewModel.sessions.last else { return .secondary }
        switch Int(lastSession.painLevel) {
        case 0...3: return .green
        case 4...6: return .orange
        default: return .red
        }
    }

    private var sessionsThisWeek: Int {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return workoutViewModel.sessions.filter { $0.date >= startOfWeek }.count
    }

    // MARK: - Recent Plans Preview

    private var recentPlansPreview: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                SectionHeader(icon: "list.clipboard.fill", color: .purple, title: "Recent Plans")
                Button("See All") {
                    tabSelection.selectedTab = 2
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.blue)
            }

            ForEach(savedPlansViewModel.rehabPlans.prefix(2)) { plan in
                NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(plan.planName)
                                .font(AppFonts.cardTitle)
                                .foregroundColor(.primary)
                            Text("\(plan.exercises.count) exercises")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    .padding(AppSpacing.lg)
                    .background(AppColors.cardBackground)
                    .cornerRadius(AppCorners.card)
                    .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
                }
            }
        }
    }

    // MARK: - Helpers

    /// User's display name from the shared profile service (no extra Firestore read)
    private var profileName: String {
        UserProfileService.shared.firstName
    }

    private var avatarInitials: String {
        let parts = profileName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return profileName.isEmpty ? "PT" : String(profileName.prefix(2)).uppercased()
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

// MARK: - Onboarding Edit Wrapper (for updating profile from home)
struct OnboardingEditView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = OnboardingViewModel()
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            if isLoading {
                LoadingStateView(message: "Loading your profile...")
            } else {
                VStack(spacing: 0) {
                    // Top bar with close button
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Text("Update Profile")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.sm)

                    // Step indicator
                    VStack(spacing: AppSpacing.lg) {
                        Text("Step \(viewModel.currentStep) of 6")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.xs)
                            .background(Color.blue)
                            .cornerRadius(AppCorners.medium)

                        HStack(spacing: 6) {
                            ForEach(1...6, id: \.self) { step in
                                Capsule()
                                    .fill(step <= viewModel.currentStep ? Color.blue : Color.gray.opacity(0.25))
                                    .frame(height: 5)
                                    .animation(.spring(response: 0.35), value: viewModel.currentStep)
                            }
                        }
                        .padding(.horizontal, 32)

                        Text(stepTitle)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(stepSubtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.bottom, 8)

                    // Step content
                    TabView(selection: $viewModel.currentStep) {
                        BasicInfoStepView(viewModel: viewModel).tag(1)
                        MedicalHistoryStepView(viewModel: viewModel).tag(2)
                        SurgicalHistoryStepView(viewModel: viewModel).tag(3)
                        InjuryHistoryStepView(viewModel: viewModel).tag(4)
                        ActivityLevelStepView(viewModel: viewModel).tag(5)
                        ProfileReviewStepView(viewModel: viewModel, onComplete: {
                            dismiss()
                        }).tag(6)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: viewModel.currentStep)

                    // Navigation buttons
                    HStack(spacing: AppSpacing.md) {
                        if viewModel.currentStep > 1 {
                            Button(action: { viewModel.previousStep() }) {
                                HStack(spacing: AppSpacing.xs) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 13, weight: .bold))
                                    Text("Back")
                                }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        if viewModel.currentStep < 6 {
                            Button(action: {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                viewModel.nextStep()
                            }) {
                                HStack(spacing: AppSpacing.xs) {
                                    Text("Continue")
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .bold))
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(isDisabled: !viewModel.canProceedFromCurrentStep))
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
        }
        .onAppear {
            viewModel.loadProfile { success in
                viewModel.currentStep = 1
                isLoading = false
            }
        }
    }

    private var stepTitle: String {
        switch viewModel.currentStep {
        case 1: return "About You"
        case 2: return "Medical History"
        case 3: return "Past Surgeries"
        case 4: return "Injuries"
        case 5: return "Activity Level"
        case 6: return "Review & Submit"
        default: return ""
        }
    }

    private var stepSubtitle: String {
        switch viewModel.currentStep {
        case 1: return "Let's start with some basic information"
        case 2: return "Select any conditions that apply to you"
        case 3: return "Tell us about any past surgical procedures"
        case 4: return "Any current or previous injuries?"
        case 5: return "How active are you day to day?"
        case 6: return "Make sure everything looks correct"
        default: return ""
        }
    }
}
