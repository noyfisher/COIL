/**
 * P1-04: pure eligibility decision enforced server-side on every AI endpoint
 * before any budget/quota/provider spend. Covers the minor safeguards and the
 * health-data-consent-withdrawal gate. The Firestore reads are exercised via
 * integration/emulator tests (PR-12); here we lock down the decision logic.
 */

import { evaluateEligibility } from "../src/index";

const consented = { docExists: true, hasPolicyVersion: true, wasRevoked: false };
const withdrawn = { docExists: true, hasPolicyVersion: false, wasRevoked: true };
const never = { docExists: false, hasPolicyVersion: false, wasRevoked: false };

describe("evaluateEligibility — minor safeguards", () => {
  it("under-13 is a hard block (and a minor)", () => {
    const e = evaluateEligibility(12, consented);
    expect(e.under13).toBe(true);
    expect(e.isMinor).toBe(true);
  });

  it("13–17 is a minor but not blocked", () => {
    const e = evaluateEligibility(15, consented);
    expect(e.under13).toBe(false);
    expect(e.isMinor).toBe(true);
  });

  it("adult is neither a minor nor blocked", () => {
    const e = evaluateEligibility(30, consented);
    expect(e.under13).toBe(false);
    expect(e.isMinor).toBe(false);
  });

  it("unknown age fails to the RESTRICTED path (minor), never to adult, never hard-blocked", () => {
    const e = evaluateEligibility(null, consented);
    expect(e.under13).toBe(false); // cannot prove under-13 → not hard-blocked
    expect(e.isMinor).toBe(true);  // but treated as a minor, not an adult
  });
});

describe("evaluateEligibility — health-data consent", () => {
  it("withdrawn consent (revoked + policyVersion cleared) blocks", () => {
    expect(evaluateEligibility(30, withdrawn).consentWithdrawn).toBe(true);
  });

  it("active consent does not block", () => {
    expect(evaluateEligibility(30, consented).consentWithdrawn).toBe(false);
  });

  it("never-created consent doc is NOT treated as withdrawn (onboarding gates first consent)", () => {
    expect(evaluateEligibility(30, never).consentWithdrawn).toBe(false);
  });

  it("re-consented after a prior withdrawal is NOT blocked (policyVersion present again)", () => {
    const reConsented = { docExists: true, hasPolicyVersion: true, wasRevoked: true };
    expect(evaluateEligibility(30, reConsented).consentWithdrawn).toBe(false);
  });

  it("a withdrawn minor is both minor and consent-blocked", () => {
    const e = evaluateEligibility(15, withdrawn);
    expect(e.isMinor).toBe(true);
    expect(e.consentWithdrawn).toBe(true);
  });
});
