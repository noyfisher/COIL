/**
 * WP-5.3: tests for the server-side age approximation used by the minors
 * safeguard in `claudeProxy`. `computeAgeFromDob` uses 365.25-day years, so a
 * DOB exactly N years before `nowMs` yields age N. We pass a fixed `nowMs` so
 * the test is deterministic and independent of the machine clock.
 */

import { computeAgeFromDob } from "../src/index";

// Fixed reference "now": 2026-07-05T00:00:00.000Z.
const NOW_MS = Date.UTC(2026, 6, 5, 0, 0, 0, 0);
const YEAR_MS = 365.25 * 24 * 3600 * 1000;

/** DOB that is exactly `years` (365.25-day) years before NOW_MS. */
function dobYearsAgo(years: number): number {
  return NOW_MS - years * YEAR_MS;
}

describe("computeAgeFromDob", () => {
  it("returns 12 for a DOB exactly 12 years ago (under-13 block)", () => {
    expect(computeAgeFromDob(dobYearsAgo(12), NOW_MS)).toBe(12);
  });

  it("returns 13 for a DOB exactly 13 years ago (minimum age)", () => {
    expect(computeAgeFromDob(dobYearsAgo(13), NOW_MS)).toBe(13);
  });

  it("returns 17 for a DOB exactly 17 years ago (still a minor)", () => {
    expect(computeAgeFromDob(dobYearsAgo(17), NOW_MS)).toBe(17);
  });

  it("returns 18 for a DOB exactly 18 years ago (no longer a minor)", () => {
    expect(computeAgeFromDob(dobYearsAgo(18), NOW_MS)).toBe(18);
  });

  it("floors toward the just-completed year (18y minus a day is still 17)", () => {
    const oneDayMs = 24 * 3600 * 1000;
    expect(computeAgeFromDob(dobYearsAgo(18) + oneDayMs, NOW_MS)).toBe(17);
  });

  it("classifies the 12/13 boundary correctly for the under-13 gate", () => {
    expect(computeAgeFromDob(dobYearsAgo(12), NOW_MS) < 13).toBe(true);
    expect(computeAgeFromDob(dobYearsAgo(13), NOW_MS) < 13).toBe(false);
  });

  it("classifies the 17/18 boundary correctly for the minor gate", () => {
    expect(computeAgeFromDob(dobYearsAgo(17), NOW_MS) < 18).toBe(true);
    expect(computeAgeFromDob(dobYearsAgo(18), NOW_MS) < 18).toBe(false);
  });
});
