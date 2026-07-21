import Foundation

enum ConsentPolicy {
    /// True when the stored ToS version is missing or older than current.
    static func needsLegalReacceptance(recordedVersion: String?,
                                       currentVersion: String = LegalContent.tosVersion) -> Bool {
        recordedVersion != currentVersion
    }

    /// Post-read mirror value for one consent doc.
    /// Read failed (offline) → keep mirror. Doc absent or field missing
    /// (server authoritatively says "no consent") → nil (clear mirror).
    /// Field present → server wins.
    static func reconciledConsentVersion(
        readFailed: Bool,
        docExists: Bool,
        serverVersion: String?,
        mirrorVersion: String?
    ) -> String? {
        if readFailed { return mirrorVersion }
        guard docExists, let serverVersion else { return nil }
        return serverVersion
    }

    /// Launch-time MHMDA gate: fires only for users with a real health profile
    /// (health data already on file) who lack consent for the CURRENT policy
    /// version, and never while a higher-priority cover (legal gate,
    /// minor-safety interstitial) is showing or pending.
    static func shouldShowHealthConsentGate(
        consentLoaded: Bool,
        needsLegalReacceptance: Bool,
        legalGateShowing: Bool,
        minorSafetyPending: Bool,
        hasHealthProfile: Bool,
        hasHealthDataConsent: Bool
    ) -> Bool {
        consentLoaded
            && !needsLegalReacceptance
            && !legalGateShowing
            && !minorSafetyPending
            && hasHealthProfile
            && !hasHealthDataConsent
    }
}

enum AgePolicy {
    static let minimumAge = 13
    static func age(from dateOfBirth: Date, on date: Date = Date()) -> Int {
        Calendar.current.dateComponents([.year], from: dateOfBirth, to: date).year ?? 0
    }
    static func isBlocked(dateOfBirth: Date, on date: Date = Date()) -> Bool {
        age(from: dateOfBirth, on: date) < minimumAge
    }
    static func isMinor(dateOfBirth: Date, on date: Date = Date()) -> Bool {
        let a = age(from: dateOfBirth, on: date)
        return a >= minimumAge && a < 18
    }
}
