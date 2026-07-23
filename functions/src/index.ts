import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { onSchedule } from "firebase-functions/v2/scheduler";
import sgMail from "@sendgrid/mail";
import { fetchRecoveryInsightsData, MINIMUM_SESSION_COUNT, fetchFormHistoryData, MINIMUM_FORM_HISTORY_COUNT } from "./firestore-queries";
import { runRecoveryInsightsAgent, validateInsightResult } from "./managed-agent";
import { runFormAnalysisAgent, validateFormResult } from "./form-agent";
import { handleGenerateExerciseImage } from "./image-generation";
import { deleteUserFirestoreData } from "./account-deletion";
import { newRequestContext, logCompleted, logError, logWarn } from "./logger";
import { validateClaudeResponse } from "./response-schemas";
import { validateNightlyReport } from "./nightly-report-validator";
import { EXERCISE_CATALOG_CSV } from "./generated/exerciseCatalog";
import { SYSTEM_PROMPTS, MODEL_CONFIG, MINOR_SAFETY_PROMPT } from "./prompts";

// Hard billing shutoff (Pub/Sub triggered). Exported so firebase-tools
// picks it up on deploy. See billing-shutoff.ts for arming instructions.
export { onBudgetAlert } from "./billing-shutoff";

admin.initializeApp();

// ---------------------------------------------------------------------------
// Distributed rate limiter (Tier 2 PR B — Firestore-backed)
// ---------------------------------------------------------------------------
//
// Previously this was an in-memory Map that lived on each Cloud Function
// instance. With horizontal autoscale that meant a single user could burst
// past 20/min by getting routed to multiple instances. This replacement
// uses a Firestore transactional counter keyed by uid + ISO-minute bucket,
// which is atomic across all instances.
//
// Doc path: `rateLimits/{uid}/windows/{ISO-minute}`
// Fields: `count` (Int), `firstSeenAt`, `lastSeenAt` (timestamps for TTL)
//
// Contention: each minute bucket is a separate doc. A single user's 20
// req/min all hit one doc — Firestore handles this comfortably (ceiling
// ~500 writes/sec per doc).
//
// Storage cleanup: TTL policy via `lastSeenAt` field deletes stale docs
// after 2 minutes. TTL is cosmetic only — the ISO-minute key provides
// the correctness guarantee (next-minute requests hit a different doc).
//
// Latency: one extra Firestore transaction per claudeProxy request
// (~50-150ms). This is on top of the existing `checkAndIncrementQuota`
// transaction. Different docs, so no contention between them.
export const RATE_LIMIT_MAX = 20; // max requests per window
export const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute — documents purpose of the ISO-minute bucket

/** ISO-minute bucket key for a given timestamp. */
export function rateLimitWindowKey(now: Date = new Date()): string {
  // YYYY-MM-DDTHH:MM
  return now.toISOString().slice(0, 16);
}

/**
 * Atomically check-and-increment the rate-limit counter for `uid` in the
 * current ISO-minute bucket. Returns `true` if the user is currently OVER
 * the limit (request should be rejected with 429), `false` otherwise.
 *
 * Visible for testing via `__testing__.isRateLimitedWith` below.
 */
export async function isRateLimited(
  uid: string,
  now: Date = new Date(),
  db: admin.firestore.Firestore = admin.firestore(),
): Promise<boolean> {
  const windowKey = rateLimitWindowKey(now);
  const ref = db.collection("rateLimits").doc(uid)
    .collection("windows").doc(windowKey);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.exists ? (snap.data()?.count as number | undefined) : 0) ?? 0;

    if (current >= RATE_LIMIT_MAX) {
      // Do not increment — user is already over.
      return true;
    }

    tx.set(ref, {
      count: admin.firestore.FieldValue.increment(1),
      firstSeenAt: snap.exists
        ? (snap.data()?.firstSeenAt ?? admin.firestore.FieldValue.serverTimestamp())
        : admin.firestore.FieldValue.serverTimestamp(),
      lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return false;
  });
}

// ---------------------------------------------------------------------------
// Per-user quota (Firestore-backed, survives scale-out)
// Doc path: users/{uid}/quotas/current
// Fields: dayKey, dayCount, monthKey, monthCount
// ---------------------------------------------------------------------------
const DAILY_QUOTA = 100;
const MONTHLY_QUOTA = 1000;

type QuotaResult =
  | { ok: true; dayCount: number; monthCount: number }
  | { ok: false; reason: "daily" | "monthly"; limit: number };

function quotaKeys(now: Date = new Date()): { dayKey: string; monthKey: string } {
  const iso = now.toISOString();
  return {
    dayKey: iso.slice(0, 10),      // YYYY-MM-DD
    monthKey: iso.slice(0, 7),     // YYYY-MM
  };
}

async function checkAndIncrementQuota(uid: string): Promise<QuotaResult> {
  const ref = admin.firestore().doc(`users/${uid}/quotas/current`);
  const { dayKey, monthKey } = quotaKeys();

  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};

    const dayCount = data.dayKey === dayKey ? (data.dayCount || 0) : 0;
    const monthCount = data.monthKey === monthKey ? (data.monthCount || 0) : 0;

    if (dayCount >= DAILY_QUOTA) {
      return { ok: false, reason: "daily", limit: DAILY_QUOTA } as QuotaResult;
    }
    if (monthCount >= MONTHLY_QUOTA) {
      return { ok: false, reason: "monthly", limit: MONTHLY_QUOTA } as QuotaResult;
    }

    const nextDay = dayCount + 1;
    const nextMonth = monthCount + 1;
    tx.set(ref, {
      dayKey,
      dayCount: nextDay,
      monthKey,
      monthCount: nextMonth,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, dayCount: nextDay, monthCount: nextMonth } as QuotaResult;
  });
}

/**
 * Refunds one unit each from dayCount and monthCount if the recorded keys
 * still match (otherwise day/month already rolled — silently skip).
 *
 * Fail-safe: errors are logged but not propagated; a stuck decrement is
 * only an accounting drift, not a user-visible error. Called on upstream
 * failure paths so users aren't charged for requests that never returned
 * a useful response.
 */
