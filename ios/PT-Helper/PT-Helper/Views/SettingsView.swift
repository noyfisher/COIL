import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {
    let userName: String
    var onEditProfile: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var notificationService = NotificationService.shared
    @State private var showSignOutConfirmation = false
    @State private var showSignOutError = false
    @State private var signOutErrorMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var reminderDate = Date()
    @State private var shareURL: URL?
    @State private var showShareSheet = false
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bgGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.lg) {
                        // Profile card
                        VStack(spacing: AppSpacing.lg) {
                            // Avatar
                            Text(initials)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(AppColors.ctaText)
                                .frame(width: 72, height: 72)
                                .background(
                                    Circle()
                                        .fill(AppColors.primaryGradient)
                                )

                            Text(userName.isEmpty ? "User" : userName)
                                .font(.system(.title3, design: .serif).weight(.bold))
                                .foregroundColor(AppColors.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xl)
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.xl)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.xl)
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                        // Notifications
                        VStack(spacing: 0) {
                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "bell.badge")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.warning)
                                    .frame(width: 32, height: 32)
                                    .background(AppColors.warning.opacity(0.12))
                                    .cornerRadius(AppCorners.small)

                                Text("Reminders")
                                    .font(.body)

                                Spacer()

                                Toggle("", isOn: $notificationService.isEnabled)
                                    .labelsHidden()
                                    .accessibilityIdentifier("settings.reminderToggle")
                                    .onChange(of: notificationService.isEnabled) { _, enabled in
                                        AnalyticsService.shared.log(.settingChanged,
                                            parameters: ["key": "reminders_enabled",
                                                         "value": enabled ? "true" : "false"])
                                        if enabled && !notificationService.isAuthorized {
                                            Task { await notificationService.requestPermission() }
                                        }
                                    }
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)

                            if notificationService.isEnabled {
                                Divider().padding(.leading, 52)

                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.accent)
                                        .frame(width: 32, height: 32)
                                        .background(AppColors.accentTint)
                                        .cornerRadius(AppCorners.small)

                                    Text("Reminder Time")
                                        .font(.body)

                                    Spacer()

                                    DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .onChange(of: reminderDate) { _, newDate in
                                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                                            notificationService.reminderHour = components.hour ?? 9
                                            notificationService.reminderMinute = components.minute ?? 0
                                            let timeString = String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
                                            AnalyticsService.shared.log(.settingChanged,
                                                parameters: ["key": "reminder_time", "value": timeString])
                                        }
                                }
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)

                                Divider().padding(.leading, 52)

                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: "dumbbell")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.success)
                                        .frame(width: 32, height: 32)
                                        .background(AppColors.success.opacity(0.12))
                                        .cornerRadius(AppCorners.small)
                                    Text("Workout Reminders")
                                        .font(.body)
                                    Spacer()
                                    Toggle("", isOn: $notificationService.workoutRemindersEnabled)
                                        .labelsHidden()
                                        .onChange(of: notificationService.workoutRemindersEnabled) { _, enabled in
                                            AnalyticsService.shared.log(.settingChanged,
                                                parameters: ["key": "workout_reminders",
                                                             "value": enabled ? "true" : "false"])
                                        }
                                }
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)

                                Divider().padding(.leading, 52)

                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.accent)
                                        .frame(width: 32, height: 32)
                                        .background(AppColors.accentTint)
                                        .cornerRadius(AppCorners.small)
                                    Text("Re-Assessment Prompts")
                                        .font(.body)
                                    Spacer()
                                    Toggle("", isOn: $notificationService.reassessmentRemindersEnabled)
                                        .labelsHidden()
                                        .onChange(of: notificationService.reassessmentRemindersEnabled) { _, enabled in
                                            AnalyticsService.shared.log(.settingChanged,
                                                parameters: ["key": "reassessment_reminders",
                                                             "value": enabled ? "true" : "false"])
                                        }
                                }
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)

                                Divider().padding(.leading, 52)

                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: "bell.badge.waveform")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.warning)
                                        .frame(width: 32, height: 32)
                                        .background(AppColors.warning.opacity(0.12))
                                        .cornerRadius(AppCorners.small)
                                    Text("Inactivity Nudges")
                                        .font(.body)
                                    Spacer()
                                    Toggle("", isOn: $notificationService.inactivityNudgesEnabled)
                                        .labelsHidden()
                                        .onChange(of: notificationService.inactivityNudgesEnabled) { _, enabled in
                                            AnalyticsService.shared.log(.settingChanged,
                                                parameters: ["key": "inactivity_nudges",
                                                             "value": enabled ? "true" : "false"])
                                        }
                                }
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)
                            }
                        }
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.large)
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                        // Debug & Feedback
                        VStack(spacing: 0) {
                            settingsRow(icon: "ladybug", color: AppColors.accent, title: "Export Debug Log") {
                                if let url = SessionLogger.shared.exportAsShareableFile() {
                                    shareURL = url
                                    showShareSheet = true
                                }
                            }

                            Divider().padding(.leading, 52)

                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(AppColors.accentLight)
                                    .frame(width: 32, height: 32)
                                    .background(AppColors.accentTint)
                                    .cornerRadius(AppCorners.small)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Session Events")
                                        .font(.body)
                                    Text("\(SessionLogger.shared.eventCount) events this session")
                                        .font(.caption2)
                                        .foregroundColor(AppColors.secondaryText)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.vertical, AppSpacing.md)
                        }
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.large)
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                        // Legal
                        VStack(spacing: 0) {
                            settingsRow(icon: "hand.raised", color: AppColors.accent, title: "Privacy Policy") {
                                showPrivacyPolicy = true
                            }
                            .accessibilityIdentifier("settings.privacyPolicyButton")

                            Divider().padding(.leading, 52)

                            settingsRow(icon: "doc.text", color: AppColors.accent, title: "Terms of Service") {
                                showTermsOfService = true
                            }
                            .accessibilityIdentifier("settings.termsOfServiceButton")
                        }
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.large)
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                        // Actions
                        VStack(spacing: 0) {
                            settingsRow(icon: "heart.text.clipboard", color: AppColors.accent, title: "Update Health Info") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    onEditProfile()
                                }
                            }
                            .accessibilityIdentifier("settings.editProfileButton")

                            #if DEBUG
                            Divider().padding(.leading, 52)

                            NavigationLink(destination: MissingImagesDebugView()) {
                                HStack(spacing: AppSpacing.md) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppColors.warning)
                                        .frame(width: 32, height: 32)
                                        .background(AppColors.warning.opacity(0.12))
                                        .cornerRadius(AppCorners.small)
                                    Text("Image Diagnostics (DEBUG)")
                                        .font(.body)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(AppColors.secondaryText)
                                }
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.md)
                            }
                            .accessibilityIdentifier("settings.imageDiagnosticsButton")
                            #endif

                            Divider().padding(.leading, 52)

                            settingsRow(icon: "rectangle.portrait.and.arrow.right", color: AppColors.danger, title: "Sign Out") {
                                showSignOutConfirmation = true
                            }
                            .accessibilityIdentifier("settings.signOutButton")
                        }
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.large)
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                        // Danger zone
                        VStack(spacing: 0) {
                            settingsRow(icon: "trash", color: AppColors.danger, title: "Delete Account") {
                                showDeleteConfirmation = true
                            }
                            .accessibilityIdentifier("settings.deleteAccountButton")
                        }
                        .background(AppColors.cardBackground)
                        .cornerRadius(AppCorners.large)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppCorners.large)
                                .stroke(AppColors.cardBorder, lineWidth: 1)
                        )
                        .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)

                        // App version
                        Text(appVersionText)
                            .font(.caption2)
                            .foregroundColor(AppColors.mutedText)
                            .padding(.top, AppSpacing.lg)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.vertical, AppSpacing.md)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    AnalyticsService.shared.log(.signedOut)
                    SessionLogger.shared.logUserAction(.buttonTapped, action: "signOut")
                    do {
                        try Auth.auth().signOut()
                    } catch {
                        SessionLogger.shared.logError(error, context: "Auth.signOut",
                                                       metadata: ["screen": "SettingsView"])
                        AnalyticsService.shared.log(.errorShown, parameters: [
                            "screen": "SettingsView",
                            "error_type": "sign_out_failed"
                        ])
                        signOutErrorMessage = error.localizedDescription
                        showSignOutError = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Sign Out Failed", isPresented: $showSignOutError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signOutErrorMessage)
            }
            .confirmationDialog("Delete Account", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Everything", role: .destructive) {
                    AnalyticsService.shared.log(.accountDeleteAttempted)
                    SessionLogger.shared.logUserAction(.buttonTapped, action: "accountDeleteAttempted")
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account, all health data, rehab plans, and workout history. This cannot be undone.")
            }
            .alert("Delete Failed", isPresented: $showDeleteError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "An unknown error occurred.")
            }
            .overlay {
                if isDeletingAccount {
                    ZStack {
                        AppColors.primaryText.opacity(0.4).ignoresSafeArea()
                        VStack(spacing: AppSpacing.md) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(AppColors.ctaText)
                            Text("Deleting account...")
                                .font(.subheadline)
                                .foregroundColor(AppColors.primaryText)
                        }
                        .padding(AppSpacing.xxl)
                        .background(.ultraThinMaterial)
                        .cornerRadius(AppCorners.large)
                    }
                }
            }
        }
        .trackScreen("Settings")
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentView(title: "Privacy Policy", markdownContent: LegalContent.privacyPolicy)
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentView(title: "Terms of Service", markdownContent: LegalContent.termsOfService)
        }
    }

    // MARK: - Account Deletion

    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid
        let db = Firestore.firestore()

        isDeletingAccount = true

        Task {
            do {
                // 1. Delete Firestore user data (subcollections)
                let subcollections = ["profile", "rehabPlans", "workoutSessions", "notes", "wellnessPlans"]
                for subcollection in subcollections {
                    let snapshot = try await db.collection("users").document(uid)
                        .collection(subcollection).getDocuments()
                    for doc in snapshot.documents {
                        try await doc.reference.delete()
                    }
                }

                // 2. Delete the user document itself
                try await db.collection("users").document(uid).delete()

                // 3. Clear local caches
                await MainActor.run {
                    UserProfileService.shared.clear()
                    DisclaimerManager.reset()
                    OnboardingViewModel.clearDraft()
                }

                // 4. Delete the Firebase Auth account
                try await user.delete()

                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleted)
                    SessionLogger.shared.log(.stateUpdated, category: .auth,
                                              message: "Account deleted",
                                              metadata: ["uid": uid])
                    isDeletingAccount = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    SessionLogger.shared.logError(error, context: "deleteAccount",
                                                   metadata: ["screen": "SettingsView"])
                    AnalyticsService.shared.log(.accountDeleteFailed,
                        parameters: ["reason": error.localizedDescription])
                    AnalyticsService.shared.log(.errorShown, parameters: [
                        "screen": "SettingsView",
                        "error_type": "account_delete_failed"
                    ])
                    isDeletingAccount = false
                    deleteError = error.localizedDescription
                    showDeleteError = true
                }
            }
        }
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = userName.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(userName.prefix(2)).uppercased()
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "PT Helper v\(version) (\(build))"
    }

    private func settingsRow(icon: String, color: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .cornerRadius(AppCorners.small)

                Text(title)
                    .font(.body)
                    .foregroundColor(title == "Sign Out" ? AppColors.danger : AppColors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }
}
