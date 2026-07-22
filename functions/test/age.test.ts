/**
 * Server-side calendar age used by the minor safeguards in the eligibility gate
 * (P1-04). `computeAgeFromDob` does a UTC calendar comparison — whole years
 * since birth, minus one if this year's birthday has not yet occurred — rather
 * than the old 365.25-day approximation that drifted by ~a day near a birthday.
 * A fixed `nowMs` keeps the test independent of the machine clock.
 */

import { computeAgeFromDob } from "../src/index";

// Fixed reference "now": 2026-07-05 (month is 0-indexed: 6 = July).
const NOW = Date.UTC(2026, 6, 5);

/** UTC epoch millis for a calendar date (month given 1–12). */
function dob(year: number, month1to12: number, day: number): number {
  return Date.UTC(year, month1to12 - 1, day);
}

describe("computeAgeFromDob (calendar)", () => {
  it("exact 13th birthday today → 13 (minimum age met)", () => {
    expect(computeAgeFromDob(dob(2013, 7, 5), NOW)).toBe(13);
  });

  it("day before 13th birthday → 12 (still under-13)", () => {
    expect(computeAgeFromDob(dob(2013, 7, 6), NOW)).toBe(12);
  });

  it("day after 13th birthday → 13", () => {
    expect(computeAgeFromDob(dob(2013, 7, 4), NOW)).toBe(13);
  });

  it("exact 18th birthday today → 18 (no longer a minor)", () => {
    expect(computeAgeFromDob(dob(2008, 7, 5), NOW)).toBe(18);
  });

  it("day before 18th birthday → 17 (still a minor)", () => {
    expect(computeAgeFromDob(dob(2008, 7, 6), NOW)).toBe(17);
  });

  it("birthday earlier this year (already passed) → full age", () => {
    expect(computeAgeFromDob(dob(2000, 1, 1), NOW)).toBe(26);
  });

  it("birthday later this year (not yet occurred) → age minus one", () => {
    expect(computeAgeFromDob(dob(2000, 12, 31), NOW)).toBe(25);
  });

  it("under-13 gate: 12 blocks, 13 passes", () => {
    expect(computeAgeFromDob(dob(2013, 7, 6), NOW) < 13).toBe(true);  // 12
    expect(computeAgeFromDob(dob(2013, 7, 5), NOW) < 13).toBe(false); // 13
  });

  it("minor gate: 17 is a minor, 18 is not", () => {
    expect(computeAgeFromDob(dob(2008, 7, 6), NOW) < 18).toBe(true);  // 17
    expect(computeAgeFromDob(dob(2008, 7, 5), NOW) < 18).toBe(false); // 18
  });
});
