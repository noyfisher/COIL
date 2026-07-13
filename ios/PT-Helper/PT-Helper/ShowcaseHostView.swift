import SwiftUI

// SHOWCASE-ONLY HARNESS — lives on the throwaway `compliance/integration-showcase`
// branch to capture deterministic screenshots of the compliance changes. Never
// merged into a real branch. Activated by `--showcase --showcase-screen=<id>`.
struct ShowcaseHostView: View {
    private var screen: String {
        let args = ProcessInfo.processInfo.arguments
        for a in args where a.hasPrefix("--showcase-screen=") {
            return String(a.dropFirst("--showcase-screen=".count))
        }
        return "index"
    }

    var body: some View {
        switch screen {
        case "consent":
            HealthDataConsentView(onConsented: {})
        case "reaccept":
            LegalAcceptanceGateView(mode: .reacceptance, onAccepted: { _ in })
        case "skipgate":
            LegalAcceptanceGateView(mode: .skipOnboarding, onAccepted: { _ in })
        case "minor":
            MinorSafetyResourcesView(onDismiss: {})
        case "report":
            NavigationStack { ReportConcernView() }
        case "friction":
            ShowcaseSheetBackdrop {
                RedFlagAcknowledgementSheet(
                    analysisId: "demo",
                    warningMessages: [
                        "Some of your reported symptoms may need urgent attention.",
                        "We recommend seeing a clinician before starting a self-guided plan."
                    ],
                    onAcknowledge: {}, onDismiss: {}
                )
            }
        case "emergency":
            EmergencyRedirectView(
                warningMessages: [
                    "Your reported symptoms include warning signs that need urgent evaluation by a healthcare provider."
                ],
                onDismiss: {}
            )
        case "disclaimer":
            DisclaimerView(onAccept: {})
        case "privacy":
            NavigationStack { LegalDocumentView(title: "Privacy Policy", markdownContent: LegalContent.privacyPolicy) }
        case "terms":
            NavigationStack { LegalDocumentView(title: "Terms of Service", markdownContent: LegalContent.termsOfService) }
        case "chd":
            NavigationStack { LegalDocumentView(title: "Consumer Health Data Policy", markdownContent: LegalContent.consumerHealthDataPolicy) }
        case "dashboard":
            ShowcaseDashboardWrap()
        default:
            ShowcaseIndex()
        }
    }
}

/// Renders sheet-style content over a dimmed backdrop so screenshots look like the
/// real bottom-sheet presentation.
private struct ShowcaseSheetBackdrop<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.35).ignoresSafeArea()
            content
                .background(AppColors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }
}

/// The de-medicalized differentials table on its dashboard background, with mock data.
private struct ShowcaseDashboardWrap: View {
    private var mock: [ConditionResult] {
        [
            ConditionResult(id: UUID(), conditionName: "Patellofemoral Pain Syndrome", commonName: "Runner's Knee",
                            confidence: 78, explanation: "Pain around the kneecap, common with running and stairs.",
                            whatItMeans: "Irritation where the kneecap meets the thigh bone.",
                            howToManage: "Quad and hip strengthening, activity modification.",
                            isRedFlag: false, redFlagMessage: nil, nextSteps: []),
            ConditionResult(id: UUID(), conditionName: "Iliotibial Band Syndrome", commonName: "IT Band Syndrome",
                            confidence: 52, explanation: "Outer-knee pain from a tight IT band.",
                            whatItMeans: "Friction on the outside of the knee during bending.",
                            howToManage: "Hip abductor work, foam rolling, load management.",
                            isRedFlag: false, redFlagMessage: nil, nextSteps: []),
            ConditionResult(id: UUID(), conditionName: "Patellar Tendinopathy", commonName: "Jumper's Knee",
                            confidence: 31, explanation: "Pain in the tendon just below the kneecap.",
                            whatItMeans: "Overloaded tendon from jumping or rapid load increases.",
                            howToManage: "Progressive tendon loading, relative rest.",
                            isRedFlag: false, redFlagMessage: nil, nextSteps: [])
        ]
    }
    var body: some View {
        ZStack {
            AppColors.pageBackground.ignoresSafeArea()
            ScrollView {
                DashDifferentialsTable(conditions: mock)
                    .padding(AppSpacing.lg)
            }
        }
    }
}

private struct ShowcaseIndex: View {
    let ids = ["consent","reaccept","skipgate","minor","report","friction","emergency","disclaimer","privacy","terms","chd","dashboard"]
    var body: some View {
        NavigationStack {
            List(ids, id: \.self) { Text($0) }
                .navigationTitle("Showcase")
        }
    }
}
