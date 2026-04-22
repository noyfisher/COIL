import SwiftUI

/// The new 3-tab navigation container.
/// Tab 0: Assess — dual gateway (pain / wellness)
/// Tab 1: My Plan — active plan hero + saved plans
/// Tab 2: Progress — charts, insights, settings
struct ThreeTabView: View {
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
                .foregroundColor(AppColors.ctaText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.danger)
                .accessibilityIdentifier("offlineBanner")
            }

            TabView(selection: $tabSelection.selectedTab) {
                AssessTab()
                    .tabItem { Label("Assess", systemImage: "stethoscope") }
                    .tag(0)
                    .id(tabSelection.assessNavigationId)

                MyPlanTab()
                    .tabItem { Label("My Plan", systemImage: "list.clipboard.fill") }
                    .tag(1)
                    .id(tabSelection.myPlanNavigationId)

                ProgressTab()
                    .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                    .tag(2)
                    .id(tabSelection.progressNavigationId)
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
            if oldTab == newTab {
                tabSelection.popToRootCurrentTab()
            }
            let tabNames = ["Assess", "My Plan", "Progress"]
            let name = newTab < tabNames.count ? tabNames[newTab] : "Unknown"
            SessionLogger.shared.logNavigation(.tabSwitched, screen: name, metadata: ["tab": "\(newTab)"])
            AnalyticsService.shared.log(.tabSwitched, parameters: ["tab_index": newTab])
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { _ in
            tabSelection.popToRootAndGoHome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLink)) { _ in
            if let tab = NotificationService.shared.pendingDeepLink {
                switch tab {
                case "home", "analyze": tabSelection.selectedTab = 0
                case "plans", "rehab": tabSelection.selectedTab = 1
                case "progress", "profile": tabSelection.selectedTab = 2
                default: break
                }
                NotificationService.shared.pendingDeepLink = nil
            }
        }
        .onAppear {
            if let tab = NotificationService.shared.pendingDeepLink {
                switch tab {
                case "home", "analyze": tabSelection.selectedTab = 0
                case "plans", "rehab": tabSelection.selectedTab = 1
                case "progress", "profile": tabSelection.selectedTab = 2
                default: break
                }
                NotificationService.shared.pendingDeepLink = nil
            }
        }
    }
}
