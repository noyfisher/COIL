/**
 * Phase 6 (monitoring dashboard): pure helpers factored out of collectMetrics
 * for the nightly report's day-over-day deltas and AI cost breakdown.
 */

import { formatDelta, topRequestTypesByCost } from "../src/index";

describe("formatDelta", () => {
  it("signs a positive delta", () => {
    expect(formatDelta(5)).toBe("+5");
  });

  it("signs a negative delta (e.g. after a deletion)", () => {
    expect(formatDelta(-3)).toBe("-3");
  });

  it("prints zero bare, no sign", () => {
    expect(formatDelta(0)).toBe("0");
  });

  it("collapses non-finite input to 0 defensively", () => {
    expect(formatDelta(NaN)).toBe("0");
    expect(formatDelta(Infinity)).toBe("0");
    expect(formatDelta(-Infinity)).toBe("0");
  });
});

describe("topRequestTypesByCost", () => {
  it("sorts by cost descending", () => {
    expect(
      topRequestTypesByCost({ analysis: 1.5, rehab_plan: 3.2, form_analysis: 0.4 }),
    ).toEqual([
      { type: "rehab_plan", costUSD: 3.2 },
      { type: "analysis", costUSD: 1.5 },
      { type: "form_analysis", costUSD: 0.4 },
    ]);
  });

  it("breaks ties alphabetically for deterministic output", () => {
    expect(topRequestTypesByCost({ zeta: 1, alpha: 1 })).toEqual([
      { type: "alpha", costUSD: 1 },
      { type: "zeta", costUSD: 1 },
    ]);
  });

  it("respects the limit param", () => {
    const result = topRequestTypesByCost(
      { a: 5, b: 4, c: 3, d: 2, e: 1, f: 0.5 },
      3,
    );
    expect(result).toHaveLength(3);
    expect(result.map((r) => r.type)).toEqual(["a", "b", "c"]);
  });

  it("defaults to a limit of 5", () => {
    const result = topRequestTypesByCost({ a: 6, b: 5, c: 4, d: 3, e: 2, f: 1 });
    expect(result).toHaveLength(5);
  });

  it("returns an empty array for undefined/null input", () => {
    expect(topRequestTypesByCost(undefined)).toEqual([]);
    expect(topRequestTypesByCost(null)).toEqual([]);
  });

  it("returns an empty array for an empty map", () => {
    expect(topRequestTypesByCost({})).toEqual([]);
  });

  it("treats non-finite cost entries as 0 rather than throwing", () => {
    expect(topRequestTypesByCost({ weird: NaN as unknown as number, normal: 2 })).toEqual([
      { type: "normal", costUSD: 2 },
      { type: "weird", costUSD: 0 },
    ]);
  });
});
