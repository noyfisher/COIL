import SwiftUI

/// Tab 1: My Plan — "What do I do?"
/// Shows the active plan as a hero card with a prominent "Start Workout" button,
/// followed by a list of all saved plans below. Empty state directs to Assess tab.
struct MyPlanTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @State private var planToDelete: RehabPlan? = nil
    @State private var showDeleteConfirmation = false

    /// The most recently modified active plan, shown as the hero card.
    private var activePlan: RehabPlan? {
        savedPlansViewModel.rehabPlans.first
    }

    /// All plans except the active one, shown in the saved list.
    private var savedPlans: [RehabPlan] {
        guard savedPlansViewModel.rehabPlans.count > 1 else { return [] }
        return Array(savedPlansViewModel.rehabPlans.dropFirst())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground.ignoresSafeArea()

                if savedPlansViewModel.isLoading {
                    LoadingStateView(message: "Loading plans...")
                } else if let error = savedPlansViewModel.loadError {
                    errorState(error)
                } else if savedPlansViewModel.rehabPlans.isEmpty {
                    emptyState
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
                        savedPlansViewModel.deletePlan(plan)
                        planToDelete = nil
                    }
                }
            } message: {
                Text("Are you sure you want to delete \"\(planToDelete?.planName ?? "this plan")\"?")
            }
        }
        .trackScreen("MyPlanTab")
    }

    // MARK: - Plan Content

    private var planContent: some View {
        List {
            // Active plan hero
            if let plan = activePlan {
                Section {
                    activePlanHero(plan)
                }
                .listRowInsets(EdgeInsets(top: AppSpacing.md, leading: AppSpacing.xl, bottom: 0, trailing: AppSpacing.xl))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            // Saved plans list
            if !savedPlans.isEmpty {
                Section {
                    ForEach(savedPlans) { plan in
                        NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                            savedPlanCard(plan)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                planToDelete = plan
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing) {
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
                } header: {
                    Text("SAVED PLANS")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppColors.mutedText)
                        .tracking(1.5)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.pageBackground)
    }

    // MARK: - Active Plan Hero

    private func activePlanHero(_ plan: RehabPlan) -> some View {
        VStack(spacing: AppSpacing.md) {
            NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(plan.planName)
                                .font(AppFonts.cardTitle)
                                .foregroundColor(.white)

                            Text("\(plan.exercises.count) exercises")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()

                        Text("Active")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2))
                            .cornerRadius(AppCorners.small)
                            .foregroundColor(.white)
                    }

                    // Condition chips
                    if !plan.conditions.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(plan.conditions.prefix(3), id: \.self) { condition in
                                Text(condition)
                                    .font(.caption2)
                                    .padding(.horizontal, AppSpacing.sm)
                                    .padding(.vertical, 3)
                                    .background(.white.opacity(0.15))
                                    .foregroundColor(.white)
                                    .cornerRadius(AppCorners.small)
                            }
                        }
                    }
                }
                .padding(AppSpacing.lg)
                .background(
                    LinearGradient(
                        colors: [AppColors.accent, AppColors.accent.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(AppCorners.card)
                .shadow(color: AppColors.accent.opacity(0.3), radius: 12, y: 4)
            }
            .buttonStyle(.plain)

            .contextMenu {
                Button(role: .destructive) {
                    planToDelete = plan
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }

            // Start Workout CTA
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
                .shadow(color: AppColors.accent.opacity(0.3), radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("myPlan.startWorkoutButton")
        }
    }

    // MARK: - Saved Plan Card

    private func savedPlanCard(_ plan: RehabPlan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(plan.planName)
                    .font(AppFonts.cardTitle)
                    .foregroundColor(AppColors.primaryText)

                HStack(spacing: 6) {
                    ForEach(plan.conditions.prefix(2), id: \.self) { condition in
                        Text(condition)
                            .font(.caption2)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, 3)
                            .background(AppColors.accentTint)
                            .foregroundColor(AppColors.accent)
                            .cornerRadius(AppCorners.small)
                    }
                }

                HStack(spacing: AppSpacing.sm) {
                    Text(plan.createdDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                    Text("·")
                        .foregroundColor(AppColors.secondaryText)
                    Text("\(plan.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(AppColors.secondaryText)
                }
            }

            Spacer()

            NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.accent)
                    .padding(AppSpacing.xs)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: "list.clipboard",
                title: "No Plan Yet",
                subtitle: "Start with an assessment to get a personalized rehab plan tailored to your condition",
                actionTitle: "Start Assessment",
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
