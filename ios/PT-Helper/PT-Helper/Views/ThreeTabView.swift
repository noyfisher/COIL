import SwiftUI

/// The new 3-tab navigation container (MVVC rebrand: dark tab bar, red active indicator).
struct ThreeTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var recoveryInsightsViewModel = RecoveryInsightsViewModel()
    @StateObject private var analysisStore = AnalysisResultStore.shared

    var body: some View {
        VStack(spacing: 0) {
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
            .tint(AppColors.tabActive)
        }
        .environmentObject(tabSelection)
        .environmentObject(savedPlansViewModel)
        .environmentObject(workoutViewModel)
        .environmentObject(networkMonitor)
        .environmentObject(recoveryInsightsViewModel)
        .environmentObject(analysisStore)
        .onChange(of: tabSelection.selectedTab) { oldTab, newTab in
            if oldTab == newTab { tabSelection.popToRootCurrentTab() }
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
            applyMVVCAppearance()
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

    // MARK: - MVVC UIKit Appearance

    private func applyMVVCAppearance() {
        let navBgColor = UIColor(AppColors.navBackground)
        let activeColor = UIColor(AppColors.tabActive)
        let inactiveColor = UIColor(AppColors.tabInactive)

        // Tab bar — dark with red active tab
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = navBgColor
        tabBar.shadowColor = UIColor(AppColors.navBorder)
        for state in [tabBar.stackedLayoutAppearance, tabBar.inlineLayoutAppearance, tabBar.compactInlineLayoutAppearance] {
            state.normal.iconColor = inactiveColor
            state.normal.titleTextAttributes = [.foregroundColor: inactiveColor]
            state.selected.iconColor = activeColor
            state.selected.titleTextAttributes = [.foregroundColor: activeColor]
        }
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        // Navigation bar — dark with white title
        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = navBgColor
        navBar.shadowColor = UIColor(AppColors.navBorder)
        let titleFont = UIFont(name: "BarlowCondensed-Black", size: 19)
            ?? UIFont.systemFont(ofSize: 19, weight: .black)
        let largeTitleFont = UIFont(name: "BarlowCondensed-Black", size: 28)
            ?? UIFont.systemFont(ofSize: 28, weight: .black)
        navBar.titleTextAttributes = [.foregroundColor: UIColor.white, .font: titleFont]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: largeTitleFont]
        let backImage = UIImage(systemName: "chevron.left")?
            .withTintColor(UIColor(AppColors.accent), renderingMode: .alwaysOriginal)
        navBar.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().tintColor = UIColor(AppColors.accent)
    }
}
