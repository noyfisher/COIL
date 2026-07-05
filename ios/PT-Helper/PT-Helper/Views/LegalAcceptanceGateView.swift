import SwiftUI
import FirebaseAuth

/// Which situation the gate is covering.
enum LegalGateMode {
    /// The legal documents changed; the signed-in user must re-accept.
    case reacceptance
    /// The user skipped onboarding; we still need a DOB + acceptance before use.
    case skipOnboarding
}

/// Blocking legal-acceptance gate. Parent bindings drive dismissal — this view
/// deliberately holds NO `@Environment(\.dismiss)` (it would freeze under a
/// `navigationDestination`; see Gotchas #1). On accept it records the consent and
/// calls `onAccepted`, handing the DOB back for skip-mode minor routing.
struct LegalAcceptanceGateView: View {
    let mode: LegalGateMode
    let onAccepted: (_ dateOfBirth: Date?) -> Void

    @State private var hasChecked = false
    @State private var dob: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var showTerms = false
    @State private var showPrivacy = false

    private var isUnderage: Bool {
        mode == .skipOnboarding && AgePolicy.isBlocked(dateOfBirth: dob)
    }

    private var canAccept: Bool {
        hasChecked && !isUnderage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.pageBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: AppSpacing.xl) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AppColors.coolGradient)
                            .padding(.top, AppSpacing.xxl)

                        Text(title)
                            .font(.system(.title2, design: .serif).weight(.bold))
                            .multilineTextAlignment(.center)

                        Text(bodyText)
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, AppSpacing.xl)

                        if mode == .skipOnboarding {
                            dobSection
                                .padding(.horizontal, AppSpacing.xl)
                        }

                        legalLinks
                            .padding(.horizontal, AppSpacing.xl)

                        agreementCheckbox
                            .padding(.horizontal, AppSpacing.xl)

                        VStack(spacing: AppSpacing.md) {
                            Button(action: accept) {
                                Text("Accept & Continue")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(canAccept ? AppColors.accent : AppColors.accent.opacity(0.4))
                                    .foregroundColor(AppColors.ctaText)
                                    .font(.headline)
                                    .cornerRadius(AppCorners.large)
                            }
                            .disabled(!canAccept)

                            Button("Sign Out") {
                                try? Auth.auth().signOut()
                            }
                            .font(.subheadline)
                            .foregroundColor(AppColors.secondaryText)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.sm)

                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Terms & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showTerms) {
            LegalDocumentView(title: "Terms of Service", markdownContent: LegalContent.termsOfService)
        }
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentView(title: "Privacy Policy", markdownContent: LegalContent.privacyPolicy)
        }
        .trackScreen("LegalAcceptanceGate")
    }

    // MARK: - Sections

    private var dobSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Date of Birth")
                .font(.subheadline.weight(.semibold))
            DatePicker("", selection: $dob, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .tint(AppColors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isUnderage {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption2)
                    Text("You must be at least 13 years old to use this app.").font(AppFonts.caption)
                }
                .foregroundColor(AppColors.danger)
            }
        }
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Button("Terms of Service") { showTerms = true }
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.accent)
            Button("Privacy Policy") { showPrivacy = true }
                .font(AppFonts.bodyMedium)
                .foregroundColor(AppColors.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var agreementCheckbox: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            Button {
                hasChecked.toggle()
            } label: {
                Image(systemName: hasChecked ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundColor(hasChecked ? AppColors.accent : AppColors.secondaryText)
            }
            .accessibilityIdentifier("legalGate.agreeCheckbox")

            Text("I agree to the Terms of Service and Privacy Policy")
                .font(AppFonts.body)
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Copy

    private var title: String {
        switch mode {
        case .reacceptance: return "Updated Terms"
        case .skipOnboarding: return "Before You Continue"
        }
    }

    private var bodyText: String {
        switch mode {
        case .reacceptance:
            return "We've updated our Terms of Service and Privacy Policy. Please review and accept them to keep using the app."
        case .skipOnboarding:
            return "Even if you skip profile setup, we need your date of birth and your acceptance of our terms before you can use the app."
        }
    }

    // MARK: - Actions

    private func accept() {
        ConsentService.shared.recordLegalAcceptance(
            source: mode == .reacceptance ? "reacceptance" : "skip_gate",
            dateOfBirth: mode == .skipOnboarding ? dob : nil
        )
        onAccepted(mode == .skipOnboarding ? dob : nil)
    }
}