async function decrementQuota(uid: string): Promise<void> {
  const ref = admin.firestore().doc(`users/${uid}/quotas/current`);
  const { dayKey, monthKey } = quotaKeys();
  try {
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const data = snap.data() || {};

      const patch: Record<string, number> = {};
      if (data.dayKey === dayKey && typeof data.dayCount === "number" && data.dayCount > 0) {
        patch.dayCount = data.dayCount - 1;
      }
      if (data.monthKey === monthKey && typeof data.monthCount === "number" && data.monthCount > 0) {
        patch.monthCount = data.monthCount - 1;
      }
      // Single update with both field deltas — avoids any ambiguity around
      // multiple writes to the same doc in one transaction.
      if (Object.keys(patch).length > 0) {
        tx.update(ref, patch);
      }
    });
  } catch (err) {
    console.error("decrementQuota failed:", err);
  }
}

// ---------------------------------------------------------------------------
// Global daily spend ceiling across ALL AI endpoints (denial-of-wallet guard).
// The per-user quotas above are keyed on uid and are bypassable by minting or
// self-registering identities; this is a single global counter that caps total
// paid AI calls per day regardless of how many identities call. Mirrors the
// image-generation DAILY_BUDGET pattern. Doc: config/aiDailyBudget.
// Increment-on-admit: over-budget calls are rejected (never admitted); admitted
// calls count — a hard ceiling, not precise per-call accounting.
// ---------------------------------------------------------------------------
// Global daily ceiling across ALL AI request types and ALL users. Dev value
// sized to survive virtual-user batches / manual QA without tripping the 429
// ceiling; denial-of-wallet is a prod concern and dev has no public account
// minting. Revisit (likely raise + per-tier scaling) before production.
const AI_DAILY_BUDGET = 200;

async function checkGlobalDailyBudget(): Promise<boolean> {
  const today = new Date().toISOString().slice(0, 10);
  const ref = admin.firestore().collection("config").doc("aiDailyBudget");
  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const count = data.date === today ? (data.count || 0) : 0;
    if (count >= AI_DAILY_BUDGET) {
      return false; // ceiling reached for today
    }
    tx.set(ref, { date: today, count: count + 1 }, { merge: true });
    return true;
  });
}

// ---------------------------------------------------------------------------
// JSON output schemas — kept for future structured output support.
// Structured output (`output` field) requires anthropic-version >= 2025-xx.
// For now the system prompts instruct JSON format directly.
// ---------------------------------------------------------------------------
/* eslint-disable @typescript-eslint/no-unused-vars */
const ANALYSIS_CONDITION_SCHEMA = {
  type: "object" as const,
  properties: {
    conditionName: { type: "string" as const },
    commonName: { type: "string" as const },
    confidence: { type: "number" as const },
    explanation: { type: "string" as const },
    whatItMeans: { type: "string" as const },
    howToManage: { type: "string" as const },
    isRedFlag: { type: "boolean" as const },
    redFlagMessage: { type: "string" as const },
    nextSteps: { type: "array" as const, items: { type: "string" as const } },
  },
  required: [
    "conditionName", "commonName", "confidence", "explanation",
    "whatItMeans", "howToManage", "isRedFlag", "redFlagMessage", "nextSteps",
  ],
  additionalProperties: false,
};

const ANALYSIS_SCHEMA = {
  type: "json_schema" as const,
  json_schema: {
    name: "analysis_response",
    strict: true,
    schema: {
      type: "object" as const,
      properties: {
        conditions: {
          type: "array" as const,
          items: ANALYSIS_CONDITION_SCHEMA,
        },
        overallSummary: { type: "string" as const },
        disclaimerText: { type: "string" as const },
      },
      required: ["conditions", "overallSummary", "disclaimerText"],
      additionalProperties: false,
    },
  },
};

const REHAB_EXERCISE_SCHEMA = {
  type: "object" as const,
  properties: {
    name: { type: "string" as const },
    targetArea: { type: "string" as const },
    description: { type: "string" as const },
    sets: { type: "number" as const },
    reps: { type: "string" as const },
    restSeconds: { type: "number" as const },
    difficulty: { type: "string" as const },
    demonstrationIcon: { type: "string" as const },
    tips: { type: "array" as const, items: { type: "string" as const } },
    contraindications: { type: "array" as const, items: { type: "string" as const } },
    startPosition: { type: "string" as const },
    movement: { type: "string" as const },
    endPosition: { type: "string" as const },
    exerciseCategory: { type: "string" as const },
    imageFileName: { type: "string" as const },
  },
  required: [
    "name", "targetArea", "description", "sets", "reps", "restSeconds",
    "difficulty", "demonstrationIcon", "tips", "contraindications",
    "startPosition", "movement", "endPosition", "exerciseCategory", "imageFileName",
  ],
  additionalProperties: false,
};

const REHAB_PLAN_SCHEMA = {
  type: "json_schema" as const,
  json_schema: {
    name: "rehab_plan_response",
    strict: true,
    schema: {
      type: "object" as const,
      properties: {
        planName: { type: "string" as const },
        exercises: {
          type: "array" as const,
          items: REHAB_EXERCISE_SCHEMA,
        },
        totalWeeks: { type: "number" as const },
        notes: { type: "string" as const },
      },
      required: ["planName", "exercises", "totalWeeks", "notes"],
      additionalProperties: false,
    },
  },
};

// OUTPUT_SCHEMAS kept for future structured output support
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const _OUTPUT_SCHEMAS: Record<string, object> = {
  analysis: ANALYSIS_SCHEMA,
  analysis_verify: ANALYSIS_SCHEMA,
  rehab_plan: REHAB_PLAN_SCHEMA,
};
/* eslint-enable @typescript-eslint/no-unused-vars */

// Client-callable request types. Deny-by-default: server-only prompts
// (e.g. nightly_report, used solely by the scheduled sendNightlyReport job)
// are intentionally excluded so clients cannot relay through the paid key.
export const ALLOWED_REQUEST_TYPES = new Set<string>([
  "analysis", "analysis_verify", "rehab_plan", "exercise_substitute",
  "recovery_insights", "form_analysis", "wellness_analysis",
  "wellness_verify", "wellness_plan",
]);

