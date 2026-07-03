import SwiftUI

/// Feature flag for the new 3-tab navigation (Assess / My Plan / Progress).
/// Set to `true` to enable the simplified 3-tab layout.
/// In UI testing mode, `--use-legacy-ui` launch argument forces the legacy 4-tab layout.
var useThreeTabUI: Bool {
    if TestDataSeeder.isUITesting && TestDataSeeder.shouldUseLegacyUI {
        return false
    }
    return true
}

/// Feature flag for the experimental data-driven dashboard UI (Manus Concept 2).
/// Superseded by `useThreeTabUI` when that is enabled.
var useDashboardUI: Bool {
    if useThreeTabUI { return false }
    if TestDataSeeder.isUITesting && TestDataSeeder.shouldUseLegacyUI {
        return false
    }
    return false // Dashboard UI disabled in favor of 3-tab layout
}

/// Which assessment entry to present from the floating "+" or a CTA button.
enum AssessmentRoute: Int, Identifiable {
    case gateway   // dual choice: "Something hurts" vs "Improve my life"
    case pain      // straight into the body-map pain assessment
    case wellness  // straight into the wellness goal picker
    var id: Int { rawValue }
}

/// Observable class to allow any child view to switch tabs or pop to root
class TabSelection: ObservableObject {
    @Published var selectedTab: Int = 0

    /// Set by any child tab / CTA to request an assessment entry point.
    /// `ThreeTabView` observes this and presents the matching full-screen cover,
    /// so buttons no longer dead-end on `selectedTab = 0` (the Home tab, which has
    /// no assessment launcher).
    @Published var assessmentRequest: AssessmentRoute?

    @Published var homeNavigationId = UUID()
    @Published var analyzeNavigationId = UUID()
    @Published var plansNavigationId = UUID()
    @Published var progressNavigationId = UUID()

    /// Navigation IDs for the 3-tab dashboard layout.
    @Published var dashboardNavigationId = UUID()
    @Published var rehabNavigationId = UUID()
    @Published var profileNavigationId = UUID()

    /// Navigation IDs for the new 3-tab layout (Assess / My Plan / Progress).
    @Published var assessNavigationId = UUID()
    @Published var myPlanNavigationId = UUID()

    func popToRootAndGoHome() {
        if selectedTab == 0 {
            // Already on Home/Dashboard/Assess — just reset navigation to pop to root
            homeNavigationId = UUID()
            dashboardNavigationId = UUID()
            assessNavigationId = UUID()
            return
        }

        // Clean up the deep navigation state on the tab we're leaving
        if useThreeTabUI {
            switch selectedTab {
            case 1: myPlanNavigationId = UUID()
            case 2: progressNavigationId = UUID()
            case 3: profileNavigationId = UUID()
            default: break
            }
        } else if useDashboardUI {
            switch selectedTab {
            case 1: rehabNavigationId = UUID()
            case 2: profileNavigationId = UUID()
            default: break
            }
        } else {
            switch selectedTab {
            case 1: analyzeNavigationId = UUID()
            case 2: plansNavigationId = UUID()
            case 3: progressNavigationId = UUID()
            default: break
            }
        }

        // Switch to Home (its NavigationStack is already at root,
        // so no need to also change homeNavigationId — doing both
        // in the same render pass can crash SwiftUI).
        selectedTab = 0
    }

    /// Pop to root on the current tab (used when re-tapping the active tab).
    func popToRootCurrentTab() {
        if useThreeTabUI {
            switch selectedTab {
            case 0: assessNavigationId = UUID()
            case 1: myPlanNavigationId = UUID()
            case 2: progressNavigationId = UUID()
            case 3: profileNavigationId = UUID()
            default: break
            }
        } else if useDashboardUI {
            switch selectedTab {
            case 0: dashboardNavigationId = UUID()
            case 1: rehabNavigationId = UUID()
            case 2: profileNavigationId = UUID()
            default: break
            }
        } else {
            switch selectedTab {
            case 0: homeNavigationId = UUID()
            case 1: analyzeNavigationId = UUID()
            case 2: plansNavigationId = UUID()
            case 3: progressNavigationId = UUID()
            default: break
            }
        }
    }
}

struct MainTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    // Shared ViewModels — created once, injected into all tabs that need them
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()
    @StateObject private var recoveryInsightsViewModel = RecoveryInsightsViewModel()

    // Health check state for inactivity detection
    @State private var showHealthCheck = false
    @State private var showQuickUpdate = false
    @State private var healthCheckDismissed = false

    /// Whether the Analyze tab should show the health check prompt instead of the body map
    private var needsHealthCheck: Bool {
        guard !healthCheckDismissed else { return false }
        if let months = UserProfileService.shared.monthsSinceLastActivity(), months >= 3 {
            return true
        }
        return false
    }

    var body: some View {
        if useThreeTabUI {
            ThreeTabView()
        } else if useDashboardUI {
            DashboardMainTabView()
        } else {
            existingTabView
        }
    }

    private var existingTabView: some View {
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
                LegacyHomeTab()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                Group {
                    if needsHealthCheck {
                        HealthCheckPromptView(
                            onUpdateProfile: {
                                showQuickUpdate = true
                            },
                            onContinue: {
                                healthCheckDismissed = true
                                UserProfileService.shared.recordActivity()
                            }
                        )
                        .fullScreenCover(isPresented: $showQuickUpdate) {
                            QuickHealthUpdateView {
                                showQuickUpdate = false
                                healthCheckDismissed = true
                            }
                        }
                    } else {
                        NavigationStack {
                            BodyMap3DView()
                        }
                        .id(tabSelection.analyzeNavigationId)
                    }
                }
                .tabItem {
                    Label("Analyze", systemImage: "figure.run.circle")
                }
                .tag(1)

                PlansTab()
                    .tabItem {
                        Label("Plans", systemImage: "list.clipboard.fill")
                    }
                    .tag(2)

                NavigationStack {
                    ProgressChartView()
                }
                .id(tabSelection.progressNavigationId)
                .tabItem {
                    Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)
            }
        }
        .environmentObject(tabSelection)
        .environmentObject(savedPlansViewModel)
        .environmentObject(workoutViewModel)
        .environmentObject(networkMonitor)
        .environmentObject(recoveryInsightsViewModel)
        .onChange(of: tabSelection.selectedTab) { _, newTab in
            let tabNames = ["Home", "Analyze", "Plans", "Progress"]
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
                case "home": tabSelection.selectedTab = 0
                case "analyze": tabSelection.selectedTab = 1
                case "plans": tabSelection.selectedTab = 2
                case "progress": tabSelection.selectedTab = 3
                default: break
                }
                NotificationService.shared.pendingDeepLink = nil
            }
        }
        .onAppear {
            if let tab = NotificationService.shared.pendingDeepLink {
                switch tab {
                case "home": tabSelection.selectedTab = 0
                case "analyze": tabSelection.selectedTab = 1
                case "plans": tabSelection.selectedTab = 2
                case "progress": tabSelection.selectedTab = 3
                default: break
                }
                NotificationService.shared.pendingDeepLink = nil
            }
        }
    }
}
