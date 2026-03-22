import SwiftUI

struct DashProfileView: View {
    @ObservedObject private var profileService = UserProfileService.shared
    @State private var showSettings = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.dashBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Profile Card
                        profileCard

                        // Settings Groups
                        settingsGroup {
                            settingsRow(icon: "heart.text.clipboard", color: AppColors.dashAccent, title: "Health Profile") {
                                showOnboarding = true
                            }
                            settingsRow(icon: "bell.badge", color: AppColors.dashWarning, title: "Reminders") {
                                // Future: notification settings
                            }
                        }

                        settingsGroup {
                            settingsRow(icon: "ladybug", color: .purple, title: "Debug Log") {
                                showSettings = true
                            }
                        }

                        // App version
                        Text("PT Helper v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.caption)
                            .foregroundColor(AppColors.dashTextSecondary)
                            .padding(.top, AppSpacing.lg)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.headline)
                        .foregroundColor(AppColors.dashTextPrimary)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView(userName: profileService.firstName, onEditProfile: {
                    showSettings = false
                    showOnboarding = true
                })
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingEditView()
            }
        }
        .trackScreen("DashProfile")
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: AppSpacing.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(AppColors.dashAccent.opacity(0.15))
                    .frame(width: 72, height: 72)
                Text(profileService.firstName.prefix(1).uppercased())
                    .font(.title.weight(.bold))
                    .foregroundColor(AppColors.dashAccent)
            }

            VStack(spacing: AppSpacing.xs) {
                Text(profileService.firstName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.dashTextPrimary)

                if profileService.profileCompleted {
                    Text("Health profile complete")
                        .font(.caption)
                        .foregroundColor(AppColors.dashSuccess)
                } else {
                    Text("Health profile incomplete")
                        .font(.caption)
                        .foregroundColor(AppColors.dashWarning)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .dashWidget()
    }

    // MARK: - Settings Helpers

    @ViewBuilder
    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(AppColors.dashSurface)
        .cornerRadius(AppCorners.large)
        .overlay(
            RoundedRectangle(cornerRadius: AppCorners.large)
                .stroke(AppColors.dashBorder, lineWidth: 1)
        )
    }

    private func settingsRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(0.15))
                    .cornerRadius(7)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(AppColors.dashTextPrimary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.dashTextSecondary)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }
}
