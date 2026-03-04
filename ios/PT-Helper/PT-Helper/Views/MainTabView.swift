import SwiftUI

/// Observable class to allow any child view to switch tabs or pop to root
class TabSelection: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var homeNavigationId = UUID()
    @Published var analyzeNavigationId = UUID()
    @Published var plansNavigationId = UUID()
    @Published var progressNavigationId = UUID()

    func popToRootAndGoHome() {
        if selectedTab == 0 {
            // Already on Home — just reset navigation to pop to root
            homeNavigationId = UUID()
            return
        }

        // Clean up the deep navigation state on the tab we're leaving
        switch selectedTab {
        case 1: analyzeNavigationId = UUID()
        case 2: plansNavigationId = UUID()
        case 3: progressNavigationId = UUID()
        default: break
        }

        // Switch to Home (its NavigationStack is already at root,
        // so no need to also change homeNavigationId — doing both
        // in the same render pass can crash SwiftUI).
        selectedTab = 0
    }
}

struct MainTabView: View {
    @StateObject private var tabSelection = TabSelection()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    // Shared ViewModels — created once, injected into all tabs that need them
    @StateObject private var savedPlansViewModel = SavedPlansViewModel()
    @StateObject private var workoutViewModel = WorkoutViewModel()

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
                .background(Color.orange)
            }

            TabView(selection: $tabSelection.selectedTab) {
                HomeTab()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(0)

                NavigationStack {
                    BodyMap3DView()
                }
                .id(tabSelection.analyzeNavigationId)
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
        .onChange(of: tabSelection.selectedTab) { _, newTab in
            let tabNames = ["Home", "Analyze", "Plans", "Progress"]
            let name = newTab < tabNames.count ? tabNames[newTab] : "Unknown"
            SessionLogger.shared.logNavigation(.tabSwitched, screen: name, metadata: ["tab": "\(newTab)"])
        }
        .onReceive(NotificationCenter.default.publisher(for: .popToRoot)) { _ in
            tabSelection.popToRootAndGoHome()
        }
    }
}
