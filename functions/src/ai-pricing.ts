/**
 * Static AI price table + cost math for usage telemetry.
 *
 * ===========================================================================
 * TODO(pricing): VERIFY EVERY NUMBER IN THIS FILE AGAINST THE CURRENT PROVIDER
 * PRICING PAGES BEFORE USING ANY $ FIGURE FOR REAL BUDGETING OR FORECASTING.
 * These rates were transcribed by hand and are NOT auto-synced with the
 * providers. Treat dashboard dollar amounts as order-of-magnitude estimates
 * until this TODO is cleared. (Anthropic: anthropic.com/pricing, OpenAI:
 * openai.com/api/pricing, BFL: bfl.ai pricing, Gemini: ai.google.dev/pricing.)
 * ===========================================================================
 *
 * Unknown model → `computeCostUSD` returns null (never throws, never guesses).
 * Callers record `costUSD: null` and the rollup adds 0 for that call, so an
 * unpriced model shows up as usage-without-cost rather than a wrong total.
 */

export interface ModelPricing {
  /** USD per 1M input tokens (uncached). */
  in: number;
  /** USD per 1M output tokens. */
  out: number;
  /** USD per 1M tokens written to the prompt cache. Omit if not applicable. */
  cacheWrite?: number;
  /** USD per 1M tokens read from the prompt cache. Omit if not applicable. */
  cacheRead?: number;
}

/**
 * Prices are per MILLION tokens (MTok), USD.
 *
 * Model IDs must match what the code actually sends:
 * - `claude-haiku-4-5-20251001` — every entry of MODEL_CONFIG in prompts.ts
 *   (all 10 request types, including the scheduled nightly_report) plus both
 *   managed-agent fallback paths.
 *   cacheWrite is 1.25x input: claudeProxy uses `cache_control: {type:
 *   "ephemeral"}` (5-minute TTL) on its system blocks — see the systemBlocks
 *   construction in index.ts — which is the 1.25x tier, not the 1h 2x tier.
 * - `gpt-4o-mini` — the cross-model verifier in crossVerify (index.ts).
 */
export const PRICING_USD_PER_MTOK: Record<string, ModelPricing> = {
  "claude-haiku-4-5-20251001": { in: 1.00, out: 5.00, cacheWrite: 1.25, cacheRead: 0.10 },
  "gpt-4o-mini": { in: 0.15, out: 0.60 },
};

/**
 * Flat per-call costs for providers billed per operation rather than per token.
 * Rough estimates — see the TODO banner above.
 */
export const FLAT_COST_USD = {
  /** One BFL FLUX 2 Pro image generation (image-generation.ts). */
  bfl_flux_image: 0.05,
  /** One Gemini 2.5 Flash vision QA call on a generated image. */
  gemini_flash_qa: 0.005,
} as const;

/** Token counts for one provider call. All fields optional; absent → 0. */
export interface TokenUsage {
  tokensIn?: number;
  tokensOut?: number;
  cacheCreateTokens?: number;
  cacheReadTokens?: number;
}

/** Non-negative finite number, or 0. Keeps bad provider payloads out of the math. */
function safeTokens(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : 0;
}

/** Round to 6 decimals — sub-micro-dollar precision without float noise. */
function round6(value: number): number {
  return Math.round(value * 1e6) / 1e6;
}

/**
 * USD cost of one provider call, or null when the model has no price entry.
 *
 * NEVER THROWS — telemetry must not be able to break a request path. Malformed
 * usage values are treated as 0; an unknown or non-string model yields null.
 */
export function computeCostUSD(model: string, usage: TokenUsage): number | null {
  try {
    if (typeof model !== "string" || model.length === 0) return null;
    if (!Object.prototype.hasOwnProperty.call(PRICING_USD_PER_MTOK, model)) return null;
    const pricing = PRICING_USD_PER_MTOK[model];
    if (!pricing) return null;

    const perToken = (rate: number | undefined) => (typeof rate === "number" ? rate / 1_000_000 : 0);

    const total =
      safeTokens(usage?.tokensIn) * perToken(pricing.in) +
      safeTokens(usage?.tokensOut) * perToken(pricing.out) +
      safeTokens(usage?.cacheCreateTokens) * perToken(pricing.cacheWrite) +
      safeTokens(usage?.cacheReadTokens) * perToken(pricing.cacheRead);

    return Number.isFinite(total) ? round6(total) : null;
  } catch {
    return null;
  }
}
