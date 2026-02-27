import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ContentView: View {
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @State private var userName: String = ""
    @State private var showOnboarding = false
    @State private var navigationId = UUID()
    @State private var planToDelete: RehabPlan? = nil
    @State private var showDeleteConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        // Welcome header
                        VStack(spacing: 6) {
                            Text(greetingText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(userName.isEmpty ? "Welcome!" : "Hi, \(userName)!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppSpacing.xl)
                        .padding(.bottom, AppSpacing.sm)

                        // Quick Actions header
                        SectionHeader(icon: "bolt.fill", color: .blue, title: "Quick Actions")
                            .padding(.horizontal, AppSpacing.xl)

                        // Quick actions
                        VStack(spacing: AppSpacing.md) {
                            QuickActionCard(
                                icon: "figure.run.circle",
                                gradientColors: [.red, .orange],
                                title: "Injury Analysis",
                                subtitle: "Assess pain and get guidance",
                                destination: BodyMapView()
                            )

                            QuickActionButton(
                                icon: "heart.text.clipboard",
                                gradientColors: [.blue, .cyan],
                                title: "Update Health Info",
                                subtitle: "Review or update your health profile",
                                action: { showOnboarding = true }
                            )

                            QuickActionCard(
                                icon: "note.text",
                                gradientColors: [.green, .mint],
                                title: "Recovery Notes",
                                subtitle: "Track your recovery journey",
                                destination: NotesView()
                            )

                            QuickActionCard(
                                icon: "figure.strengthtraining.traditional",
                                gradientColors: [.purple, .indigo],
                                title: "Log Workout",
                                subtitle: "Record a workout session",
                                destination: WorkoutSessionView()
                            )

                            QuickActionCard(
                                icon: "chart.line.uptrend.xyaxis",
                                gradientColors: [.teal, .blue],
                                title: "Progress",
                                subtitle: "View your pain trends and stats",
                                destination: ProgressChartView()
                            )
                        }
                        .padding(.horizontal, AppSpacing.xl)

                        // My Rehab Plans section
                        myRehabPlansSection
                            .padding(.horizontal, AppSpacing.xl)

                        Spacer(minLength: 40)

                        // Sign out
                        Button(action: {
                            showSignOutConfirmation = true
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                        }
                        .buttonStyle(DestructiveButtonStyle())

                        // App version
                        Text(appVersionText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.bottom, AppSpacing.xxl)
                    }
                }
                .refreshable {
                    savedPlansViewModel.fetchRehabPlans()
                    fetchUserName()
                }
            }
            .navigationTitle("PT Helper")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                fetchUserName()
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingEditView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { _ in
                navigationId = UUID()
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    do {
                        try Auth.auth().signOut()
                    } catch {
                        signOutErrorMessage = error.localizedDescription
                        showSignOutError = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage)
            }
        }
        .id(navigationId)
    }

    // MARK: - My Rehab Plans

    private var myRehabPlansSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SectionHeader(icon: "list.clipboard.fill", color: .purple, title: "My Rehab Plans")

            if savedPlansViewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, AppSpacing.xl)
            } else if let error = savedPlansViewModel.loadError {
                VStack(spacing: AppSpacing.md) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        savedPlansViewModel.fetchRehabPlans()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xl)
            } else if savedPlansViewModel.rehabPlans.isEmpty {
                EmptyStateView(
                    icon: "figure.run",
                    title: "No Rehab Plans Yet",
                    subtitle: "Complete an injury analysis to get a personalized plan"
                )
            } else {
                ForEach(savedPlansViewModel.rehabPlans) { plan in
                    NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                                Text(plan.planName)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(.primary)
                                HStack(spacing: 6) {
                                    ForEach(plan.conditions, id: \.self) { condition in
                                        Text(condition)
                                            .font(.caption2)
                                            .padding(.horizontal, AppSpacing.sm)
                                            .padding(.vertical, 3)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(AppCorners.small)
                                    }
                                }
                                Text(plan.createdDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                planToDelete = plan
                                showDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                                    .font(.body)
                                    .foregroundColor(.red.opacity(0.7))
                                    .padding(AppSpacing.sm)
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()
                    }
                }
            }
        }
        .alert("Delete Plan", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                planToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let plan = planToDelete {
                    savedPlansViewModel.deletePlan(plan)
                    planToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(planToDelete?.planName ?? "this plan")\"? This cannot be undone.")
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

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "PT Helper v\(version) (\(build))"
    }

    private func fetchUserName() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        db.collection("users").document(uid).collection("profile").document("health").getDocument { snapshot, error in
            if let error = error {
                AppLogger.data.error("Error fetching user name: \(error.localizedDescription)")
            } else if let snapshot = snapshot, let data = snapshot.data() {
                let first = data["firstName"] as? String ?? ""
                userName = first.isEmpty ? (data["name"] as? String ?? "") : first
            }
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
