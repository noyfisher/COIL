/**
 * Phase 1 (monitoring dashboard): shaping helpers behind `recordAiUsage`.
 *
 * The Firestore write itself is Admin-SDK-only and is exercised live (deploy +
 * one real request); what MUST be pinned here is the shape:
 *   - the per-call `aiUsage` doc carries NO uid (aggregate-only, matches the
 *     project's telemetry-minimization posture)
 *   - the `aiUsageDaily` rollup is all FieldValue.increment sentinels, so
 *     concurrent calls compose instead of clobbering
 *   - errors are counted only for non-"ok" statuses
 *   - the day key is UTC (the dashboard labels this source day explicitly)
 *
 * The builders take an injected FieldValue factory, so these run without
 * firebase-admin — same fake-sentinel approach as rate-limit.test.ts.
 */

import {
  utcDayKey,
  requestTypeKey,
  normalizeAiUsageEntry,
  buildUsageDoc,
  buildDailyRollup,
  AiUsageEntry,
  FieldValueFactory,
} from "../src/ai-usage";

// Fake sentinels that mimic firebase-admin's FieldValue API.
type IncrementSentinel = { __increment: number };
const fv: FieldValueFactory = {
  increment: (n: number): IncrementSentinel => ({ __increment: n }),
  serverTimestamp: () => ({ __serverTimestamp: true }),
};

function inc(value: unknown): number {
  expect(value).toHaveProperty("__increment");
  return (value as IncrementSentinel).__increment;
}

const baseEntry: AiUsageEntry = {
  fn: "claudeProxy",
  requestType: "analysis",
  provider: "anthropic",
  model: "claude-haiku-4-5-20251001",
  tokensIn: 1_000,
  tokensOut: 500,
  cacheCreateTokens: 2_000,
  cacheReadTokens: 10_000,
  durationMs: 1_234,
  status: "ok",
  at: new Date("2026-07-26T23:59:59.999Z"),
};

// ---------------------------------------------------------------------------
// Day key
// ---------------------------------------------------------------------------