// ---------------------------------------------------------------------------
// Request / response types
// ---------------------------------------------------------------------------
interface ProxyRequestBody {
  requestType: string;
  messages: { role: string; content: string }[];
}

const ageCache = new Map<string, { age: number | null; fetchedAt: number }>();
const AGE_CACHE_TTL_MS = 15 * 60_000;

export function computeAgeFromDob(dobMs: number, nowMs: number): number {
  return Math.floor((nowMs - dobMs) / (365.25 * 24 * 3600 * 1000));
}

async function getUserAge(uid: string): Promise<number | null> {
  const cached = ageCache.get(uid);
  if (cached && Date.now() - cached.fetchedAt < AGE_CACHE_TTL_MS) return cached.age;
  let age: number | null = null;
  try {
    const db = admin.firestore();
    let dob = (await db.doc(`users/${uid}/profile/health`).get()).get("dateOfBirth");
    if (!dob) dob = (await db.doc(`users/${uid}/consents/legal`).get()).get("dateOfBirth");
    if (dob && typeof dob.toDate === "function") {
      age = computeAgeFromDob(dob.toDate().getTime(), Date.now());
    }
  } catch { /* fail open (adult); the client gate is primary */ }
  ageCache.set(uid, { age, fetchedAt: Date.now() });
  return age;
}

