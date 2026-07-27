/**
 * AI usage & cost telemetry (Phase 1 of the monitoring dashboard).
 *
 * Every attempted provider call writes:
 *   1. `aiUsage/{autoId}`        — one immutable per-call record
 *   2. `aiUsageDaily/{YYYY-MM-DD}` — an increment-merged rollup for the day
 *
 * PRIVACY: an `aiUsage` doc NEVER carries a uid or any user content. The doc
 * shape is built by `buildUsageDoc` from an explicit field list, so a caller
 * cannot accidentally widen it.
 *
 * SAFETY CONTRACT: `recordAiUsage` is called from production request paths
 * (claudeProxy et al.). Its entire body is wrapped in try/catch and it returns
 * void — it can never throw into, or otherwise disturb, a response path. A
 * telemetry failure degrades to a Cloud Logging warning.
 *
 * Rollup ownership is Admin-SDK only; Firestore's default-deny covers both
 * collections (no rules change needed).
 */

import * as admin from "firebase-admin";
import { newRequestContext, logWarn } from "./logger";
import { computeCostUSD, TokenUsage } from "./ai-pricing";

export const AI_USAGE_COLLECTION = "aiUsage";
export const AI_USAGE_DAILY_COLLECTION = "aiUsageDaily";

/**
 * - `ok`               — provider returned a usable response
 * - `upstream_error`   — provider returned a non-2xx
 * - `invalid_response` — provider responded 2xx but the payload failed validation
 * - `error`            — the call threw (network/timeout/parse)
 */
export type AiUsageStatus = "ok" | "upstream_error" | "invalid_response" | "error";

export interface AiUsageEntry extends TokenUsage {
  /** Cloud Function that made the call, e.g. "claudeProxy". */
  fn: string;
  /** Logical request type, e.g. "analysis", "cross_verify", "exercise_image". */
  requestType: string;
  /** "anthropic" | "openai" | "bfl" | "google" | ... */
  provider: string;
  /** Provider model id as actually sent (used for the price lookup). */
  model: string;
  /** Wall-clock duration of the provider call. */
  durationMs?: number;
  status: AiUsageStatus;
  /**
   * Explicit cost override. Use for flat-priced providers, or pass `null` when
   * the cost is genuinely unknown (e.g. managed-agent calls whose tokens the
   * handler cannot see). Omit entirely to compute from model + tokens.
   */
  costUSD?: number | null;
  /** True when tokens and/or cost are approximations rather than provider-reported. */
  estimated?: boolean;
  /** Injectable clock (tests). */
  at?: Date;
}

/** Fully-resolved, plain-data view of an entry — the input to both doc builders. */
export interface NormalizedAiUsage {
  day: string;
  fn: string;
  requestType: string;
  provider: string;
  model: string;
  tokensIn: number;
  tokensOut: number;
  cacheCreateTokens: number;
  cacheReadTokens: number;
  durationMs: number;
  status: AiUsageStatus;
  costUSD: number | null;
  estimated: boolean;
}

/**
 * Minimal surface of `admin.firestore.FieldValue` used by the doc builders.
 * Injected so the builders stay pure and unit-testable without firebase-admin.
 */
export interface FieldValueFactory {
  increment(n: number): unknown;
  serverTimestamp(): unknown;
}

const adminFieldValues: FieldValueFactory = {
  increment: (n: number) => admin.firestore.FieldValue.increment(n),
  serverTimestamp: () => admin.firestore.FieldValue.serverTimestamp(),
};

/** UTC calendar day, `YYYY-MM-DD`. Invalid dates fall back to "now". */
export function utcDayKey(at: Date = new Date()): string {
  const d = at instanceof Date && Number.isFinite(at.getTime()) ? at : new Date();
  return d.toISOString().slice(0, 10);
}

/** Non-negative finite integer-ish number, or 0. */
function safeNumber(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : 0;
}

function safeString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.length > 0 ? value.slice(0, 200) : fallback;
}

/**
 * Firestore map keys can't contain `.`, `/`, `~`, `*`, `[`, `]`, and must be
 * non-empty. `byType` is keyed by requestType, so sanitize defensively even
 * though every current caller passes a known-safe literal.
 */
export function requestTypeKey(requestType: string): string {
  if (typeof requestType !== "string") return "unknown";
  const cleaned = requestType.trim().toLowerCase().replace(/[^a-z0-9_-]+/g, "_").slice(0, 64);
  return cleaned.length > 0 ? cleaned : "unknown";
}