describe("utcDayKey", () => {
  it("formats YYYY-MM-DD in UTC", () => {
    expect(utcDayKey(new Date("2026-07-26T14:37:59.123Z"))).toBe("2026-07-26");
  });

  it("uses UTC, not local time, at the day boundary", () => {
    expect(utcDayKey(new Date("2026-07-26T23:59:59.999Z"))).toBe("2026-07-26");
    expect(utcDayKey(new Date("2026-07-27T00:00:00.000Z"))).toBe("2026-07-27");
  });

  it("falls back to now for an invalid date instead of throwing", () => {
    expect(utcDayKey(new Date("not-a-date"))).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

// ---------------------------------------------------------------------------
// byType map key
// ---------------------------------------------------------------------------

describe("requestTypeKey", () => {
  it("passes through the canonical request types", () => {
    expect(requestTypeKey("analysis")).toBe("analysis");
    expect(requestTypeKey("wellness_plan")).toBe("wellness_plan");
    expect(requestTypeKey("cross_verify")).toBe("cross_verify");
  });

  it("replaces characters Firestore map keys can't hold", () => {
    expect(requestTypeKey("weird.type/with*chars")).toBe("weird_type_with_chars");
  });

  it("falls back to 'unknown' for empty / non-string input", () => {
    expect(requestTypeKey("")).toBe("unknown");
    expect(requestTypeKey("   ")).toBe("unknown");
    // @ts-expect-error deliberately wrong type at runtime
    expect(requestTypeKey(undefined)).toBe("unknown");
  });
});

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

describe("normalizeAiUsageEntry", () => {
  it("computes cost from model + tokens when no override is given", () => {
    const n = normalizeAiUsageEntry(baseEntry);
    expect(n.costUSD).toBeCloseTo(0.007, 10);
    expect(n.day).toBe("2026-07-26");
    expect(n.estimated).toBe(false);
  });

  it("honours an explicit null cost (managed-agent path)", () => {
    const n = normalizeAiUsageEntry({
      fn: "agentInsights",
      requestType: "recovery_insights",
      provider: "anthropic",
      model: "managed_agent",
      status: "ok",
      costUSD: null,
      estimated: true,
    });
    expect(n.costUSD).toBeNull();
    expect(n.estimated).toBe(true);
    expect(n.tokensIn).toBe(0);
    expect(n.tokensOut).toBe(0);
  });

  it("honours an explicit flat cost override (image providers)", () => {
    const n = normalizeAiUsageEntry({
      fn: "generateExerciseImage",
      requestType: "exercise_image",
      provider: "bfl",
      model: "flux-2-pro",
      status: "ok",
      costUSD: 0.05,
      estimated: true,
    });
    expect(n.costUSD).toBe(0.05);
  });

  it("yields null cost for an unpriced model rather than 0", () => {
    const n = normalizeAiUsageEntry({ ...baseEntry, model: "some-unpriced-model" });
    expect(n.costUSD).toBeNull();
  });

  it("coerces missing / malformed fields instead of throwing", () => {
    // @ts-expect-error deliberately incomplete at runtime
    const n = normalizeAiUsageEntry({});
    expect(n.fn).toBe("unknown");
    expect(n.requestType).toBe("unknown");
    expect(n.provider).toBe("unknown");
    expect(n.model).toBe("unknown");
    expect(n.tokensIn).toBe(0);
    expect(n.durationMs).toBe(0);
    expect(n.status).toBe("error");
    expect(n.costUSD).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Per-call doc
// ---------------------------------------------------------------------------

describe("buildUsageDoc", () => {
  const doc = buildUsageDoc(normalizeAiUsageEntry(baseEntry), fv);

  it("NEVER includes a uid or any user content", () => {
    expect(Object.keys(doc).sort()).toEqual([
      "cacheCreateTokens", "cacheReadTokens", "costUSD", "day", "durationMs",
      "estimated", "fn", "model", "provider", "requestType", "status",
      "tokensIn", "tokensOut", "ts",
    ]);
    expect(doc).not.toHaveProperty("uid");
  });

  it("carries the call's facts verbatim", () => {
    expect(doc.day).toBe("2026-07-26");
    expect(doc.fn).toBe("claudeProxy");
    expect(doc.requestType).toBe("analysis");
    expect(doc.provider).toBe("anthropic");
    expect(doc.model).toBe("claude-haiku-4-5-20251001");
    expect(doc.tokensIn).toBe(1_000);
    expect(doc.tokensOut).toBe(500);
    expect(doc.cacheCreateTokens).toBe(2_000);
    expect(doc.cacheReadTokens).toBe(10_000);
    expect(doc.durationMs).toBe(1_234);
    expect(doc.status).toBe("ok");
    expect(doc.costUSD).toBeCloseTo(0.007, 10);
  });

  it("stamps ts with a server timestamp sentinel", () => {
    expect(doc.ts).toEqual({ __serverTimestamp: true });
  });

  it("drops an extra field a caller tries to smuggle in", () => {
    const sneaky = { ...baseEntry, uid: "user-123" } as AiUsageEntry;
    expect(buildUsageDoc(normalizeAiUsageEntry(sneaky), fv)).not.toHaveProperty("uid");
  });
});

// ---------------------------------------------------------------------------
// Daily rollup
// ---------------------------------------------------------------------------

describe("buildDailyRollup", () => {
  it("increments every counter for a successful call", () => {
    const r = buildDailyRollup(normalizeAiUsageEntry(baseEntry), fv);

    expect(r.date).toBe("2026-07-26");
    expect(inc(r.calls)).toBe(1);
    expect(inc(r.errors)).toBe(0);
    expect(inc(r.tokensIn)).toBe(1_000);
    expect(inc(r.tokensOut)).toBe(500);
    expect(inc(r.cacheCreateTokens)).toBe(2_000);
    expect(inc(r.cacheReadTokens)).toBe(10_000);
    expect(inc(r.totalCostUSD)).toBeCloseTo(0.007, 10);
    expect(inc(r.totalDurationMs)).toBe(1_234);
    expect(r.updatedAt).toEqual({ __serverTimestamp: true });
  });

  it("nests a per-request-type breakdown under byType", () => {
    const r = buildDailyRollup(normalizeAiUsageEntry(baseEntry), fv);
    const byType = r.byType as Record<string, Record<string, unknown>>;

    expect(Object.keys(byType)).toEqual(["analysis"]);
    expect(inc(byType.analysis.calls)).toBe(1);
    expect(inc(byType.analysis.errors)).toBe(0);
    expect(inc(byType.analysis.costUSD)).toBeCloseTo(0.007, 10);
    expect(inc(byType.analysis.tokensIn)).toBe(1_000);
    expect(inc(byType.analysis.tokensOut)).toBe(500);
    expect(inc(byType.analysis.durationMs)).toBe(1_234);
  });

  it.each(["upstream_error", "invalid_response", "error"] as const)(
    "counts status %s as an error, at top level and per type",
    (status) => {
      const r = buildDailyRollup(normalizeAiUsageEntry({ ...baseEntry, status }), fv);
      const byType = r.byType as Record<string, Record<string, unknown>>;
      expect(inc(r.calls)).toBe(1);
      expect(inc(r.errors)).toBe(1);
      expect(inc(byType.analysis.errors)).toBe(1);
    },
  );

  it("adds 0 to the cost total when cost is unknown (null)", () => {
    const r = buildDailyRollup(
      normalizeAiUsageEntry({ ...baseEntry, model: "managed_agent", costUSD: null }),
      fv,
    );
    const byType = r.byType as Record<string, Record<string, unknown>>;
    expect(inc(r.totalCostUSD)).toBe(0);
    expect(inc(byType.analysis.costUSD)).toBe(0);
    // The call itself is still counted — usage without a price.
    expect(inc(r.calls)).toBe(1);
  });

  it("keys byType by the sanitized request type", () => {
    const r = buildDailyRollup(
      normalizeAiUsageEntry({ ...baseEntry, requestType: "weird.type" }),
      fv,
    );
    expect(Object.keys(r.byType as object)).toEqual(["weird_type"]);
  });
});
