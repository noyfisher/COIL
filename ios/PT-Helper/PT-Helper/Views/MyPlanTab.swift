import SwiftUI
import Combine

/// Tab 1: My Plan — "What do I do?"
/// Two sub-tabs (Injury / Wellness) filter saved plans by `RehabPlan.PlanType`.
struct MyPlanTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @State private var planToDelete: RehabPlan? = nil
    @State private var showDeleteConfirmation = false
    @State private var selectedPlanType: RehabPlan.PlanType = .rehab
    @State private var hasInitializedTab = false
    @State private var route: PlanRoute? = nil

    /// Programmatic navigation target. Keyed by `RehabPlan.id` (a `UUID`) so the
    /// shared `RehabPlan` model doesn't need to be `Hashable`.
    private enum PlanRoute: Hashable {
        case detail(UUID)
        case workout(UUID)
    }

    private var filteredPlans: [RehabPlan] {
        savedPlansViewModel.rehabPlans.filter { $0.planType == selectedPlanType }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                if savedPlansViewModel.isLoading {
                    LoadingStateView(message: "Loading plans...")
                } else if let error = savedPlansViewModel.loadError {
                    errorState(error)
                } else {
                    planContent
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .coilNavBar()
            .navigationDestination(item: $route) { route in
                switch route {
                case .detail(let id):
                    if let plan = savedPlansViewModel.rehabPlans.first(where: { $0.id == id }) {
                        RehabPlanView(existingPlan: plan)
                    }
                case .workout(let id):
                    if let plan = savedPlansViewModel.rehabPlans.first(where: { $0.id == id }) {
                        GuidedWorkoutView(plan: plan)
                    }
                }
            }
            .refreshable { savedPlansViewModel.fetchRehabPlans() }
            .alert("Delete Plan", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { planToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let plan = planToDelete {
                        let planType = plan.planType == .rehab ? "injury" : "wellness"
                        AnalyticsService.shared.log(.planDeleted, parameters: ["plan_type": planType])
                        SessionLogger.shared.logUserAction(.buttonTapped, action: "planDeleted",
                                                            metadata: ["plan_type": planType])
                        withAnimation(.easeInOut(duration: 0.25)) {
                            savedPlansViewModel.deletePlan(plan)
                        }
                        planToDelete = nil
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(planToDelete?.planName ?? "this plan")\"?")
            }
            .onReceive(savedPlansViewModel.$rehabPlans) { plans in
                guard !hasInitializedTab, let mostRecent = plans.first else { return }
                selectedPlanType = mostRecent.planType
                hasInitializedTab = true
            }
        }
        .trackScreen("MyPlanTab")
    }

    // MARK: - Plan Content

    private var planContent: some View {
        VStack(spacing: 0) {
            // Segmented picker
            Picker("Plan Type", selection: $selectedPlanType) {
                Text("Injury").tag(RehabPlan.PlanType.rehab)
                Text("Wellness").tag(RehabPlan.PlanType.wellness)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.sm)
            .accessibilityIdentifier("myPlan.typePicker")

            if filteredPlans.isEmpty {
                emptyStateForCurrentTab
            } else {
                plansList
            }
        }
    }

    // MARK: - Plans List

    private var plansList: some View {
        List {
            // Section header
            Section {
                ForEach(filteredPlans) { plan in
                    planCard(plan)
                        .contextMenu {
                            Button(role: .destructive) {
                                planToDelete = plan
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                planToDelete = plan
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.lg, bottom: AppSpacing.sm, trailing: AppSpacing.lg))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            } header: {
                CoilDividerHeader(title: selectedPlanType == .rehab ? "Injury Plans" : "Wellness Plans")
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.bottom, AppSpacing.sm)
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.pageBackground)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: FloatingTabBarMetrics.clearance)
        }
    }

    // MARK: - Plan Card

    private func planCard(_ plan: RehabPlan) -> some View {
        VStack(spacing: 0) {
            // Red top stripe for active feel
            AppColors.accent.frame(height: 3)

            VStack(spacing: AppSpacing.md) {
                // Plan info row — tapping anywhere on the card (handled by the
                // card's onTapGesture below) opens the plan home page.
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.sm) {
                            CoilBadge(text: "Active")
                            Spacer()
                        }

                        Text(plan.planName)
                            .font(AppFonts.sectionTitle)
                            .textCase(.uppercase)
                            .kerning(0.3)
                            .foregroundColor(AppColors.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if !plan.conditions.isEmpty {
                            Text(plan.conditions.prefix(2).joined(separator: " · "))
                                .font(AppFonts.micro)
                                .foregroundColor(AppColors.secondaryText)
                        }

                        HStack(spacing: AppSpacing.sm) {
                            Text(plan.createdDate.formatted(date: .abbreviated, time: .omitted))
                            Text("·")
                            Text("\(plan.exercises.count) exercises")
                        }
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.mutedText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.nano) {
                        Text("\(plan.totalWeeks)")
                            .font(AppFonts.heroTitle)
                            .foregroundColor(AppColors.primaryText)
                        Text("weeks")
                            .font(Font.custom("Inter-Regular", size: 10))
                            .foregroundColor(AppColors.mutedText)
                    }
                }

                // Red CTA — explicit button so only this region starts the workout.
                Button {
                    route = .workout(plan.id)
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Start Guided Workout")
                            .font(AppFonts.cardTitle)
                            .textCase(.uppercase)
                            .kerning(1.0)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.md)
                    .background(AppColors.ctaBackground)
                    .clipShape(Capsule())
                    .shadow(color: AppColors.ctaBackground.opacity(0.30), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("myPlan.startWorkoutButton")
            }
            .padding(AppSpacing.lg)
        }
        .background(AppColors.cardBackground)
        .cornerRadius(AppCorners.card)
        .overlay(RoundedRectangle(cornerRadius: AppCorners.card).stroke(AppColors.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        .clipShape(RoundedRectangle(cornerRadius: AppCorners.card))
        .contentShape(Rectangle())
        .onTapGesture { route = .detail(plan.id) }
    }

    // MARK: - Empty State

    private var emptyStateForCurrentTab: some View {
        let copy: (title: String, subtitle: String, cta: String) = selectedPlanType == .rehab
            ? ("No Injury Plans Yet",
               "Start with an assessment to get a personalized rehab plan tailored to your condition",
               "Start Assessment")
            : ("No Wellness Plans Yet",
               "Pick wellness goals (posture, sleep, mobility, strength, pain management) to generate a plan",
               "Set Wellness Goals")

        return VStack {
            Spacer()
            EmptyStateView(
                icon: "list.clipboard",
                title: copy.title,
                subtitle: copy.subtitle,
                actionTitle: copy.cta,
                action: {
                    // Injury empty state → dual gateway; wellness empty state →
                    // straight into the wellness goal picker (previously both
                    // dead-ended on the Home tab).
                    tabSelection.assessmentRequest = selectedPlanType == .rehab ? .gateway : .wellness
                }
            )
            .padding(.horizontal, AppSpacing.lg)
            Spacer()
        }
    }

    // MARK: - Error State

    private func errorState(_ error: String) -> some View {
        // Standardized error UI — no hardcoded wifi icon (a Firestore permission
        // error is not a connectivity problem) (audit #63).
        VStack {
            Spacer()
            ErrorStateView(
                title: "Couldn't load your plans",
                message: error,
                onRetry: { savedPlansViewModel.fetchRehabPlans() }
            )
            .padding(.horizontal, AppSpacing.lg)
            Spacer()
        }
    }
}
