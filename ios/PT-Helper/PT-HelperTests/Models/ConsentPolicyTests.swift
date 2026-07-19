import XCTest
@testable import PT_Helper

final class ConsentPolicyTests: XCTestCase {

    func testNeedsLegalReacceptance_NilRecord_True() {
        XCTAssertTrue(
            ConsentPolicy.needsLegalReacceptance(recordedVersion: nil,
                                                 currentVersion: "2026.07")
        )
    }

    func testNeedsLegalReacceptance_OlderVersion_True() {
        XCTAssertTrue(
            ConsentPolicy.needsLegalReacceptance(recordedVersion: "2026.01",
                                                 currentVersion: "2026.07")
        )
    }

    func testNeedsLegalReacceptance_CurrentVersion_False() {
        XCTAssertFalse(
            ConsentPolicy.needsLegalReacceptance(recordedVersion: "2026.07",
                                                 currentVersion: "2026.07")
        )
    }

    // MARK: - shouldShowHealthConsentGate

    func testShouldShowHealthConsentGate_profiledUserWithoutConsent_fires() {
        XCTAssertTrue(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: false, legalGateShowing: false,
            minorSafetyPending: false, hasHealthProfile: true, hasHealthDataConsent: false))
    }

    func testShouldShowHealthConsentGate_consentNotLoaded_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: false, needsLegalReacceptance: false, legalGateShowing: false,
            minorSafetyPending: false, hasHealthProfile: true, hasHealthDataConsent: false))
    }

    func testShouldShowHealthConsentGate_needsLegalReacceptance_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: true, legalGateShowing: false,
            minorSafetyPending: false, hasHealthProfile: true, hasHealthDataConsent: false))
    }

    func testShouldShowHealthConsentGate_legalGateShowing_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: false, legalGateShowing: true,
            minorSafetyPending: false, hasHealthProfile: true, hasHealthDataConsent: false))
    }

    func testShouldShowHealthConsentGate_minorSafetyPending_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: false, legalGateShowing: false,
            minorSafetyPending: true, hasHealthProfile: true, hasHealthDataConsent: false))
    }

    func testShouldShowHealthConsentGate_noHealthProfile_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: false, legalGateShowing: false,
            minorSafetyPending: false, hasHealthProfile: false, hasHealthDataConsent: false))
    }

    func testShouldShowHealthConsentGate_alreadyConsented_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: false, legalGateShowing: false,
            minorSafetyPending: false, hasHealthProfile: true, hasHealthDataConsent: true))
    }

    func testShouldShowHealthConsentGate_multipleBlockers_defers() {
        XCTAssertFalse(ConsentPolicy.shouldShowHealthConsentGate(
            consentLoaded: true, needsLegalReacceptance: true, legalGateShowing: true,
            minorSafetyPending: true, hasHealthProfile: false, hasHealthDataConsent: true))
    }
}