/** Resolve defaults + cost. Pure. */
export function normalizeAiUsageEntry(entry: AiUsageEntry, now: Date = new Date()): NormalizedAiUsage {
  const model = safeString(entry?.model, "unknown");
  const tokens = {
    tokensIn: safeNumber(entry?.tokensIn),
    tokensOut: safeNumber(entry?.tokensOut),
    cacheCreateTokens: safeNumber(entry?.cacheCreateTokens),
    cacheReadTokens: safeNumber(entry?.cacheReadTokens),
  };

  // `undefined` means "compute it"; an explicit `null` means "unknowable".
  const costUSD = entry?.costUSD === undefined
    ? computeCostUSD(model, tokens)
    : (typeof entry.costUSD === "number" && Number.isFinite(entry.costUSD) ? entry.costUSD : null);

  const status: AiUsageStatus = entry?.status === "ok" || entry?.status === "upstream_error" ||
    entry?.status === "invalid_response" || entry?.status === "error" ? entry.status : "error";

  return {
    day: utcDayKey(entry?.at ?? now),
    fn: safeString(entry?.fn, "unknown"),
    requestType: safeString(entry?.requestType, "unknown"),
    provider: safeString(entry?.provider, "unknown"),
    model,
    ...tokens,
    durationMs: safeNumber(entry?.durationMs),
    status,
    costUSD,
    estimated: entry?.estimated === true,
  };
}

/**
 * The per-call `aiUsage` document. Explicit field list — NO uid, no prompt or
 * response content, ever.
 */
export function buildUsageDoc(
  n: NormalizedAiUsage,
  fv: FieldValueFactory = adminFieldValues,
): Record<string, unknown> {
  return {
    ts: fv.serverTimestamp(),
    day: n.day,
    fn: n.fn,
    requestType: n.requestType,
    provider: n.provider,
    model: n.model,
    tokensIn: n.tokensIn,
    tokensOut: n.tokensOut,
    cacheCreateTokens: n.cacheCreateTokens,
    cacheReadTokens: n.cacheReadTokens,
    durationMs: n.durationMs,
    status: n.status,
    costUSD: n.costUSD,
    estimated: n.estimated,
  };
}

/**
 * The increment-merge payload for `aiUsageDaily/{day}`. Every numeric field is
 * a FieldValue.increment sentinel so concurrent calls compose; `date` and
 * `updatedAt` are plain overwrites. Nested `byType` maps merge correctly under
 * `set(..., {merge: true})`.
 */
export function buildDailyRollup(
  n: NormalizedAiUsage,
  fv: FieldValueFactory = adminFieldValues,
): Record<string, unknown> {
  const isError = n.status !== "ok";
  const errorDelta = isError ? 1 : 0;
  const cost = n.costUSD ?? 0;
  const typeKey = requestTypeKey(n.requestType);

  return {
    date: n.day,
    calls: fv.increment(1),
    errors: fv.increment(errorDelta),
    tokensIn: fv.increment(n.tokensIn),
    tokensOut: fv.increment(n.tokensOut),
    cacheCreateTokens: fv.increment(n.cacheCreateTokens),
    cacheReadTokens: fv.increment(n.cacheReadTokens),
    totalCostUSD: fv.increment(cost),
    totalDurationMs: fv.increment(n.durationMs),
    byType: {
      [typeKey]: {
        calls: fv.increment(1),
        errors: fv.increment(errorDelta),
        costUSD: fv.increment(cost),
        tokensIn: fv.increment(n.tokensIn),
        tokensOut: fv.increment(n.tokensOut),
        durationMs: fv.increment(n.durationMs),
      },
    },
    updatedAt: fv.serverTimestamp(),
  };
}

/**
 * Record one attempted AI provider call. Fire-and-await from a request path:
 * this function is guaranteed not to throw and returns void, so it cannot
 * change the caller's control flow. Awaiting (rather than floating the
 * promise) is required because Cloud Functions v1 freezes the instance once
 * the response is sent.
 *
 * Do NOT call this for pre-provider rejections (bad token, age policy, rate
 * limit, quota/budget denial) — no provider call, no usage record.
 */
export async function recordAiUsage(entry: AiUsageEntry): Promise<void> {
  try {
    const normalized = normalizeAiUsageEntry(entry);
    const db = admin.firestore();
    await Promise.all([
      db.collection(AI_USAGE_COLLECTION).add(buildUsageDoc(normalized)),
      db.collection(AI_USAGE_DAILY_COLLECTION)
        .doc(normalized.day)
        .set(buildDailyRollup(normalized), { merge: true }),
    ]);
  } catch (err) {
    // Telemetry must never surface to the caller. Warn and move on.
    try {
      logWarn(
        newRequestContext(typeof entry?.fn === "string" ? entry.fn : "recordAiUsage"),
        "ai_usage_record_failed",
        {
          requestType: typeof entry?.requestType === "string" ? entry.requestType : undefined,
          errorMessage: err instanceof Error ? err.message : String(err),
        },
      );
    } catch {
      // Even the logger failed — nothing further is safe or useful to do here.
    }
  }
}
