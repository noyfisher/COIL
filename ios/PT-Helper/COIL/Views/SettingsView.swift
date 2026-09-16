import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import StoreKit

/// The grouped settings body shown under the Profile masthead (Preferences ·
/// Help & Legal · Account, then the DEBUG card and the version footer). It owns
/// every confirmation dialog, the account-deletion flow and the legal sheets;
/// `ProfileTab` owns the scroll view, the nav bar and the Edit Health Info sheet.
struct SettingsView: View {
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var consentService = ConsentService.shared
    @State private var showWithdrawConsentConfirmation = false
    @State private var showWithdrawDone = false
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
    @State private var showConsumerHealthDataPolicy = false
    @State private var showReportConcern = false
    @State private var showSafetyResources = false
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            settingsGroup(title: "Preferences", index: 1) {
                appearanceCard
                notificationsCard
            }

            settingsGroup(title: "Help & Legal", index: 2) {
                helpSupportCard
                legalCard
            }

            settingsGroup(title: "Account", index: 3) {
                accountCard
            }

            #if DEBUG
            debugCard
                .modifier(RevealOnAppear(index: 4))
            #endif

            Text(appVersionText)
                .font(AppFonts.micro)
                .foregroundColor(AppColors.mutedText)
                .frame(maxWidth: .infinity)
                .padding(.top, AppSpacing.sm)
                .accessibilityIdentifier("settings.versionFooter")
        }
        .padding(.horizontal, AppSpacing.xl)
        .confirmationDialog("Sign Out", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                AnalyticsService.shared.log(.signedOut)
                SessionLogger.shared.logUserAction(.buttonTapped, action: "signOut")
                Task {
                    // Clear the FCM token while STILL authenticated — after
                    // signOut the client can't write Firestore and the token
                    // would linger on this (possibly shared) device under the
                    // former account (P2-01).
                    await NotificationService.shared.clearFCMToken()
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
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Couldn't sign you out", isPresented: $showSignOutError) {
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
        .alert("Couldn't delete your account", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An unknown error occurred.")
        }
        .confirmationDialog("Withdraw Health Data Consent", isPresented: $showWithdrawConsentConfirmation, titleVisibility: .visible) {
            Button("Withdraw Consent", role: .destructive) {
                ConsentService.shared.revokeHealthDataConsent()
                showWithdrawDone = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("COIL will stop collecting and using your health data. You'll need to consent again before starting new assessments or using health features. Your existing data is kept until you delete your account.")
        }
        .alert("Consent Withdrawn", isPresented: $showWithdrawDone) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("New health-data features are paused until you consent again. To erase your data entirely, use Delete Account.")
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
                            .font(AppFonts.body)
                            .foregroundColor(AppColors.primaryText)
                    }
                    .padding(AppSpacing.xxl)
                    .background(.ultraThinMaterial)
                    .cornerRadius(AppCorners.large)
                }
            }
        }
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
        .sheet(isPresented: $showConsumerHealthDataPolicy) {
            LegalDocumentView(title: "Consumer Health Data Policy", markdownContent: LegalContent.consumerHealthDataPolicy)
        }
        .sheet(isPresented: $showReportConcern) {
            ReportConcernView()
        }
        .sheet(isPresented: $showSafetyResources) {
            MinorSafetyResourcesView { showSafetyResources = false }
        }
    }

    // MARK: - Account Deletion

    /// Classifies the `deleteAccount` endpoint response. Only HTTP 200 is a
    /// confirmed server-side deletion. The server authenticates *before* it
    /// deletes anything, so a 401 means the request was never authorized and
    /// nothing was deleted — retry once with a force-refreshed token, then fail.
    /// A 401 must never be treated as success: that would tell the user their
    /// health data was erased while it still lives on the server. (An idempotent
    /// retry against an already-deleted account returns 200, not 401, because the
    /// server swallows `auth/user-not-found`.)
    enum AccountDeletionOutcome: Equatable {
        case deleted
        case retryWithFreshToken
        case failed(status: Int)

        static func classify(status: Int, didRefreshToken: Bool) -> AccountDeletionOutcome {
            if status == 200 { return .deleted }
            if status == 401 && !didRefreshToken { return .retryWithFreshToken }
            return .failed(status: status)
        }
    }

    private func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        isDeletingAccount = true
        Task {
            do {
                try await performAccountDeletion(user: user, didRefreshToken: false)
                await MainActor.run { clearAllLocalUserData() }
                try? Auth.auth().signOut()
                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleted)
                    isDeletingAccount = false
                    // Nothing to dismiss: the tab hosts this body, and the sign-out
                    // above already routes RootView back to the auth screen.
                }
            } catch {
                await MainActor.run {
                    AnalyticsService.shared.log(.accountDeleteFailed,
                        parameters: ["reason": error.localizedDescription])
                    isDeletingAccount = false
                    deleteError = error.localizedDescription
                    showDeleteError = true
                }
            }
        }
    }

    /// Calls the `deleteAccount` endpoint and succeeds ONLY on a confirmed 200.
    /// A first 401 forces a token refresh and retries exactly once; anything that
    /// isn't a 200 throws, so the caller never clears local data or claims
    /// deletion on an unconfirmed response.
    private func performAccountDeletion(user: User, didRefreshToken: Bool) async throws {
        let idToken = try await user.getIDToken(forcingRefresh: didRefreshToken)
        var request = URLRequest(url: URL(string: APIConfig.deleteAccountURL)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        switch AccountDeletionOutcome.classify(status: status, didRefreshToken: didRefreshToken) {
        case .deleted:
            return
        case .retryWithFreshToken:
            try await performAccountDeletion(user: user, didRefreshToken: true)
        case .failed(let code):
            throw NSError(domain: "DeleteAccount", code: code,
                userInfo: [NSLocalizedDescriptionKey:
                    "The server couldn't complete the deletion (code \(code)). Your account was NOT deleted — please try again."])
        }
    }

    @MainActor
    private func clearAllLocalUserData() {
        // GA4 is a processor the deletion function cannot reach, so clear the
        // local identifiers here; already-exported events need a property-side
        // deletion request.
        AnalyticsService.shared.resetForAccountDeletion()
        UserProfileService.shared.clear()
        DisclaimerManager.reset()
        OnboardingViewModel.clearDraft()
        AnalysisResultStore.shared.clear()
        SeriousWarningAcknowledgements.clearAll()
        SessionLogger.shared.clearAllLocalData()
        GuidedWorkoutViewModel.clearAllLocalWorkoutState()
        ConsentService.clearLocalMirrors()
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.hasSeenMinorSafetyScreen)
        UserDefaults.standard.removeObject(forKey: AppStorageKeys.pendingMinorSafetyScreen)
        for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.hasPrefix("preventiveTasks_") {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - Helpers

    /// Opens the mail composer prefilled with the app version for faster debugging (audit #84).
    private func contactSupport() {
        let subject = "COIL Support"
        let body = "\n\n———\n\(appVersionText)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:noyfisher2003@gmail.com?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }

    /// Requests an App Store review via the system prompt (audit #84).
    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        // SKStoreReviewController was deprecated in iOS 18; the deployment
        // target is 18.2, so the StoreKit 2 entry point is always available.
        AppStore.requestReview(in: scene)
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "COIL v\(version) (\(build))"
    }

    // MARK: - Layout helpers

    /// A titled group: teal divider header above one or more cards.
    private func settingsGroup<Content: View>(title: String, index: Int,
                                              @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            CoilDividerHeader(title: title)
            content()
        }
        .modifier(RevealOnAppear(index: index))
    }

    /// The card chrome every group card shares. Rows carry their own padding, so
    /// the card itself has none (`.cardStyle()` would add `AppSpacing.lg`).
    private func groupCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(AppColors.cardBackground)
            .cornerRadius(AppCorners.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppCorners.card)
                    .stroke(AppColors.cardBorder, lineWidth: 1)
            )
            .shadow(color: AppColors.cardShadowColor, radius: 8, y: 2)
    }

    /// Inset so the rule starts under the row text, past the 32pt icon tile.
    private var rowDivider: some View {
        Divider().padding(.leading, AppSpacing.huge + AppSpacing.xl)
    }

    private func rowIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(AppFonts.iconS)
            .foregroundColor(color)
            .frame(width: 32, height: 32)
            .background(color.opacity(0.12))
            .cornerRadius(AppCorners.small)
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var appearanceCard: some View {
        groupCard {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.md) {
                    rowIcon("circle.lefthalf.filled", color: AppColors.accent)
                    Text("Appearance")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                }

                Picker("Appearance", selection: $appearanceRaw) {
                    ForEach(AppAppearance.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearancePicker")
                .onChange(of: appearanceRaw) { _, newValue in
                    AnalyticsService.shared.log(.settingChanged,
                        parameters: ["key": "appearance", "value": newValue])
                }
            }
            .padding(AppSpacing.lg)
        }
    }

    #if DEBUG
    /// Developer tooling; release builds never show it (deviation 5 keeps
    /// "Export Debug Log" available to testers in the Help card instead).
    @ViewBuilder
    private var debugCard: some View {
        groupCard {
            HStack(spacing: AppSpacing.md) {
                rowIcon("doc.text.magnifyingglass", color: AppColors.accentLight)

                VStack(alignment: .leading, spacing: AppSpacing.nano) {
                    Text("Session Events")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Text("\(SessionLogger.shared.eventCount) events this session")
                        .font(AppFonts.micro)
                        .foregroundColor(AppColors.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)

            rowDivider

            NavigationLink(destination: MissingImagesDebugView()) {
                HStack(spacing: AppSpacing.md) {
                    rowIcon("photo.badge.exclamationmark", color: AppColors.warning)
                    Text("Image Diagnostics")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFonts.iconXS)
                        .foregroundColor(AppColors.mutedText)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
            .accessibilityIdentifier("settings.imageDiagnosticsButton")
        }
    }
    #endif

    /// Extracted from `body` to keep the type-checker's per-expression work bounded.
    @ViewBuilder
    private var helpSupportCard: some View {
        groupCard {
            settingsRow(icon: "envelope", color: AppColors.accent, title: "Contact Support") {
                contactSupport()
            }
            .accessibilityIdentifier("settings.contactSupportButton")

            rowDivider

            settingsRow(icon: "flag", color: AppColors.warning, title: "Report a Concern") {
                showReportConcern = true
            }
            .accessibilityIdentifier("settings.reportConcernButton")

            rowDivider

            settingsRow(icon: "ladybug", color: AppColors.accent, title: "Export Debug Log") {
                if let url = SessionLogger.shared.exportAsShareableFile() {
                    shareURL = url
                    showShareSheet = true
                }
            }
            .accessibilityIdentifier("settings.exportDebugLogButton")

            rowDivider

            settingsRow(icon: "shield.checkered", color: AppColors.accent, title: "Safety Resources") {
                showSafetyResources = true
            }
            .accessibilityIdentifier("settings.safetyResourcesButton")

            rowDivider

            settingsRow(icon: "star", color: AppColors.accent, title: "Rate COIL") {
                requestAppReview()
            }
            .accessibilityIdentifier("settings.rateAppButton")
        }
    }

    /// Sign Out and Delete Account, formerly the "actions" and "danger zone" cards.
    /// "Update Health Info" now lives in the masthead.
    @ViewBuilder
    private var accountCard: some View {
        groupCard {
            settingsRow(icon: "rectangle.portrait.and.arrow.right", color: AppColors.danger,
                        title: "Sign Out", isDestructive: true) {
                showSignOutConfirmation = true
            }
            .accessibilityIdentifier("settings.signOutButton")

            rowDivider

            settingsRow(icon: "trash", color: AppColors.danger, title: "Delete Account") {
                showDeleteConfirmation = true
            }
            .accessibilityIdentifier("settings.deleteAccountButton")
        }
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var notificationsCard: some View {
        groupCard {
            HStack(spacing: AppSpacing.md) {
                rowIcon("bell.badge", color: AppColors.warning)

                Text("Reminders")
                    .font(AppFonts.body)
                    .foregroundColor(AppColors.primaryText)

                Spacer()

                Toggle("", isOn: $notificationService.isEnabled)
                    .labelsHidden()
                    .accessibilityLabel("Reminders")
                    .accessibilityIdentifier("settings.reminderToggle")
                    .onChange(of: notificationService.isEnabled) { _, enabled in
                        AnalyticsService.shared.log(.settingChanged,
                            parameters: ["key": "reminders_enabled",
                                         "value": enabled ? "true" : "false"])
                        if enabled {
                            Task {
                                if !notificationService.isAuthorized {
                                    _ = await notificationService.requestPermission()
                                }
                                await notificationService.resyncReminders()
                            }
                        } else {
                            notificationService.cancelAllReminders()
                        }
                    }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)

            if notificationService.isEnabled {
                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("clock", color: AppColors.accent)

                    Text("Reminder Time")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)

                    Spacer()

                    DatePicker("", selection: $reminderDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityLabel("Reminder time")
                        .onChange(of: reminderDate) { _, newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notificationService.updateReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
                            let timeString = String(format: "%02d:%02d", components.hour ?? 9, components.minute ?? 0)
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "reminder_time", "value": timeString])
                        }
                        .onAppear {
                            // Seed the picker from the SAVED time so a glance or an
                            // accidental tap can't silently overwrite it (audit #81).
                            var comps = DateComponents()
                            comps.hour = notificationService.reminderHour
                            comps.minute = notificationService.reminderMinute
                            if let seeded = Calendar.current.date(from: comps) {
                                reminderDate = seeded
                            }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("dumbbell", color: AppColors.success)
                    Text("Workout Reminders")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Toggle("", isOn: $notificationService.workoutRemindersEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Workout reminders")
                        .onChange(of: notificationService.workoutRemindersEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "workout_reminders",
                                             "value": enabled ? "true" : "false"])
                            Task { await notificationService.resyncReminders() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("arrow.triangle.2.circlepath", color: AppColors.accent)
                    Text("Re-Assessment Prompts")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Toggle("", isOn: $notificationService.reassessmentRemindersEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Re-assessment prompts")
                        .onChange(of: notificationService.reassessmentRemindersEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "reassessment_reminders",
                                             "value": enabled ? "true" : "false"])
                            Task { await notificationService.resyncReminders() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)

                rowDivider

                HStack(spacing: AppSpacing.md) {
                    rowIcon("bell.badge.waveform", color: AppColors.warning)
                    Text("Inactivity Nudges")
                        .font(AppFonts.body)
                        .foregroundColor(AppColors.primaryText)
                    Spacer()
                    Toggle("", isOn: $notificationService.inactivityNudgesEnabled)
                        .labelsHidden()
                        .accessibilityLabel("Inactivity nudges")
                        .onChange(of: notificationService.inactivityNudgesEnabled) { _, enabled in
                            AnalyticsService.shared.log(.settingChanged,
                                parameters: ["key": "inactivity_nudges",
                                             "value": enabled ? "true" : "false"])
                            if !enabled { notificationService.cancelInactivityNudge() }
                        }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
            }
        }
    }

    /// Extracted from `body` to keep the type-checker's per-expression work bounded
    /// (adding the conditional withdraw row inline pushed the main VStack over the
    /// compiler's reasonable-time threshold).
    @ViewBuilder
    private var legalCard: some View {
        groupCard {
            settingsRow(icon: "hand.raised", color: AppColors.accent, title: "Privacy Policy") {
                showPrivacyPolicy = true
            }
            .accessibilityIdentifier("settings.privacyPolicyButton")

            rowDivider

            settingsRow(icon: "doc.text", color: AppColors.accent, title: "Terms of Service") {
                showTermsOfService = true
            }
            .accessibilityIdentifier("settings.termsOfServiceButton")

            rowDivider

            settingsRow(icon: "heart.text.square", color: AppColors.accent, title: "Consumer Health Data Policy") {
                showConsumerHealthDataPolicy = true
            }
            .accessibilityIdentifier("settings.consumerHealthDataPolicyButton")

            if consentService.hasHealthDataConsent {
                rowDivider
                settingsRow(icon: "heart.slash", color: AppColors.danger, title: "Withdraw Health Data Consent") {
                    showWithdrawConsentConfirmation = true
                }
                .accessibilityIdentifier("settings.withdrawHealthConsentButton")
            }
        }
    }

    private func settingsRow(icon: String, color: Color, title: String,
                             isDestructive: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                rowIcon(icon, color: color)

                Text(title)
                    .font(AppFonts.body)
                    .foregroundColor(isDestructive ? AppColors.danger : AppColors.primaryText)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(AppFonts.iconXS)
                    .foregroundColor(AppColors.mutedText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }
}
