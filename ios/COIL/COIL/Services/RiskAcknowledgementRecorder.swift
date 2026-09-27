import FirebaseAuth
import FirebaseFirestore

/// Fire-and-forget recorder for red-flag risk acknowledgements. When a user chooses
/// to build a self-guided plan after seeing red-flag warnings, we persist an
/// acknowledgement record to Firestore for auditability.
enum RiskAcknowledgementRecorder {
    static func record(analysisId: String, warnings: [String]) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("riskAcknowledgements").document(analysisId)
            .setData([
                "analysisId": analysisId,
                "warningMessages": warnings,
                "acknowledgedAt": FieldValue.serverTimestamp(),
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            ], merge: true)
    }
}
