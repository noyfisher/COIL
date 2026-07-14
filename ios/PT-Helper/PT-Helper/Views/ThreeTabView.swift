import SwiftUI

/// The 4-tab navigation container with a custom floating tab bar.
struct ThreeTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var recoveryInsightsViewModel = RecoveryInsightsViewModel()
    @StateObject private var analysisStore = AnalysisResultStore.shared

    @State private var showAssessment = false

    var body: some View {
        ZStack(alignment: .bottom) {
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
                    HomeTab()
                        .tag(0)
                        .id(tabSelection.assessNavigationId)
                        .toolbar(.hidden, for: .tabBar)

                    MyPlanTab()
                        .tag(1)
                        .id(tabSelection.myPlanNavigationId)
                        .toolbar(.hidden, for: .tabBar)

                    ProgressTab()
                        .tag(2)
                        .id(tabSelection.progressNavigationId)
                        .toolbar(.hidden, for: .tabBar)

                    ProfileTab()
                        .tag(3)
                        .id(tabSelection.profileNavigationId)
                        .toolbar(.hidden, for: .tabBar)
                }
            }

            // Full-width tab bar pinned to bottom
            VStack(spacing: 0) {
                Spacer()
                FloatingTabBar(selectedTab: $tabSelection.selectedTab, onTabTapped: { tapped in
                    if tabSelection.selectedTab == tapped {
                        tabSelection.popToRootCurrentTab()
                    }
                }, onAssessmentTapped: {
                    showAssessment = true
                })
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .environmentObject(tabSelection)
        .environmentObject(savedPlansViewModel)
        .environmentObject(workoutViewModel)
        .environmentObject(networkMonitor)
        .environmentObject(recoveryInsightsViewModel)
        .environmentObject(analysisStore)
        .onChange(of: tabSelection.selectedTab) { oldTab, newTab in
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

    // MARK: - UIKit Appearance (nav bar only — tab bar is custom)

    private func applyAppNavBarAppearance() {
        let navBgColor = UIColor(AppColors.navBackground)

        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.backgroundColor = navBgColor
        navBar.shadowColor = UIColor(AppColors.navBorder)
        let titleFont = UIFont(name: "Inter-Bold", size: 19)
            ?? UIFont.systemFont(ofSize: 19, weight: .bold)
        let largeTitleFont = UIFont(name: "Inter-Bold", size: 28)
            ?? UIFont.systemFont(ofSize: 28, weight: .bold)
        navBar.titleTextAttributes = [.foregroundColor: UIColor.white, .font: titleFont]
        navBar.largeTitleTextAttributes = [.foregroundColor: UIColor.white, .font: largeTitleFont]
        let backImage = UIImage(systemName: "chevron.left")?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        navBar.setBackIndicatorImage(backImage, transitionMaskImage: backImage)
        UINavigationBar.appearance().standardAppearance = navBar
        UINavigationBar.appearance().compactAppearance = navBar
        UINavigationBar.appearance().scrollEdgeAppearance = navBar
        UINavigationBar.appearance().tintColor = .white
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

/// Layout metrics for the custom `FloatingTabBar`.
enum FloatingTabBarMetrics {
    /// Bottom clearance needed so on-screen content/footers sit above the
    /// floating tab bar. The bar overlays the bottom of every view rendered
    /// inside the tab navigation (it lives in `ThreeTabView`'s ZStack, outside
    /// the NavigationStacks, and uses `.ignoresSafeArea(edges: .bottom)`), so
    /// this covers the full bar footprint including the home-indicator area and
    /// the lifted centre "+" button.
    static let clearance: CGFloat = 100
}

extension View {
    /// Adds bottom padding so content/footers clear the custom `FloatingTabBar`
    /// overlay. Apply to a pinned footer's bottom or to a ScrollView's inner
    /// content container.
    func floatingTabBarClearance() -> some View {
        padding(.bottom, FloatingTabBarMetrics.clearance)
    }
}

private struct TabBarItem {
    let tag: Int
    let icon: String
    let label: String
}

/// Left pair and right pair flank the centre "+" button.
private let leftTabItems: [TabBarItem] = [
    TabBarItem(tag: 0, icon: "house.fill",         label: "Home"),
    TabBarItem(tag: 1, icon: "list.clipboard.fill", label: "Plan"),
]
private let rightTabItems: [TabBarItem] = [
    TabBarItem(tag: 2, icon: "chart.line.uptrend.xyaxis", label: "Progress"),
    TabBarItem(tag: 3, icon: "person.fill",               label: "Profile"),
]

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    var onTabTapped: (Int) -> Void
    var onAssessmentTapped: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // ── Full-width bar ─────────────────────────────────────────────
            HStack(spacing: 0) {
                // Left tabs
                ForEach(leftTabItems, id: \.tag) { item in
                    tabButton(item)
                }

                // Centre spacer — reserves room beneath the "+" button
                Spacer()
                    .frame(width: 72)

                // Right tabs
                ForEach(rightTabItems, id: \.tag) { item in
                    tabButton(item)
                }
            }
            .padding(.top, 10)   // push tab icons down below the "+" button
            .frame(maxWidth: .infinity)
            .background(AppColors.navBackground)

            // ── Big "+" button centred, lifts above the bar ───────────────
            Button {
                onAssessmentTapped()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: -4)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppColors.accent)
                }
            }
            .accessibilityLabel("New Assessment")
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: -8)   // lift slightly above the bar top edge
        }
    }

    @ViewBuilder
    private func tabButton(_ item: TabBarItem) -> some View {
        Button {
            onTabTapped(item.tag)
            selectedTab = item.tag
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(item.label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(selectedTab == item.tag ? AppColors.tabActive : AppColors.tabInactive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(selectedTab == item.tag ? [.isSelected] : [])
    }
}
