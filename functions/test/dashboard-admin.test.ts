/**
 * Phase 3 (monitoring dashboard): the admin gate and the pure response
 * shapers behind `dashboardData`.
 *
 * What MUST be pinned here:
 *   - the allowlist fails CLOSED (unset/blank env → nobody is an admin)
 *   - `aiCallsToday` honours the budget counter's LAZY reset (a stale
 *     yesterday doc must read as 0, not as yesterday's leftover count)
 *   - a missing GA4 day is null, not 0, on the sparkline — otherwise "not
 *     exported yet" and "genuinely zero users" look identical on a chart
 *   - derived AI figures (avg latency, error rate, per-type cost) come out of
 *     a rollup that only stores sums
 *
 * Firestore itself isn't exercised — these are all pure functions.
 */

import {
  parseAdminEmails,
  parseDaysParam,
  resolveAiCallsToday,
  shapeAiUsageDaily,
  buildTrendPoint,
  computeTotalsDeltas,
  shiftDayKey,
  toJsonSafe,
} from "../src/dashboard-data";

// ---------------------------------------------------------------------------
// parseAdminEmails
// ---------------------------------------------------------------------------

describe("parseAdminEmails", () => {
  it("returns an empty set when unset — nobody is an admin by default", () => {
    expect(parseAdminEmails(undefined).size).toBe(0);
  });

  it("returns an empty set for a blank string", () => {
    expect(parseAdminEmails("   ").size).toBe(0);
  });

  it("parses a single address", () => {
    const allowed = parseAdminEmails("ops@org.example");
    expect(allowed.has("ops@org.example")).toBe(true);
    expect(allowed.size).toBe(1);
  });

  it("lower-cases so token emails match regardless of case", () => {
    const allowed = parseAdminEmails("Ops@Org.Example");
    expect(allowed.has("ops@org.example")).toBe(true);
    expect(allowed.has("Ops@Org.Example")).toBe(false);
  });

  it("trims whitespace around each entry", () => {
    const allowed = parseAdminEmails("  a@org.example ,\tb@org.example  ");
    expect(Array.from(allowed).sort()).toEqual(["a@org.example", "b@org.example"]);
  });

  it("parses a multi-entry list and drops empty entries", () => {
    const allowed = parseAdminEmails("a@org.example,,b@org.example, ,c@org.example,");
    expect(Array.from(allowed).sort()).toEqual([
      "a@org.example",
      "b@org.example",
      "c@org.example",
    ]);
  });

  it("de-duplicates case variants of the same address", () => {
    expect(parseAdminEmails("a@org.example,A@ORG.EXAMPLE").size).toBe(1);
  });

  it("ignores non-string input", () => {
    expect(parseAdminEmails(null as unknown as string | undefined).size).toBe(0);
    expect(parseAdminEmails(42 as unknown as string | undefined).size).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// parseDaysParam
// ---------------------------------------------------------------------------

describe("parseDaysParam", () => {
  it("accepts the three supported windows", () => {
    expect(parseDaysParam("7")).toBe(7);
    expect(parseDaysParam("30")).toBe(30);
    expect(parseDaysParam("90")).toBe(90);
  });

  it("defaults to 30 when absent or unsupported", () => {
    expect(parseDaysParam(undefined)).toBe(30);
    expect(parseDaysParam("")).toBe(30);
    expect(parseDaysParam("14")).toBe(30);
    expect(parseDaysParam("9999")).toBe(30);
    expect(parseDaysParam("drop table")).toBe(30);
  });

  it("accepts a repeated query param by taking the first value", () => {
    expect(parseDaysParam(["7", "90"])).toBe(7);
  });
});

// ---------------------------------------------------------------------------
// resolveAiCallsToday — the lazy-reset gotcha
// ---------------------------------------------------------------------------

describe("resolveAiCallsToday", () => {
  it("reports the count when the counter is for today", () => {
    expect(resolveAiCallsToday({ date: "2026-07-26", count: 42 }, "2026-07-26")).toBe(42);
  });

  it("reports 0 for a stale counter — it resets lazily on the next AI call", () => {
    expect(resolveAiCallsToday({ date: "2026-07-25", count: 199 }, "2026-07-26")).toBe(0);
  });

  it("reports 0 when the doc is missing", () => {
    expect(resolveAiCallsToday(undefined, "2026-07-26")).toBe(0);
  });

  it("reports 0 when the count is missing or malformed", () => {
    expect(resolveAiCallsToday({ date: "2026-07-26" }, "2026-07-26")).toBe(0);
    expect(resolveAiCallsToday({ date: "2026-07-26", count: "12" }, "2026-07-26")).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// shapeAiUsageDaily
// ---------------------------------------------------------------------------

describe("shapeAiUsageDaily", () => {
  const doc = {
    date: "2026-07-26",
    calls: 8,
    errors: 2,
    tokensIn: 12_000,
    tokensOut: 3_000,
    totalCostUSD: 0.0271234567,
    totalDurationMs: 12_000,
    byType: {
      analysis: { calls: 5, errors: 1, costUSD: 0.02 },
      rehab_plan: { calls: 3, errors: 1, costUSD: 0.0071234567 },
    },
  };

  it("derives avg latency from the stored duration sum", () => {
    expect(shapeAiUsageDaily("2026-07-26", doc).avgLatencyMs).toBe(1_500);
  });

  it("derives the error rate", () => {
    expect(shapeAiUsageDaily("2026-07-26", doc).errorRatePct).toBe(25);
  });

  it("flattens byType to per-type cost", () => {
    expect(shapeAiUsageDaily("2026-07-26", doc).byTypeCostUSD).toEqual({
      analysis: 0.02,
      rehab_plan: 0.007123,
    });
  });

  it("returns zeros (not NaN) for a missing doc", () => {
    const shaped = shapeAiUsageDaily("2026-07-26", undefined);
    expect(shaped).toEqual({
      date: "2026-07-26",
      calls: 0,
      errors: 0,
      errorRatePct: 0,
      tokensIn: 0,
      tokensOut: 0,
      totalCostUSD: 0,
      avgLatencyMs: 0,
      byTypeCostUSD: {},
    });
  });

  it("never divides by zero when a day has no calls", () => {
    const shaped = shapeAiUsageDaily("2026-07-26", { calls: 0, errors: 0, totalDurationMs: 0 });
    expect(shaped.avgLatencyMs).toBe(0);
    expect(shaped.errorRatePct).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// buildTrendPoint
// ---------------------------------------------------------------------------

describe("buildTrendPoint", () => {
  const daily = {
    engagement: { dau: 12, totalSessions: 20, workoutsStarted: 7, workoutsCompleted: 5 },
    funnel: { rehabPlanGenerated: 3 },
  };

  it("joins the GA4 day with that day's AI cost", () => {
    const point = buildTrendPoint("2026-07-25", daily, {
      calls: 4,
      totalCostUSD: 0.01,
      totalDurationMs: 4_000,
    });
    expect(point).toEqual({
      date: "2026-07-25",
      dau: 12,
      sessions: 20,
      workoutsStarted: 7,
      workoutsCompleted: 5,
      plansGenerated: 3,
      aiCalls: 4,
      aiCostUSD: 0.01,
    });
  });

  it("nulls GA4 metrics when the day has not been materialized yet", () => {
    const point = buildTrendPoint("2026-07-26", undefined, { calls: 2, totalCostUSD: 0.004 });
    expect(point.dau).toBeNull();
    expect(point.sessions).toBeNull();
    expect(point.workoutsCompleted).toBeNull();
    expect(point.plansGenerated).toBeNull();
    // AI telemetry is written same-day, so absence there really is zero.
    expect(point.aiCalls).toBe(2);
    expect(point.aiCostUSD).toBe(0.004);
  });

  it("zeroes AI metrics when only the GA4 day exists", () => {
    const point = buildTrendPoint("2026-07-25", daily, undefined);
    expect(point.dau).toBe(12);
    expect(point.aiCalls).toBe(0);
    expect(point.aiCostUSD).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// computeTotalsDeltas
// ---------------------------------------------------------------------------

describe("computeTotalsDeltas", () => {
  it("subtracts the older doc from the newer one", () => {
    expect(
      computeTotalsDeltas(
        { totalUsers: 120, totalPlans: 300, totalWorkoutSessions: 900, activePlansCount: 40 },
        { totalUsers: 100, totalPlans: 280, totalWorkoutSessions: 850, activePlansCount: 45 },
      ),
    ).toEqual({
      totalUsers: 20,
      totalPlans: 20,
      totalWorkoutSessions: 50,
      activePlansCount: -5,
    });
  });

  it("returns null without a baseline — a missing comparison is not '+0'", () => {
    expect(computeTotalsDeltas({ totalUsers: 120 }, undefined)).toBeNull();
    expect(computeTotalsDeltas(undefined, { totalUsers: 100 })).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// shiftDayKey
// ---------------------------------------------------------------------------

describe("shiftDayKey", () => {
  it("walks backwards across a month boundary", () => {
    expect(shiftDayKey("2026-08-03", -7)).toBe("2026-07-27");
  });

  it("walks forwards", () => {
    expect(shiftDayKey("2026-07-26", 1)).toBe("2026-07-27");
  });

  it("handles a leap day", () => {
    expect(shiftDayKey("2028-03-01", -1)).toBe("2028-02-29");
  });

  it("returns the input unchanged when it isn't a date", () => {
    expect(shiftDayKey("not-a-date", -1)).toBe("not-a-date");
  });
});

// ---------------------------------------------------------------------------
// toJsonSafe
// ---------------------------------------------------------------------------

describe("toJsonSafe", () => {
  it("passes primitives and arrays through", () => {
    expect(toJsonSafe({ a: 1, b: "x", c: [1, 2] })).toEqual({ a: 1, b: "x", c: [1, 2] });
  });

  it("converts Dates to ISO strings", () => {
    expect(toJsonSafe({ at: new Date("2026-07-26T12:00:00.000Z") }))
      .toEqual({ at: "2026-07-26T12:00:00.000Z" });
  });

  it("normalizes undefined to null so JSON keeps the key", () => {
    expect(toJsonSafe({ a: undefined })).toEqual({ a: null });
  });

  it("recurses into nested structures (Sankey edges)", () => {
    expect(toJsonSafe({ edges: [{ source: "A", target: "B", count: 3 }] }))
      .toEqual({ edges: [{ source: "A", target: "B", count: 3 }] });
  });
});
