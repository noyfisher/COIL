/**
 * Phase 1 (monitoring dashboard): cost math for AI usage telemetry.
 *
 * `computeCostUSD` runs on every production AI request path, so the contract
 * under test is as much "never throws / never guesses" as it is arithmetic:
 * an unknown model must yield null (recorded as usage-without-cost) rather
 * than a fabricated 0 that would silently understate the daily spend.
 */

import { computeCostUSD, PRICING_USD_PER_MTOK, FLAT_COST_USD } from "../src/ai-pricing";
import { MODEL_CONFIG } from "../src/prompts";

describe("PRICING_USD_PER_MTOK", () => {
  it("prices every model MODEL_CONFIG can actually send", () => {
    for (const [requestType, config] of Object.entries(MODEL_CONFIG)) {
      expect(
        Object.prototype.hasOwnProperty.call(PRICING_USD_PER_MTOK, config.model),
      ).toBe(true);
      // Guard against a silently mis-typed entry for this request type.
      expect(PRICING_USD_PER_MTOK[config.model].in).toBeGreaterThan(0);
      expect(requestType.length).toBeGreaterThan(0);
    }
  });

  it("prices the cross-verify model", () => {
    expect(PRICING_USD_PER_MTOK["gpt-4o-mini"]).toEqual({ in: 0.15, out: 0.60 });
  });

  it("charges Haiku cache writes at 1.25x input (5-minute ephemeral cache)", () => {
    const haiku = PRICING_USD_PER_MTOK["claude-haiku-4-5-20251001"];
    expect(haiku.cacheWrite).toBeCloseTo(haiku.in * 1.25, 10);
  });
});

describe("computeCostUSD — known tuple", () => {
  it("sums input, output, cache-write and cache-read at their own rates", () => {
    // Haiku 4.5: $1.00 in / $5.00 out / $1.25 cache write / $0.10 cache read per MTok.
    //   1,000 in     → 0.001
    //     500 out    → 0.0025
    //   2,000 write  → 0.0025
    //  10,000 read   → 0.001
    const cost = computeCostUSD("claude-haiku-4-5-20251001", {
      tokensIn: 1_000,
      tokensOut: 500,
      cacheCreateTokens: 2_000,
      cacheReadTokens: 10_000,
    });
    expect(cost).toBeCloseTo(0.007, 10);
  });

  it("treats absent token fields as zero", () => {
    expect(computeCostUSD("claude-haiku-4-5-20251001", { tokensOut: 1_000_000 })).toBe(5);
    expect(computeCostUSD("claude-haiku-4-5-20251001", {})).toBe(0);
  });

  it("ignores cache fields for a model with no cache pricing", () => {
    // gpt-4o-mini has no cacheWrite/cacheRead — those tokens contribute 0.
    const cost = computeCostUSD("gpt-4o-mini", {
      tokensIn: 1_000_000,
      tokensOut: 1_000_000,
      cacheCreateTokens: 5_000_000,
      cacheReadTokens: 5_000_000,
    });
    expect(cost).toBeCloseTo(0.75, 10);
  });
});

describe("computeCostUSD — unknown / malformed input", () => {
  it("returns null for an unknown model", () => {
    expect(computeCostUSD("claude-some-future-model", { tokensIn: 1000 })).toBeNull();
  });

  it("returns null for the managed-agent placeholder model", () => {
    expect(computeCostUSD("managed_agent", { tokensIn: 0 })).toBeNull();
  });

  it("returns null for an empty or non-string model", () => {
    expect(computeCostUSD("", { tokensIn: 1000 })).toBeNull();
    // @ts-expect-error deliberately wrong type at runtime
    expect(computeCostUSD(undefined, { tokensIn: 1000 })).toBeNull();
  });

  it("does not resolve Object.prototype keys as models", () => {
    expect(computeCostUSD("constructor", { tokensIn: 1000 })).toBeNull();
    expect(computeCostUSD("toString", { tokensIn: 1000 })).toBeNull();
  });

  it("never throws on malformed usage values", () => {
    const cost = computeCostUSD("claude-haiku-4-5-20251001", {
      // @ts-expect-error deliberately wrong types at runtime
      tokensIn: "1000",
      tokensOut: NaN,
      cacheCreateTokens: -500,
      // @ts-expect-error deliberately wrong types at runtime
      cacheReadTokens: null,
    });
    expect(cost).toBe(0);
    // @ts-expect-error deliberately wrong type at runtime
    expect(computeCostUSD("gpt-4o-mini", undefined)).toBe(0);
  });
});

describe("FLAT_COST_USD", () => {
  it("carries per-operation estimates for the non-token providers", () => {
    expect(FLAT_COST_USD.bfl_flux_image).toBe(0.05);
    expect(FLAT_COST_USD.gemini_flash_qa).toBe(0.005);
  });
});