// ---------------------------------------------------------------------------
// Cloud Function: claudeProxy
// ---------------------------------------------------------------------------
export const claudeProxy = functions
  .runWith({ timeoutSeconds: 120, memory: "256MB", secrets: ["ANTHROPIC_API_KEY"] })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("claudeProxy");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1. Authenticate: verify Firebase ID token
    // -----------------------------------------------------------------------
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // -----------------------------------------------------------------------
    // 2. Rate limit
    // -----------------------------------------------------------------------
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Per-user quotas
    // are bypassable by minting identities; this caps total paid AI calls/day.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // -----------------------------------------------------------------------
    // 3. Validate request body
    // -----------------------------------------------------------------------
    const body = req.body as ProxyRequestBody;

    if (!body.requestType || !body.messages) {
      res.status(400).json({
        error: "Missing required fields: requestType, messages",
      });
      return;
    }

    ctx.metadata.requestType = body.requestType;

    // Validate requestType is allowed (prevents misuse of API key)
    if (!ALLOWED_REQUEST_TYPES.has(body.requestType)) {
      res.status(400).json({
        error: `Invalid requestType. Allowed: ${[...ALLOWED_REQUEST_TYPES].join(", ")}`,
      });
      return;
    }

    // Validate message roles — only "user" role is allowed from clients
    const invalidRole = body.messages.find((m) => m.role !== "user");
    if (invalidRole) {
      res.status(400).json({ error: "Only 'user' role messages are allowed" });
      return;
    }

    // Validate message content length (prevent abuse)
    // form_analysis may have longer messages due to per-rep metrics data
    const maxMessageLength = body.requestType === "form_analysis" ? 20000 : 10000;
    const totalMessageLength = body.messages.reduce((sum, m) => sum + (m.content?.length || 0), 0);
    if (totalMessageLength > maxMessageLength) {
      res.status(400).json({ error: "Message content too long" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get Anthropic API key from environment
    // -----------------------------------------------------------------------
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      logError(ctx, new Error("ANTHROPIC_API_KEY not configured in environment"));
      res.status(500).json({ error: "Server configuration error" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4b. Per-user daily/monthly quota (cost cap, survives scale-out).
    // Placed AFTER validation + API key check so malformed / mis-configured
    // requests don't burn quota. Block is OUTSIDE the fetch try/catch so the
    // decrement paths on failure are reachable (see below).
    // -----------------------------------------------------------------------
    let quota: QuotaResult;
    try {
      quota = await checkAndIncrementQuota(uid);
    } catch (err) {
      console.error("Quota check failed:", err);
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!quota.ok) {
      res.status(429).json({
        error: `${quota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${quota.limit}). Please try again ${quota.reason === "daily" ? "tomorrow" : "next month"}.`,
        quotaReason: quota.reason,
      });
      return;
    }

    // -----------------------------------------------------------------------
    // 4c. Minor-user safeguards. Under-13 is a hard block; 13–17 receives an
    // extra system block. Age is derived server-side (tamper-resistant) and
    // fails open to adult if unavailable (the client gate is primary).
    // -----------------------------------------------------------------------
    const userAge = await getUserAge(uid);
    if (userAge !== null && userAge < 13) {
      res.status(403).json({ error: "age_policy" });
      return;
    }
    const isMinor = userAge !== null && userAge < 18;

    // -----------------------------------------------------------------------
    // 5. Build request with SERVER-SIDE prompt and model config
    // -----------------------------------------------------------------------
    const systemPrompt = SYSTEM_PROMPTS[body.requestType];
    const config = MODEL_CONFIG[body.requestType];

    // For request types that need exercise-name constraint, prepend the catalog as a
    // separate cacheable block. Catalog FIRST so prompt edits don't invalidate the
    // larger catalog cache. NEVER inject per-user content into either system block —
    // user data goes in `messages`. Adding the catalog to other request types would
    // waste ~18K tokens per call for no benefit.
    const REQUEST_TYPES_WITH_CATALOG = new Set(["rehab_plan", "exercise_substitute", "wellness_plan"]);
    const systemBlocks = REQUEST_TYPES_WITH_CATALOG.has(body.requestType)
      ? [
          { type: "text", text: EXERCISE_CATALOG_CSV, cache_control: { type: "ephemeral" } },
          { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
        ]
      : [
          { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
        ];

    // Minors get an extra, cacheable safety block appended last (catalog +
    // prompt + minors = at most 3 of the 4 cache breakpoints — safe).
    if (isMinor) {
      systemBlocks.push({ type: "text", text: MINOR_SAFETY_PROMPT, cache_control: { type: "ephemeral" } });
    }

    try {
      const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anthropicApiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.model,
          max_tokens: config.max_tokens,
          ...(config.temperature !== undefined && { temperature: config.temperature }),
          system: systemBlocks,
          messages: body.messages,
        }),
      });

      const responseData = await anthropicResponse.json() as {
        usage?: {
          input_tokens?: number;
          output_tokens?: number;
          cache_creation_input_tokens?: number;
          cache_read_input_tokens?: number;
        };
      };

      if (!anthropicResponse.ok) {
        // Refund quota — user didn't get a usable response.
        await decrementQuota(uid);
        // Don't forward the raw upstream error envelope (leaks model/internal
        // details); log it server-side and return a generic error.
        logError(ctx, new Error("anthropic upstream error"),
          { stage: "anthropic_call", upstreamStatus: anthropicResponse.status });
        res.status(anthropicResponse.status).json({ error: "ai_service_error" });
        return;
      }

      // Record token usage on the context so the completion log captures it.
      if (responseData.usage) {
        ctx.metadata.tokensIn = responseData.usage.input_tokens;
        ctx.metadata.tokensOut = responseData.usage.output_tokens;
        ctx.metadata.cacheCreateTokens = responseData.usage.cache_creation_input_tokens;
        ctx.metadata.cacheReadTokens = responseData.usage.cache_read_input_tokens;
      }

      // Tier 1: validate the AI response against the per-type Zod schema before
      // passing it back. If validation fails, bump a counter and return HTTP 502
      // so the iOS client surfaces a retry state rather than crashing on bad data.
      const schemaCheck = validateClaudeResponse(body.requestType, responseData);
      if (!schemaCheck.ok) {
        logWarn(ctx, "AI response rejected by schema validation", {
          requestType: body.requestType,
          reason: schemaCheck.reason,
        });
        try {
          await admin
            .firestore()
            .collection("responseValidationFailures")
            .doc(body.requestType)
            .set({
              count: admin.firestore.FieldValue.increment(1),
              lastReason: schemaCheck.reason,
              lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        } catch (counterError) {
          // Counter is telemetry — never let its failure block the error response.
          logError(ctx, counterError, { stage: "response_validation_counter" });
        }
        // Quota already consumed (we did reach Anthropic) — do NOT refund. Treat
        // this as "we wasted a request" for quota purposes. 502 so the client
        // categorizes it as a server issue, matching existing invalidResponse(5xx)
        // handling in ClaudeAPIService.
        res.status(502).json({
          error: "ai_response_invalid",
          reason: schemaCheck.reason,
        });
        return;
      }

      res.status(200).json(responseData);
    } catch (error) {
      // Fetch threw (network error, timeout, etc.) — refund quota.
      await decrementQuota(uid);
      logError(ctx, error, { stage: "anthropic_call" });
      res.status(502).json({ error: "Failed to reach AI service" });
    }
  });

// ---------------------------------------------------------------------------
// Cross-Model Verification: GPT-4o-mini fact-checker for unverified exercises
// ---------------------------------------------------------------------------
interface CrossVerifyRequestBody {
  exercises: { name: string; condition: string }[];
  patientContext: string;
}

export const crossVerify = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB", secrets: ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"] })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("crossVerify");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1. Authenticate
    // -----------------------------------------------------------------------
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // -----------------------------------------------------------------------
    // 2. Rate limit (shares the same limiter as claudeProxy)
    // -----------------------------------------------------------------------
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Shared counter.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // -----------------------------------------------------------------------
    // 3. Validate request
    // -----------------------------------------------------------------------
    const body = req.body as CrossVerifyRequestBody;

    if (!body.exercises || !Array.isArray(body.exercises) || body.exercises.length === 0) {
      res.status(400).json({ error: "Missing or empty exercises array" });
      return;
    }

    if (body.exercises.length > 20) {
      res.status(400).json({ error: "Too many exercises (max 20)" });
      return;
    }

    // Bound attacker-controlled free-text that flows into the verifier prompt:
    // caps per-call token cost and limits prompt-injection surface against the
    // cross-model safety check.
    if (typeof body.patientContext === "string" && body.patientContext.length > 4000) {
      res.status(400).json({ error: "patientContext too long" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get OpenAI API key
    // -----------------------------------------------------------------------
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      logError(ctx, new Error("OPENAI_API_KEY not configured in environment"));
      res.status(500).json({ error: "Server configuration error" });
      return;
    }

    ctx.metadata.exerciseCount = body.exercises.length;

    // -----------------------------------------------------------------------
    // 4b. Per-user daily/monthly quota (shared cost cap across AI endpoints).
    // Placed AFTER validation + API key check so malformed / mis-configured
    // requests don't burn quota. Block is OUTSIDE the fetch try/catch so the
    // decrement paths on failure are reachable.
    // -----------------------------------------------------------------------
    let quota: QuotaResult;
    try {
      quota = await checkAndIncrementQuota(uid);
    } catch (err) {
      console.error("Quota check failed:", err);
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!quota.ok) {
      res.status(429).json({
        error: `${quota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${quota.limit}).`,
        quotaReason: quota.reason,
      });
      return;
    }

    // -----------------------------------------------------------------------
    // 5. Call GPT-4o-mini for each exercise (batched in one prompt)
    // -----------------------------------------------------------------------
    try {
      const clamp = (s: unknown) => String(s ?? "").slice(0, 200);
      const exerciseList = body.exercises
        .map((e, i) => `${i + 1}. Exercise: "${clamp(e.name)}" — Condition: "${clamp(e.condition)}"`)
        .join("\n");

      const userPrompt = `Evaluate whether each of the following exercises is appropriate for the given musculoskeletal condition.
Health context: ${body.patientContext || "Not provided"}

Exercises to evaluate:
${exerciseList}

For EACH exercise, respond with a JSON object in this exact format:
{
  "results": [
    {
      "safe": true/false,
      "confidence": 0.0-1.0,
      "reasoning": "brief explanation (1-2 sentences)",
      "concerns": ["list any specific concerns, empty array if none"]
    }
  ]
}

Return results in the same order as the exercises listed above.`;

      const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0.2,
          max_tokens: 2048,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: "You are an exercise-safety fact-checker. You evaluate whether specific exercises are safe and appropriate for people with the musculoskeletal issues described. Be conservative — when in doubt, flag concerns. Respond only in JSON.",
            },
            {
              role: "user",
              content: userPrompt,
            },
          ],
        }),
      });

      if (!openaiResponse.ok) {
        const errorData = await openaiResponse.text();
        await decrementQuota(uid);
        logError(ctx, new Error(`OpenAI API returned ${openaiResponse.status}: ${errorData}`), { stage: "openai_call" });
        res.status(502).json({ error: "Failed to reach verification service" });
        return;
      }

      const openaiData = await openaiResponse.json() as {
        choices?: { message?: { content?: string } }[];
      };
      const content = openaiData.choices?.[0]?.message?.content;

      if (!content) {
        // Upstream delivered nothing useful — refund quota.
        await decrementQuota(uid);
        res.status(502).json({ error: "Empty response from verification service" });
        return;
      }

      // Parse the GPT response and forward to client
      const parsed = JSON.parse(content);
      res.status(200).json(parsed);
    } catch (error) {
      // Fetch threw or JSON.parse of response threw — refund quota.
      await decrementQuota(uid);
      logError(ctx, error, { stage: "openai_call" });
      res.status(502).json({ error: "Failed to reach verification service" });
    }
  });

