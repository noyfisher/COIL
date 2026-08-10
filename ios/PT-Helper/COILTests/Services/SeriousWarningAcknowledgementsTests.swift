import XCTest
@testable import COIL

/// Covers `SeriousWarningAcknowledgements` — the record of which plans the user has
/// explicitly accepted a `.serious` safety warning for. It is read on every plan open to
/// decide whether to re-show the blocking `SeriousWarningModal`, and had no test coverage.
///
/// A false positive here suppresses a safety modal the user never actually dismissed; a
/// crash on malformed data takes out plan opening entirely.
final class SeriousWarningAcknowledgementsTests: XCTestCase {

    private let key = "acknowledgedSeriousWarnings"

    override func setUp() {
        super.setUp()
        SeriousWarningAcknowledgements.clearAll()
    }

    override func tearDown() {
        SeriousWarningAcknowledgements.clearAll()
        super.tearDown()
    }

    func testUnknownPlan_isNotAcknowledged() {
        XCTAssertFalse(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
    }

    func testAcknowledge_marksThatPlanAcknowledged() {
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")

        XCTAssertTrue(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
    }

    /// The important negative: acknowledging one plan must not suppress the safety modal
    /// for a different plan with its own unreviewed warnings.
    func testAcknowledge_doesNotLeakToOtherPlans() {
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")

        XCTAssertFalse(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-b"))
    }

    func testMultiplePlans_trackedIndependently() {
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-c")

        XCTAssertTrue(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
        XCTAssertFalse(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-b"))
        XCTAssertTrue(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-c"))
    }

    func testAcknowledge_isIdempotent() {
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")

        XCTAssertTrue(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
    }

    func testClearAll_resetsEveryAcknowledgement() {
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-b")

        SeriousWarningAcknowledgements.clearAll()

        XCTAssertFalse(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
        XCTAssertFalse(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-b"))
    }

    /// Acknowledgements must survive the app being killed, since the modal is meant to
    /// stop re-firing permanently. Values live in `UserDefaults.standard`, so a fresh read
    /// after a write is the observable proxy for a relaunch.
    func testAcknowledgement_persistsAcrossReads() {
        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")

        let reread = UserDefaults.standard.data(forKey: key)

        XCTAssertNotNil(reread, "Acknowledgements must be written to persistent storage, not held in memory")
        XCTAssertTrue(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
    }

    /// `loadSet` is read on every plan open. If corrupt data threw or trapped instead of
    /// degrading to empty, a single bad write would break opening any plan. Degrading to
    /// empty is the safe direction: the user sees the safety modal again.
    func testCorruptStoredData_degradesToEmpty_ratherThanCrashing() {
        UserDefaults.standard.set(Data([0x00, 0x01, 0x02, 0xFF]), forKey: key)

        XCTAssertFalse(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"),
                       "Corrupt data must read as 'not acknowledged' so the warning re-shows")
    }

    /// Corrupt data must not block future acknowledgements either.
    func testAcknowledge_recoversFromCorruptStoredData() {
        UserDefaults.standard.set(Data([0xFF, 0xFE]), forKey: key)

        SeriousWarningAcknowledgements.acknowledge(planId: "plan-a")

        XCTAssertTrue(SeriousWarningAcknowledgements.isAcknowledged(planId: "plan-a"))
    }
}
