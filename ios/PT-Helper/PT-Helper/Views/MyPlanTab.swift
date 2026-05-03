import SwiftUI
import Combine

/// Tab 1: My Plan — "What do I do?"
/// Two sub-tabs (Injury / Wellness) filter the saved plans by `RehabPlan.PlanType`.
/// Every plan renders as an equal-weight card with its own "Start Guided Workout" CTA.
struct MyPlanTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @State private var planToDelete: RehabPlan? = nil
    @State private var showDeleteConfirmation = false
    @State private var selectedPlanType: RehabPlan.PlanType = .rehab
    @State private var hasInitializedTab = false

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
            .navigationTitle("My Plan")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { savedPlansViewModel.fetchRehabPlans() }
            .alert("Delete Plan", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { planToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let plan = planToDelete {
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
            Picker("Plan Type", selection: $selectedPlanType) {
                Text("Injury").tag(RehabPlan.PlanType.rehab)
                Text("Wellness").tag(RehabPlan.PlanType.wellness)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
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
                    .listRowInsets(EdgeInsets(top: AppSpacing.sm, leading: AppSpacing.xl, bottom: AppSpacing.sm, trailing: AppSpacing.xl))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.pageBackground)
    }

    // MARK: - Plan Card (uniform for every plan)

    private func planCard(_ plan: RehabPlan) -> some View {
        VStack(spacing: AppSpacing.md) {
            NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text(plan.planName)
                        .font(AppFonts.cardTitle)
                        .foregroundColor(AppColors.primaryText)

                    if !plan.conditions.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(plan.conditions.prefix(3), id: \.self) { condition in
                                Text(condition)
                                    .font(.caption2)
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(AppColors.accentTint)
                                    .foregroundColor(AppColors.accent)
                                    .cornerRadius(AppCorners.small)
                            }
                        }
                    }

                    HStack(spacing: AppSpacing.sm) {
                        Text(plan.createdDate.formatted(date: .abbreviated, time: .omitted))
                        Text("·")
                        Text("\(plan.exercises.count) exercises")
                    }
                    .font(.caption)
                    .foregroundColor(AppColors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Start Guided Workout")
                        .font(.system(.subheadline, weight: .semibold))
                }
                .foregroundColor(AppColors.ctaText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.accent)
                .cornerRadius(AppCorners.large)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("myPlan.startWorkoutButton")
        }
        .cardStyle()
    }

    // MARK: - Empty State (per tab)

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
                action: { tabSelection.selectedTab = 0 }
            )
            .padding(.horizontal, AppSpacing.xl)
            Spacer()
        }
    }

    // MARK: - Error State

    private func errorState(_ error: String) -> some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(AppColors.warning)
            Text(error)
                .font(.subheadline)
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
            Button("Retry") { savedPlansViewModel.fetchRehabPlans() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, AppSpacing.xxxl)
            Spacer()
        }
    }
}