// ---------------------------------------------------------------------------
// Cloud Function: deleteAccount
// Deletes ALL server-side data for the authenticated user, then the Auth user.
// Order matters: the Auth user is deleted LAST so any mid-way failure leaves
// the account able to re-authenticate and retry. Every step is idempotent.
// ---------------------------------------------------------------------------
export const deleteAccount = functions
  .runWith({ timeoutSeconds: 300, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("deleteAccount");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(authHeader.split("Bearer ")[1]);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    const db = admin.firestore();
    try {
      // Firestore data: user tree + top-level sessionLogs/concernReports +
      // rate limits (extracted + emulator-tested in account-deletion.ts).
      await deleteUserFirestoreData(db, uid);

      // Storage session-log JSON blobs.
      await admin.storage().bucket().deleteFiles({ prefix: `sessionLogs/${uid}/` });

      // Auth user — LAST. A retry after a lost success response may arrive
      //    with a still-valid token for an already-deleted user; user-not-found
      //    here means the desired end state is already reached.
      try {
        await admin.auth().deleteUser(uid);
      } catch (error) {
        if ((error as { code?: string })?.code !== "auth/user-not-found") throw error;
      }

      res.status(200).json({ ok: true });
    } catch (error) {
      logError(ctx, error, { stage: "delete_account" });
      res.status(500).json({ error: "deletion_failed" });
    }
  });

// ---------------------------------------------------------------------------
// Virtual User Auth — mint Firebase Custom Tokens for virtual test users
// Only works for UIDs prefixed with "vuser-" and requires a shared secret.
// ---------------------------------------------------------------------------
export const createVirtualUserToken = functions.https.onRequest(async (req, res) => {
  // Test-only affordance. Hard-restrict to the dev project so it can never mint
  // impersonation tokens in production. `GCLOUD_PROJECT` is set by the Functions
  // runtime on deploy (same var billing-shutoff relies on); when it is defined
  // and is not the dev project we 404. If undefined (e.g. local), we fall
  // through to the secret gate, which still protects the endpoint.
  const proj = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
  if (proj && proj !== "pt-helper-dev") {
    res.status(404).send("Not found");
    return;
  }

  // No CORS header: this endpoint is invoked server-to-server (the virtual-user
  // harness mints via the Admin SDK directly), never from a browser origin.
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const { virtualUserId, secret } = req.body || {};

  // Validate secret (constant-time, length-checked to avoid timing leaks).
  const expectedSecret = process.env.VIRTUAL_USER_SECRET;
  if (!expectedSecret) {
    console.error("VIRTUAL_USER_SECRET not configured");
    res.status(500).json({ error: "Server configuration error" });
    return;
  }

  const provided = Buffer.from(typeof secret === "string" ? secret : "");
  const expected = Buffer.from(expectedSecret);
  if (provided.length !== expected.length || !crypto.timingSafeEqual(provided, expected)) {
    res.status(403).json({ error: "Invalid secret" });
    return;
  }

  // Safety: only allow vuser- prefixed UIDs
  if (typeof virtualUserId !== "string" || !virtualUserId.startsWith("vuser-")) {
    res.status(400).json({ error: "virtualUserId must start with 'vuser-'" });
    return;
  }

  try {
    const customToken = await admin.auth().createCustomToken(virtualUserId);
    res.status(200).json({ token: customToken });
  } catch (error) {
    console.error("Error creating custom token:", error);
    res.status(500).json({ error: "Failed to create custom token" });
  }
});

