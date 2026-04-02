import SwiftUI

/// Experimental 3-tab dashboard UI (Manus Concept 2).
/// Replaces the standard 4-tab MainTabView when `useDashboardUI` is true.
struct DashboardMainTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var recoveryInsightsViewModel = RecoveryInsightsViewModel()
    @StateObject private var analysisStore = AnalysisResultStore.shared

    var body: some View {
        VStack(spacing: 0) {
            // Offline banner
            if !networkMonitor.isConnected {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .semibold))
                    Text("You're offline. Changes will sync when reconnected.")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.danger.opacity(0.8))
                .accessibilityIdentifier("offlineBanner")
            }

            TabView(selection: $tabSelection.selectedTab) {
                AnalysisDashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    }
                    .tag(0)
                    .id(tabSelection.dashboardNavigationId)

                FormCheckTab()
                    .tabItem {
                        Label("Form Check", systemImage: "figure.walk")
                    }
                    .tag(1)

                RehabMetricsView()
                    .tabItem {
                        Label("Rehab", systemImage: "heart.text.clipboard.fill")
                    }
                    .tag(2)
                    .id(tabSelection.rehabNavigationId)

                PreventativeHomeView()
                    .tabItem {
                        Label("Prevent", systemImage: "leaf.fill")
                    }
                    .tag(3)

                DashProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(4)
                    .id(tabSelection.profileNavigationId)
            }
            .tint(AppColors.accent)
        }
        .environmentObject(tabSelection)
        .environmentObject(savedPlansViewModel)
        .environmentObject(workoutViewModel)
        .environmentObject(networkMonitor)
        .environmentObject(recoveryInsightsViewModel)
        .environmentObject(analysisStore)
        .onChange(of: tabSelection.selectedTab) { oldTab, newTab in
            // Re-tapping the same tab pops to root
            if oldTab == newTab {
                tabSelection.popToRootCurrentTab()
            }
            let tabNames = ["Dashboard", "Form Check", "Rehab", "Prevent", "Profile"]
            let name = newTab < tabNames.count ? tabNames[newTab] : "Unknown"
            SessionLogger.shared.logNavigation(.tabSwitched, screen: name, metadata: ["tab": "\(newTab)"])
            AnalyticsService.shared.log(.tabSwitched, parameters: ["tab_index": newTab])
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { _ in
            tabSelection.popToRootAndGoHome()
        }
    }
}
