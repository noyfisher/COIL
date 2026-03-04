import SwiftUI

struct PlansTab: View {
    @EnvironmentObject private var savedPlansViewModel: SavedPlansViewModel
    @EnvironmentObject private var tabSelection: TabSelection
    @State private var planToDelete: RehabPlan? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                if savedPlansViewModel.isLoading {
                    LoadingStateView(message: "Loading plans...")
                } else if let error = savedPlansViewModel.loadError {
                    errorState(error)
                } else if savedPlansViewModel.rehabPlans.isEmpty {
                    emptyState
                } else {
                    plansList
                }
            }
            .navigationTitle("My Plans")
            .refreshable {
                savedPlansViewModel.fetchRehabPlans()
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
        .id(tabSelection.plansNavigationId)
        .trackScreen("PlansTab")
    }

    // MARK: - Plans List

    private var plansList: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                ForEach(savedPlansViewModel.rehabPlans) { plan in
                    NavigationLink(destination: RehabPlanView(existingPlan: plan)) {
                        planCard(for: plan)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func planCard(for plan: RehabPlan) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(plan.planName)
                    .font(AppFonts.cardTitle)
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
                HStack(spacing: AppSpacing.sm) {
                    Text(plan.createdDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(plan.exercises.count) exercises")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()

            // Quick start guided workout
            NavigationLink(destination: GuidedWorkoutView(plan: plan)) {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .padding(AppSpacing.xs)
            }
            .buttonStyle(.plain)

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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: "figure.run",
                title: "No Rehab Plans Yet",
                subtitle: "Complete an injury analysis to get a personalized rehabilitation plan",
                actionTitle: "Start Analysis",
                action: {
                    tabSelection.selectedTab = 1
                }
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
                .foregroundColor(.orange)
            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
            Button("Retry") {
                savedPlansViewModel.fetchRehabPlans()
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, AppSpacing.xxxl)
            Spacer()
        }
    }
}