// ---------------------------------------------------------------------------
// Daily analytics aggregation (runs at 01:00 UTC)
// Writes summary counts to analytics/dailyAggregates/{date}
// No health data — behavioral counts only
// ---------------------------------------------------------------------------
export const aggregateDailyMetrics = onSchedule("every day 01:00", async () => {
  const db = admin.firestore();
  const today = new Date().toISOString().split("T")[0]; // YYYY-MM-DD

  try {
    // Count users with profiles (path: users/{uid}/profile/health)
    // "profile" is the subcollection, "health" is the document ID
    const usersSnap = await db.collectionGroup("profile").count().get();
    const totalUsers = usersSnap.data().count;

    // Count total rehab plans
    const plansSnap = await db.collectionGroup("rehabPlans").count().get();
    const totalPlans = plansSnap.data().count;

    // Count total workout sessions
    const sessionsSnap = await db.collectionGroup("workoutSessions").count().get();
    const totalWorkoutSessions = sessionsSnap.data().count;

    // Count active plans (modified in last 14 days)
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
    const activePlansSnap = await db.collectionGroup("rehabPlans")
      .where("lastModifiedDate", ">=", admin.firestore.Timestamp.fromDate(twoWeeksAgo))
      .count()
      .get();
    const activePlansCount = activePlansSnap.data().count;

    await db.collection("analytics").doc("dailyAggregates").collection("days").doc(today).set({
      date: today,
      totalUsers,
      totalPlans,
      totalWorkoutSessions,
      activePlansCount,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Daily metrics aggregated for ${today}: ${totalUsers} users, ${totalPlans} plans, ${totalWorkoutSessions} sessions`);
  } catch (error) {
    console.error("Error aggregating daily metrics:", error);
  }
});

// ---------------------------------------------------------------------------
// Nightly Email Report — AI-written summary of app health
// Runs at 07:00 local time, collects metrics, calls Claude for summary,
// sends via SendGrid.
// ---------------------------------------------------------------------------
async function collectMetrics(): Promise<string> {
  const db = admin.firestore();
  const today = new Date().toISOString().split("T")[0];
  const yesterday = new Date(Date.now() - 86_400_000).toISOString().split("T")[0];

  const lines: string[] = [`Report date: ${today}`, ""];

  // --- Firestore daily aggregates (from aggregateDailyMetrics) ---
  try {
    const todayDoc = await db
      .collection("analytics").doc("dailyAggregates").collection("days").doc(today)
      .get();
    const yesterdayDoc = await db
      .collection("analytics").doc("dailyAggregates").collection("days").doc(yesterday)
      .get();

    if (todayDoc.exists) {
      const d = todayDoc.data()!;
      lines.push("## Firestore Aggregates (today)");
      lines.push(`- Total users: ${d.totalUsers}`);
      lines.push(`- Total rehab plans: ${d.totalPlans}`);
      lines.push(`- Total workout sessions: ${d.totalWorkoutSessions}`);
      lines.push(`- Active plans (last 14d): ${d.activePlansCount}`);
    } else {
      lines.push("## Firestore Aggregates (today): no data yet");
    }

    if (yesterdayDoc.exists) {
      const d = yesterdayDoc.data()!;
      lines.push("\n## Firestore Aggregates (yesterday)");
      lines.push(`- Total users: ${d.totalUsers}`);
      lines.push(`- Total rehab plans: ${d.totalPlans}`);
      lines.push(`- Total workout sessions: ${d.totalWorkoutSessions}`);
      lines.push(`- Active plans (last 14d): ${d.activePlansCount}`);
    }
  } catch (err) {
    lines.push(`Firestore aggregate error: ${err}`);
  }

  // --- Crash logs (last 24h) ---
  const oneDayAgo = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 86_400_000));

  try {
    const crashSnap = await db
      .collectionGroup("crashLogs")
      .where("timestamp", ">=", oneDayAgo)
      .count()
      .get();
    lines.push(`\n## Crash Logs (last 24h): ${crashSnap.data().count}`);
  } catch (err) {
    lines.push(`\nCrash log query error: ${err}`);
  }

  // --- Session logs (last 24h) ---
  try {
    const sessionLogSnap = await db
      .collectionGroup("sessionLogs")
      .where("uploadedAt", ">=", oneDayAgo)
      .count()
      .get();
    lines.push(`## Session Logs uploaded (last 24h): ${sessionLogSnap.data().count}`);
  } catch (err) {
    lines.push(`Session log query error: ${err}`);
  }

  // --- Missing exercise images reported ---
  try {
    const missingSnap = await db.collection("missingExerciseImages").count().get();
    lines.push(`\n## Missing Exercise Images reported: ${missingSnap.data().count}`);
  } catch (err) {
    lines.push(`Missing images query error: ${err}`);
  }

  return lines.join("\n");
}

function markdownToHtml(md: string): string {
  // Simple markdown → HTML for email
  return md
    .replace(/^## (.+)$/gm, "<h2 style=\"color:#6B7F6B;margin:16px 0 8px;font-size:18px;\">$1</h2>")
    .replace(/^- (.+)$/gm, "<li style=\"margin:4px 0;\">$1</li>")
    .replace(/(<li[^>]*>.*<\/li>\n?)+/g, (match) => `<ul style="padding-left:20px;">${match}</ul>`)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\n\n/g, "<br><br>")
    .replace(/\n/g, "<br>");
}

/**
 * The nightly-report recipient MUST be configured explicitly. Returns null when
 * `REPORT_RECIPIENT_EMAIL` is unset/blank so the caller skips sending — there is
 * NO personal-email fallback (P3-03): operational data must never fail open to an
 * individual mailbox that can silently survive into another environment. Use an
 * organization-controlled distribution address.
 */
export function resolveReportRecipient(env: NodeJS.ProcessEnv = process.env): string | null {
  const recipient = env.REPORT_RECIPIENT_EMAIL?.trim();
  return recipient ? recipient : null;
}

export const sendNightlyReport = onSchedule(
  {
    schedule: "every day 07:00",
    timeZone: "Asia/Jerusalem",
    secrets: ["ANTHROPIC_API_KEY", "SENDGRID_API_KEY"],
  },
  async () => {
    // --- 1. Collect metrics ---
    const metricsText = await collectMetrics();
    console.log("Collected metrics:\n", metricsText);

    // --- 2. Call Claude for human-readable summary ---
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      console.error("ANTHROPIC_API_KEY not configured");
      return;
    }

    const systemPrompt = SYSTEM_PROMPTS.nightly_report;
    const config = MODEL_CONFIG.nightly_report;

    let summary: string;
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anthropicApiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.model,
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          system: systemPrompt,
          messages: [{ role: "user", content: metricsText }],
        }),
      });

      const data = await response.json() as {
        content?: { type: string; text: string }[];
      };
      summary = data.content?.[0]?.text || "Failed to generate summary";
    } catch (err) {
      console.error("Claude API error:", err);
      summary = `Error generating AI summary. Raw metrics:\n\n${metricsText}`;
    }

    // --- 2.5 Tier 3 PR B: structural validation ---
    // Catch malformed Claude output (truncated tables, empty code fences,
    // dangling headings) before it ships to the inbox. On failure we send a
    // degraded email instead so the recipient knows something went wrong but
    // the cron job still completes (vs silently failing or sending garbage).
    const reportValidation = validateNightlyReport(summary);
    if (!reportValidation.ok) {
      console.warn("Nightly report failed structural validation:", reportValidation.reasons);
      // Bump the failure counter — fire-and-forget; counter problems must
      // never block the email path.
      try {
        await admin
          .firestore()
          .collection("reportValidationFailures")
          .doc("nightly_report")
          .set(
            {
              count: admin.firestore.FieldValue.increment(1),
              lastReasons: reportValidation.reasons,
              lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true },
          );
      } catch (counterError) {
        console.error("Failed to bump reportValidationFailures counter:", counterError);
      }
      // Replace the summary with a degraded message that still includes the
      // raw metrics so the recipient has SOMETHING actionable.
      summary = [
        "## Report generation issue",
        "",
        "Claude's nightly report failed structural validation. Reasons:",
        "",
        ...reportValidation.reasons.map((r) => `- ${r}`),
        "",
        "Raw metrics from collectMetrics() are below. The AI summary is omitted to avoid sending a malformed email.",
        "",
        "```",
        metricsText,
        "```",
      ].join("\n");
    }

    // --- 3. Send email via SendGrid ---
    const sendgridKey = process.env.SENDGRID_API_KEY;
    const recipientEmail = resolveReportRecipient();

    // No personal-email fallback (P3-03): skip the send when no org recipient is set.
    if (!recipientEmail) {
      console.warn("sendNightlyReport: REPORT_RECIPIENT_EMAIL not configured — skipping send");
      return;
    }

    if (!sendgridKey) {
      console.error("SENDGRID_API_KEY not configured — logging report to console instead");
      console.log("=== NIGHTLY REPORT ===\n", summary);
      return;
    }

    sgMail.setApiKey(sendgridKey);

    const htmlBody = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#3D3D3D;background:#F5F2EC;">
  <div style="background:#FFFFFF;border-radius:12px;padding:24px;box-shadow:0 1px 3px rgba(0,0,0,0.1);">
    <h1 style="color:#6B7F6B;font-size:22px;margin:0 0 4px;">PT Helper Daily Report</h1>
    <p style="color:#9B8F80;font-size:14px;margin:0 0 20px;">${new Date().toISOString().split("T")[0]}</p>
    <hr style="border:none;border-top:1px solid #E8E3DA;margin:16px 0;">
    ${markdownToHtml(summary)}
    <hr style="border:none;border-top:1px solid #E8E3DA;margin:16px 0;">
    <p style="color:#9B8F80;font-size:12px;text-align:center;margin:0;">
      Generated by PT Helper Nightly Report &bull; Powered by Claude AI
    </p>
  </div>
