import SwiftUI

/// The 4-tab navigation container using the native iOS tab bar
/// (floating Liquid Glass style on iOS 26).
struct ThreeTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var recoveryInsightsViewModel = RecoveryInsightsViewModel()
    @StateObject private var analysisStore = AnalysisResultStore.shared

    @State private var showAssessment = false

    /// Sentinel tab value for the "New Assessment" action tab. Selecting it
    /// presents the body map cover and reverts to the previous tab.
    private static let assessActionTab = 4

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
                Tab("Home", systemImage: "house.fill", value: 0) {
                    HomeTab()
                        .id(tabSelection.assessNavigationId)
                }

                Tab("Plan", systemImage: "list.clipboard.fill", value: 1) {
                    MyPlanTab()
                        .id(tabSelection.myPlanNavigationId)
                }

                Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: 2) {
                    ProgressTab()
                        .id(tabSelection.progressNavigationId)
                }

                Tab("Profile", systemImage: "person.fill", value: 3) {
                    ProfileTab()
                        .id(tabSelection.profileNavigationId)
                }

                // Action tab: on iOS 26 the search role renders as the
                // separated circular button on the floating bar. Selection is
                // intercepted in onChange and never lands here.
                Tab("Assess", systemImage: "plus", value: Self.assessActionTab, role: .search) {
                    Color.clear
                }
            }
            // The system glass bar is light — white (the old tabActive) would
            // wash out, so tint with the brand accent instead.
            .tint(AppColors.accent)
        }
        .environmentObject(tabSelection)
        .environmentObject(savedPlansViewModel)
        .environmentObject(workoutViewModel)
        .environmentObject(networkMonitor)
        .environmentObject(recoveryInsightsViewModel)
        .environmentObject(analysisStore)
        .onChange(of: tabSelection.selectedTab) { oldTab, newTab in
            // Intercept the Assess action tab: present the body map and
            // bounce selection back to the tab the user was on.
            if newTab == Self.assessActionTab {
                showAssessment = true
                tabSelection.selectedTab = oldTab
                return
            }
            if oldTab == Self.assessActionTab { return }  // bounce-back, not a real switch
            if oldTab == newTab { tabSelection.popToRootCurrentTab() }
            let tabNames = ["Home", "My Plan", "Progress", "Profile"]
            let name = newTab < tabNames.count ? tabNames[newTab] : "Unknown"
            SessionLogger.shared.logNavigation(.tabSwitched, screen: name, metadata: ["tab": "\(newTab)"])
            AnalyticsService.shared.log(.tabSwitched, parameters: ["tab_index": newTab])
        }
        .fullScreenCover(isPresented: $showAssessment) {
            NavigationStack {
                BodyMap3DView()
                    .toolbar {
                        // BodyMap3DView registers a navigationDestination, so the
                        // close affordance lives out here and toggles state directly
                        // instead of reading @Environment(\.dismiss) (P1 freeze class).
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showAssessment = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .accessibilityLabel("Close")
                            .accessibilityIdentifier("bodyMap.closeButton")
                        }
                    }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { _ in
            showAssessment = false
            tabSelection.popToRootAndGoHome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deepLink)) { _ in
            if let tab = NotificationService.shared.pendingDeepLink {
                switch tab {
                case "home", "analyze": tabSelection.selectedTab = 0
                case "plans", "rehab": tabSelection.selectedTab = 1
                case "progress": tabSelection.selectedTab = 2
                case "profile": tabSelection.selectedTab = 3
                default: break
                }
                NotificationService.shared.pendingDeepLink = nil
            }
        }
        .onAppear {
            applyAppNavBarAppearance()
            if let tab = NotificationService.shared.pendingDeepLink {
                switch tab {
                case "home", "analyze": tabSelection.selectedTab = 0
                case "plans", "rehab": tabSelection.selectedTab = 1
                case "progress": tabSelection.selectedTab = 2
                case "profile": tabSelection.selectedTab = 3
                default: break
                }
                NotificationService.shared.pendingDeepLink = nil
            }
        }
    }

    // MARK: - UIKit Appearance (nav bar only — tab bar is the native system bar)

    private func applyAppNavBarAppearance() {
        let navBgColor = UIColor(AppColors.navBackground)
        let titleColor = UIColor(AppColors.primaryText)

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = navBgColor
        navBar.shadowColor = UIColor(AppColors.navBorder)
        let titleFont = UIFont(name: "Inter-Bold", size: 19)
            ?? UIFont.systemFont(ofSize: 19, weight: .bold)
        let largeTitleFont = UIFont(name: "Inter-Bold", size: 28)
            ?? UIFont.systemFont(ofSize: 28, weight: .bold)
        navBar.titleTextAttributes = [.foregroundColor: titleColor, .font: titleFont]
        navBar.largeTitleTextAttributes = [.foregroundColor: titleColor, .font: largeTitleFont]
        let backImage = UIImage(systemName: "chevron.left")?
            .withTintColor(titleColor, renderingMode: .alwaysOriginal)
        navBar.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().tintColor = titleColor
    }
}

// MARK: - Profile Tab

struct ProfileTab: View {
    @State private var showEditProfile = false

    var body: some View {
        NavigationStack {
            SettingsView(
                userName: UserProfileService.shared.profile?.firstName ?? "User",
                onEditProfile: { showEditProfile = true }
            )
        }
        .sheet(isPresented: $showEditProfile) {
            // Edit profile sheet — reuse onboarding review step
            Text("Edit Profile")
                .padding()
        }
    }
}

// MARK: - Tab Bar

/// Layout metrics kept for the call sites that padded content above the old
/// custom overlay bar. The native tab bar participates in the safe area, so
/// no extra clearance is needed.
enum FloatingTabBarMetrics {
    static let clearance: CGFloat = 0
}

extension View {
    /// No-op retained for source compatibility: the native tab bar insets
    /// content automatically, so no manual clearance padding is required.
    func floatingTabBarClearance() -> some View {
        padding(.bottom, FloatingTabBarMetrics.clearance)
    }
}