</body>
</html>`;

    const reportDate = new Date().toISOString().split("T")[0];

    try {
      await sgMail.send({
        to: recipientEmail,
        from: { email: "noyfisher2003@gmail.com", name: "PT Helper Reports" },
        subject: `PT Helper Daily Report — ${reportDate}`,
        html: htmlBody,
      });
      console.log(`Nightly report sent to ${recipientEmail}`);
    } catch (err) {
      console.error("SendGrid error:", err);
    }
  }
);

// ---------------------------------------------------------------------------
// Agent-Powered Recovery Insights
// Uses Claude Managed Agents for multi-step analysis.
// Falls back to single-call claudeProxy path on failure.
// ---------------------------------------------------------------------------
export const agentInsights = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
    secrets: ["ANTHROPIC_API_KEY", "MANAGED_AGENT_ID", "MANAGED_ENVIRONMENT_ID"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("agentInsights");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // 2. Rate limit
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Shared counter.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // 3. Fetch user data from Firestore
    let data;
    try {
      data = await fetchRecoveryInsightsData(uid);
    } catch (err) {
      logError(ctx, err, { stage: "fetch_recovery_data" });
      res.status(500).json({ error: "Failed to fetch recovery data" });
      return;
    }

    ctx.metadata.sessionCount = data.sessionCount;

    if (data.sessionCount < MINIMUM_SESSION_COUNT) {
      res.status(400).json({
        error: `Need at least ${MINIMUM_SESSION_COUNT} sessions in the past 14 days`,
      });
      return;
    }

    // 4. Try managed agent
    let resultJson: string;
    try {
      const result = await runRecoveryInsightsAgent(data.userMessage);

      // Server-side validation before returning
      if (!validateInsightResult(result)) {
        throw new Error("Agent returned invalid insight structure");
      }

      resultJson = JSON.stringify(result);
      ctx.metadata.path = "agent";
    } catch (agentErr) {
      // 5. Fallback to single-call Messages API with Haiku
      logWarn(ctx, "agent_fallback", { stage: "managed_agent", fallbackReason: agentErr instanceof Error ? agentErr.message : String(agentErr) });
      ctx.metadata.path = "fallback";

      const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
      if (!anthropicApiKey) {
        res.status(500).json({ error: "Server configuration error" });
        return;
      }

      try {
        const systemPrompt = SYSTEM_PROMPTS.recovery_insights;
        const config = MODEL_CONFIG.recovery_insights;

        const fallbackResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "x-api-key": anthropicApiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            model: config.model,
            max_tokens: config.max_tokens,
            temperature: config.temperature,
            system: [
              { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
            ],
            messages: [{ role: "user", content: data.userMessage }],
          }),
        });

        const fallbackData = await fallbackResponse.json();

        if (!fallbackResponse.ok) {
          // Don't forward the raw upstream error envelope to the client.
          logError(ctx, new Error("recovery fallback upstream error"),
            { stage: "fallback_call", upstreamStatus: fallbackResponse.status });
          res.status(502).json({ error: "ai_service_error" });
          return;
        }

        // Validate the fallback payload before returning. recovery_insights has
        // no zod schema in validateClaudeResponse (it's validated by
        // validateInsightResult), so parse the model JSON and check it here.
        try {
          const text = fallbackData?.content?.[0]?.text;
          const parsed = JSON.parse(typeof text === "string" ? text : "");
          if (!validateInsightResult(parsed)) {
            logError(ctx, new Error("fallback insight failed validation"),
              { stage: "fallback_validation" });
            res.status(502).json({ error: "Failed to generate recovery insights" });
            return;
          }
        } catch (parseErr) {
          logError(ctx, parseErr, { stage: "fallback_validation" });
          res.status(502).json({ error: "Failed to generate recovery insights" });
          return;
        }

        // Validated — return in Anthropic format for iOS compatibility.
        res.status(200).json(fallbackData);
        return;
      } catch (fallbackErr) {
        logError(ctx, fallbackErr, { stage: "fallback_call" });
        res.status(502).json({ error: "Failed to generate recovery insights" });
        return;
      }
    }

    // 6. Wrap agent result in Anthropic response format for iOS compatibility
    res.status(200).json({
      content: [{ type: "text", text: resultJson }],
      stop_reason: "end_turn",
    });
  });

// ---------------------------------------------------------------------------
// Agent-Powered Cross-Session Form Analysis
// Uses Claude Managed Agents (Sonnet) to compare the current session's pose
// metrics against the user's prior persisted sessions of the same exercise.
// Falls back to the single-call form_analysis Haiku path on any agent failure.
// ---------------------------------------------------------------------------
const FORM_EXERCISE_NAME_MAX_LENGTH = 200;
const FORM_USER_MESSAGE_MAX_LENGTH = 50_000;

export const agentFormAnalysis = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
    secrets: ["ANTHROPIC_API_KEY", "FORM_AGENT_ID", "MANAGED_ENVIRONMENT_ID"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("agentFormAnalysis");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // 2. Rate limit
    if (await isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // Global daily AI spend ceiling (denial-of-wallet guard). Shared counter.
    if (!(await checkGlobalDailyBudget())) {
      res.status(429).json({ error: "daily_capacity_reached" });
      return;
    }

    // 3. Validate request body — the CURRENT session's metrics travel in the
    // body (they are not in Firestore yet; iOS persists after feedback).
    const exerciseName = req.body?.exerciseName;
    const userMessage = req.body?.userMessage;
    if (typeof exerciseName !== "string" || exerciseName.length === 0 ||
        exerciseName.length > FORM_EXERCISE_NAME_MAX_LENGTH) {
      res.status(400).json({ error: "Missing or invalid exerciseName" });
      return;
    }
    if (typeof userMessage !== "string" || userMessage.length === 0 ||
        userMessage.length > FORM_USER_MESSAGE_MAX_LENGTH) {
      res.status(400).json({ error: "Missing or invalid userMessage" });
      return;
    }

    // 4. Fetch prior form sessions for this exercise
    let history;
    try {
      history = await fetchFormHistoryData(uid, exerciseName);
    } catch (err) {
      logError(ctx, err, { stage: "fetch_form_history" });
      res.status(500).json({ error: "Failed to fetch form history" });
      return;
    }

    ctx.metadata.sessionCount = history.sessionCount;

    if (history.sessionCount < MINIMUM_FORM_HISTORY_COUNT) {
      res.status(400).json({
        error: `Need at least ${MINIMUM_FORM_HISTORY_COUNT} prior sessions of this exercise`,
      });
      return;
    }

    // 5. Try managed agent with history + current session
    const combinedMessage = `${history.userMessage}\n\nCURRENT SESSION:\n${userMessage}`;
    let resultJson: string;
    try {
      const result = await runFormAnalysisAgent(combinedMessage);

      // Server-side validation before returning
      if (!validateFormResult(result)) {
        throw new Error("Agent returned invalid form analysis structure");
      }

      resultJson = JSON.stringify(result);
      ctx.metadata.path = "agent";
    } catch (agentErr) {
      // 6. Fallback to single-call Messages API with Haiku, using the
      // CURRENT-SESSION message only (the Haiku prompt is single-session;
      // its JSON shape has no cross-session fields).
      logWarn(ctx, "agent_fallback", { stage: "form_agent", fallbackReason: agentErr instanceof Error ? agentErr.message : String(agentErr) });
      ctx.metadata.path = "fallback";

      const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
      if (!anthropicApiKey) {
        res.status(500).json({ error: "Server configuration error" });
        return;
      }

      try {
        const systemPrompt = SYSTEM_PROMPTS.form_analysis;
        const config = MODEL_CONFIG.form_analysis;

        const fallbackResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "x-api-key": anthropicApiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            model: config.model,
            max_tokens: config.max_tokens,
            temperature: config.temperature,
            system: [
              { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
            ],
            messages: [{ role: "user", content: userMessage }],
          }),
        });

        const fallbackData = await fallbackResponse.json();

        if (!fallbackResponse.ok) {
          logError(ctx, new Error("form fallback upstream error"),
            { stage: "fallback_call", upstreamStatus: fallbackResponse.status });
          res.status(502).json({ error: "ai_service_error" });
          return;
        }

        // Validate fallback against the single-call schema (unlike
        // recovery_insights, form_analysis has a zod schema).
        const check = validateClaudeResponse("form_analysis", fallbackData);
        if (!check.ok) {
          logError(ctx, new Error(check.reason), { stage: "fallback_validation" });
          res.status(502).json({ error: "ai_response_invalid" });
          return;
        }

        // Return fallback response directly (already in Anthropic format)
        res.status(200).json(fallbackData);
        return;
      } catch (fallbackErr) {
        logError(ctx, fallbackErr, { stage: "fallback_call" });
        res.status(502).json({ error: "Failed to generate form analysis" });
        return;
      }
    }

    // 7. Wrap agent result in Anthropic response format for iOS compatibility
    res.status(200).json({
      content: [{ type: "text", text: resultJson }],
      stop_reason: "end_turn",
    });
  });

// ---------------------------------------------------------------------------
// On-demand exercise image generation
// ---------------------------------------------------------------------------
export const generateExerciseImage = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "512MB",
    secrets: ["BFL_API_KEY", "GEMINI_API_KEY"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("generateExerciseImage");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // 2. Handle request
    try {
      const result = await handleGenerateExerciseImage({
        body: req.body,
        uid,
      });

      ctx.metadata.resultStatus = result.status;
      ctx.metadata.matchType = result.matchType;

      const statusCode = result.status === "rate_limited" ? 429
        : result.status === "generation_failed" || result.status === "qa_failed" ? 502
        : 200;

      res.status(statusCode).json(result);
    } catch (err) {
      logError(ctx, err, { stage: "image_generation" });
      res.status(500).json({ status: "generation_failed", message: "Internal error", retryable: true });
    }
  });
