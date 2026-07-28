/**
 * Dashboard read API + admin gate (Phase 3 of the monitoring dashboard).
 *
 * `dashboardData` serves BOTH dashboard pages from Firestore ONLY — it never
 * touches BigQuery on the request path. Everything BigQuery-derived was
 * materialized ahead of time by `analytics-pull.ts` into
 * `analytics/dashboard/daily/{YYYY-MM-DD}` and `analytics/dashboard/meta/*`.
 *
 * MODULE DIRECTION (deliberate, keeps the import graph acyclic):
 *   index.ts ──► dashboard-data.ts ──► ai-usage.ts ──► ai-pricing.ts
 *   index.ts ──► analytics-pull.ts ──► dashboard-data.ts
 * so the Firestore path constants + `requireAdmin` live HERE and the writer
 * (analytics-pull) imports them, never the other way around.
 *
 * DEGRADATION: every independent read is wrapped on its own. A failing read
 * nulls out its own field/section; it never 500s the whole response. The
 * frontend renders "—" for nulls.
 *
 * AUTH: Bearer Firebase ID token → verified → email must be verified AND
 * present in the `ADMIN_EMAILS` allowlist (comma-separated, from the
 * gitignored functions/.env, same pattern as REPORT_RECIPIENT_EMAIL).
 * Nothing here is client-readable via rules — Firestore is default-deny for
 * these paths and every read below goes through the Admin SDK.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import {
  RequestContext,
  newRequestContext,
  logCompleted,
  logError,
  logWarn,
} from "./logger";
import {
  utcDayKey,
  AI_USAGE_DAILY_COLLECTION,
  AI_DAILY_BUDGET,
  AI_BUDGET_COLLECTION,
  AI_BUDGET_DOC_ID,
} from "./ai-usage";

// ---------------------------------------------------------------------------
// Firestore layout (written by analytics-pull.ts, read here)
// ---------------------------------------------------------------------------

export const ANALYTICS_ROOT_COLLECTION = "analytics";
export const DASHBOARD_DOC_ID = "dashboard";
export const DAILY_SUBCOLLECTION = "daily";
export const META_SUBCOLLECTION = "meta";

/** `analytics/dashboard/daily` — one doc per GA4 day, id = YYYY-MM-DD. */
export function dashboardDailyCollection(
  db: admin.firestore.Firestore,
): admin.firestore.CollectionReference {
  return db
    .collection(ANALYTICS_ROOT_COLLECTION)
    .doc(DASHBOARD_DOC_ID)
    .collection(DAILY_SUBCOLLECTION);
}

/** `analytics/dashboard/meta` — rolling-window rollups, overwritten daily. */
export function dashboardMetaCollection(
  db: admin.firestore.Firestore,
): admin.firestore.CollectionReference {
  return db
    .collection(ANALYTICS_ROOT_COLLECTION)
    .doc(DASHBOARD_DOC_ID)
    .collection(META_SUBCOLLECTION);
}

export const META_SCREEN_FLOW = "screenFlow";
export const META_FUNNEL_SUMMARY = "funnelSummary";
export const META_RETENTION = "retention";

export const REPORTS_SUBCOLLECTION = "reports";

/**
 * `analytics/dashboard/reports` — one doc per nightly report, id = YYYY-MM-DD.
 *
 * Written by `sendNightlyReport` (index.ts) BEFORE it attempts the email, so
 * the report survives a dead SendGrid account; read back here for the
 * overview page's "Nightly report" card. Admin SDK only — `analytics/**` has
 * no Firestore rule, so it is default-deny to every client.
 */
export function dashboardReportsCollection(
  db: admin.firestore.Firestore,
): admin.firestore.CollectionReference {
  return db
    .collection(ANALYTICS_ROOT_COLLECTION)
    .doc(DASHBOARD_DOC_ID)
    .collection(REPORTS_SUBCOLLECTION);
}

/**
 * Delivery outcome recorded on a nightly-report doc.
 *
 * "skipped" covers both "no recipient configured" and "no SendGrid key" — and
 * is also the value written on the pre-send persist, since at that moment
 * nothing has been sent yet. The post-send merge write flips it to
 * "sent"/"failed".
 */
export const NIGHTLY_REPORT_EMAIL_STATUSES = ["sent", "failed", "skipped"] as const;
export type NightlyReportEmailStatus = (typeof NIGHTLY_REPORT_EMAIL_STATUSES)[number];

/** `analytics/dailyAggregates/days` — written by aggregateDailyMetrics. */
function dailyAggregatesCollection(
  db: admin.firestore.Firestore,
): admin.firestore.CollectionReference {
  return db
    .collection(ANALYTICS_ROOT_COLLECTION)
    .doc("dailyAggregates")
    .collection("days");
}

/** How many days of sparkline history the overview page carries. */
export const TREND_DAYS = 14;

// ---------------------------------------------------------------------------
// Admin gate
// ---------------------------------------------------------------------------

/**
 * Parse the `ADMIN_EMAILS` env var into a lookup set.
 *
 * Comma-separated, whitespace-trimmed, lower-cased. Empty/undefined input and
 * empty entries ("a,,b", ", ,") yield no members — an empty set means NOBODY
 * is an admin, which is the correct fail-closed default for an unconfigured
 * deployment.
 */
export function parseAdminEmails(raw: string | undefined): Set<string> {
  const allowed = new Set<string>();
  if (typeof raw !== "string") return allowed;
  for (const part of raw.split(",")) {
    const email = part.trim().toLowerCase();
    if (email.length > 0) allowed.add(email);
  }
  return allowed;
}

/**
 * Verify the caller is an allowlisted admin.
 *
 * Mirrors claudeProxy's Bearer/verifyIdToken pattern (index.ts) and adds two
 * requirements: the token's email must be VERIFIED (an unverified email is
 * attacker-controllable at sign-up on some providers) and must appear in
 * ADMIN_EMAILS.
 *
 * Returns the lower-cased admin email on success. On failure it has ALREADY
 * written the error response and returns null — callers must `return`
 * immediately without touching `res`.
 */
export async function requireAdmin(
  req: functions.Request,
  res: functions.Response,
): Promise<string | null> {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "unauthorized" });
    return null;
  }

  const idToken = authHeader.split("Bearer ")[1];
  let decoded: admin.auth.DecodedIdToken;
  try {
    decoded = await admin.auth().verifyIdToken(idToken);
  } catch {
    res.status(401).json({ error: "unauthorized" });
    return null;
  }

  const allowed = parseAdminEmails(process.env.ADMIN_EMAILS);
  const email = typeof decoded.email === "string" ? decoded.email.toLowerCase() : "";
  if (decoded.email_verified !== true || email.length === 0 || !allowed.has(email)) {
    res.status(403).json({ error: "not_admin" });
    return null;
  }

  return email;
}

// ---------------------------------------------------------------------------
// Pure shaping helpers (unit-tested; no Firestore, no clock of their own)
// ---------------------------------------------------------------------------

/** Allowed graph windows. Anything else falls back to 30 days. */
export const ALLOWED_WINDOW_DAYS = [7, 30, 90] as const;

export function parseDaysParam(raw: unknown): number {
  const value = Array.isArray(raw) ? raw[0] : raw;
  const parsed = typeof value === "number" ? value : parseInt(String(value ?? ""), 10);
  return (ALLOWED_WINDOW_DAYS as readonly number[]).includes(parsed) ? parsed : 30;
}

/** Finite number, or `fallback`. Firestore can hand back anything. */
function num(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function round(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/**
 * AI calls used today, honouring the counter's LAZY reset.
 *
 * `config/aiDailyBudget` is only rolled over when the NEXT AI call's
 * transaction observes `data.date !== today` (checkGlobalDailyBudget in
 * index.ts). A naive read on a quiet morning therefore returns yesterday's
 * leftover count. Same date check here → report 0.
 */
export function resolveAiCallsToday(
  data: Record<string, unknown> | undefined,
  todayKey: string,
): number {
  if (!data || data.date !== todayKey) return 0;
  return num(data.count);
}

export interface AiDailyPoint {
  date: string;
  calls: number;
  errors: number;
  errorRatePct: number;
  tokensIn: number;
  tokensOut: number;
  totalCostUSD: number;
  avgLatencyMs: number;
  byTypeCostUSD: Record<string, number>;
}

/**
 * Shape one `aiUsageDaily/{YYYY-MM-DD}` doc for the API.
 *
 * The stored doc carries totals only (`totalDurationMs`, nested `byType`); the
 * per-call averages the charts want are derived here so the rollup stays a
 * pure sum of increments.
 */
export function shapeAiUsageDaily(
  date: string,
  data: Record<string, unknown> | undefined,
): AiDailyPoint {
  const calls = num(data?.calls);
  const errors = num(data?.errors);
  const totalDurationMs = num(data?.totalDurationMs);

  const byTypeCostUSD: Record<string, number> = {};
  const byType = data?.byType;
  if (byType && typeof byType === "object") {
    for (const [key, value] of Object.entries(byType as Record<string, unknown>)) {
      const entry = value as Record<string, unknown> | undefined;
      byTypeCostUSD[key] = round(num(entry?.costUSD), 6);
    }
  }

  return {
    date,
    calls,
    errors,
    errorRatePct: calls > 0 ? round((errors / calls) * 100, 1) : 0,
    tokensIn: num(data?.tokensIn),
    tokensOut: num(data?.tokensOut),
    totalCostUSD: round(num(data?.totalCostUSD), 6),
    avgLatencyMs: calls > 0 ? Math.round(totalDurationMs / calls) : 0,
    byTypeCostUSD,
  };
}

export interface TrendPoint {
  date: string;
  dau: number | null;
  sessions: number | null;
  workoutsStarted: number | null;
  workoutsCompleted: number | null;
  plansGenerated: number | null;
  aiCalls: number;
  aiCostUSD: number;
}

/**
 * One sparkline point. GA4 numbers are null (not 0) when that day's BigQuery
 * doc hasn't landed yet — a missing day and a genuinely empty day must not
 * look the same on a chart. AI numbers come from a different pipeline that
 * writes same-day, so absence there really is zero.
 */
export function buildTrendPoint(
  date: string,
  daily: Record<string, unknown> | undefined,
  ai: Record<string, unknown> | undefined,
): TrendPoint {
  const engagement = (daily?.engagement ?? undefined) as Record<string, unknown> | undefined;
  const funnel = (daily?.funnel ?? undefined) as Record<string, unknown> | undefined;
  const aiPoint = shapeAiUsageDaily(date, ai);

  return {
    date,
    dau: engagement ? num(engagement.dau) : null,
    sessions: engagement ? num(engagement.totalSessions) : null,
    workoutsStarted: engagement ? num(engagement.workoutsStarted) : null,
    workoutsCompleted: engagement ? num(engagement.workoutsCompleted) : null,
    plansGenerated: funnel ? num(funnel.rehabPlanGenerated) : null,
    aiCalls: aiPoint.calls,
    aiCostUSD: aiPoint.totalCostUSD,
  };
}

/** The four cumulative counters aggregateDailyMetrics maintains. */
const TOTALS_FIELDS = [
  "totalUsers",
  "totalPlans",
  "totalWorkoutSessions",
  "activePlansCount",
] as const;

/**
 * Day-over-N-days deltas between two `dailyAggregates` docs. Null when there
 * is no comparison doc (fresh project, or the older doc was never written) —
 * a missing baseline must not render as "+0".
 */
export function computeTotalsDeltas(
  latest: Record<string, unknown> | undefined,
  prior: Record<string, unknown> | undefined,
): Record<string, number> | null {
  if (!latest || !prior) return null;
  const deltas: Record<string, number> = {};
  for (const field of TOTALS_FIELDS) {
    deltas[field] = num(latest[field]) - num(prior[field]);
  }
  return deltas;
}

/** UTC day key N days before `dayKey`. Pure string→string date math. */
export function shiftDayKey(dayKey: string, deltaDays: number): string {
  const parsed = Date.parse(`${dayKey}T00:00:00.000Z`);
  if (!Number.isFinite(parsed)) return dayKey;
  return new Date(parsed + deltaDays * 86_400_000).toISOString().slice(0, 10);
}

/**
 * Firestore Timestamps don't JSON-serialize usefully (`{_seconds, _nanoseconds}`).
 * Convert them to ISO strings recursively so meta docs can be forwarded
 * verbatim without leaking the SDK's wire shape into the frontend.
 */
export function toJsonSafe(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (value instanceof admin.firestore.Timestamp) return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map(toJsonSafe);
  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      out[key] = toJsonSafe(entry);
    }
    return out;
  }
  return value;
}

export interface NightlyReportSummary {
  date: string;
  generatedAt: string | null;
  summaryHtml: string;
  validationPassed: boolean;
  emailStatus: NightlyReportEmailStatus | null;
}

/**
 * Shape one `analytics/dashboard/reports/{YYYY-MM-DD}` doc for the API.
 *
 * Deliberately DROPS `summaryMarkdown` and `metricsText`: both are kept in
 * Firestore for debugging, and shipping all three copies would triple a
 * payload the overview page polls every 60s. Only the HTML is rendered.
 *
 * `validationPassed` defaults to false on a malformed doc — a report whose
 * flag we can't read must not claim it passed. `emailStatus` is narrowed to
 * the known union so the frontend's chip can switch on it safely.
 */
export function shapeNightlyReport(
  date: string,
  data: Record<string, unknown> | undefined,
): NightlyReportSummary | null {
  if (!data) return null;
  const generatedAt = toJsonSafe(data.generatedAt ?? null);
  const status = data.emailStatus;
  return {
    date: typeof data.date === "string" ? data.date : date,
    generatedAt: typeof generatedAt === "string" ? generatedAt : null,
    summaryHtml: typeof data.summaryHtml === "string" ? data.summaryHtml : "",
    validationPassed: data.validationPassed === true,
    emailStatus: (NIGHTLY_REPORT_EMAIL_STATUSES as readonly unknown[]).includes(status)
      ? (status as NightlyReportEmailStatus)
      : null,
  };
}

// ---------------------------------------------------------------------------
// Read helpers
// ---------------------------------------------------------------------------

/**
 * Run one independent read. On failure: warn (never throw) and yield null so
 * the caller's section degrades on its own.
 */
async function safeRead<T>(
  ctx: RequestContext,
  section: string,
  read: () => Promise<T>,
): Promise<T | null> {
  try {
    return await read();
  } catch (err) {
    logWarn(ctx, "dashboard_read_failed", {
      section,
      errorMessage: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}

/**
 * Most recent N docs of a date-keyed collection, returned oldest→newest.
 *
 * Deliberately queries ASCENDING over a __name__ range and slices the tail:
 * a bare `orderBy(documentId(), "desc")` is NOT served by Firestore's
 * automatic indexes (FAILED_PRECONDITION in production), while an ascending
 * range is. Doc ids are YYYY-MM-DD, so lexicographic == chronological. The
 * lookback window is padded (min 7 days) so gaps from missed runs don't
 * shrink the result below `limit` unnecessarily.
 */
async function readRecentDateKeyedDocs(
  collection: admin.firestore.CollectionReference,
  limit: number,
): Promise<Map<string, Record<string, unknown>>> {
  const lookbackDays = Math.max(limit + 2, 7);
  const sinceKey = new Date(Date.now() - lookbackDays * 86_400_000).toISOString().slice(0, 10);
  const snap = await collection
    .orderBy(admin.firestore.FieldPath.documentId())
    .startAt(sinceKey)
    .get();
  const out = new Map<string, Record<string, unknown>>();
  for (const doc of snap.docs.slice(-limit)) {
    out.set(doc.id, doc.data() as Record<string, unknown>);
  }
  return out;
}

function dailyDocToApi(date: string, data: Record<string, unknown>): Record<string, unknown> {
  return {
    date,
    engagement: toJsonSafe(data.engagement ?? null),
    funnel: toJsonSafe(data.funnel ?? null),
    workout: toJsonSafe(data.workout ?? null),
  };
}

// ---------------------------------------------------------------------------
// Overview page
// ---------------------------------------------------------------------------

async function buildOverviewPayload(
  db: admin.firestore.Firestore,
  ctx: RequestContext,
  now: Date,
): Promise<Record<string, unknown>> {
  const todayKey = utcDayKey(now);
  const yesterdayKey = shiftDayKey(todayKey, -1);
  const since24h = admin.firestore.Timestamp.fromDate(new Date(now.getTime() - 86_400_000));

  const [
    aiCallsToday,
    aiToday,
    sessionsUploaded24h,
    crashes24h,
    validationFailures,
    missingExerciseImages,
    totals,
    yesterday,
    trend,
    nightlyReport,
  ] = await Promise.all([
    // Live AI budget counter — lazily reset, see resolveAiCallsToday.
    safeRead(ctx, "aiDailyBudget", async () => {
      const snap = await db.collection(AI_BUDGET_COLLECTION).doc(AI_BUDGET_DOC_ID).get();
      return resolveAiCallsToday(snap.data() as Record<string, unknown> | undefined, todayKey);
    }),

    safeRead(ctx, "aiUsageToday", async () => {
      const snap = await db.collection(AI_USAGE_DAILY_COLLECTION).doc(todayKey).get();
      return shapeAiUsageDaily(todayKey, snap.data() as Record<string, unknown> | undefined);
    }),

    safeRead(ctx, "sessionsUploaded24h", async () => {
      const snap = await db
        .collectionGroup("sessionLogs")
        .where("uploadedAt", ">=", since24h)
        .count()
        .get();
      return snap.data().count;
    }),

    // Needs the COLLECTION_GROUP composite index (crashMarker, uploadedAt).
    safeRead(ctx, "crashes24h", async () => {
      const snap = await db
        .collectionGroup("sessionLogs")
        .where("crashMarker", "==", true)
        .where("uploadedAt", ">=", since24h)
        .count()
        .get();
      return snap.data().count;
    }),

    // One doc per requestType — bounded by the request-type enum, so a full
    // read is cheap and gives the per-type breakdown a count() can't.
    safeRead(ctx, "responseValidationFailures", async () => {
      const snap = await db.collection("responseValidationFailures").get();
      const byType: Record<string, number> = {};
      for (const doc of snap.docs) byType[doc.id] = num(doc.get("count"));
      return byType;
    }),

    safeRead(ctx, "missingExerciseImages", async () => {
      const snap = await db.collection("missingExerciseImages").count().get();
      return snap.data().count;
    }),

    safeRead(ctx, "totals", async () => {
      // Same ascending-range trick as readRecentDateKeyedDocs — descending
      // documentId() orderBy would demand a manual index.
      const recent = await readRecentDateKeyedDocs(dailyAggregatesCollection(db), 1);
      const latestId = [...recent.keys()].pop();
      if (!latestId) return null;
      const latestDoc = { id: latestId };
      const latest = recent.get(latestId) as Record<string, unknown>;

      const priorKey = shiftDayKey(latestDoc.id, -7);
      const priorSnap = await dailyAggregatesCollection(db).doc(priorKey).get();
      const prior = priorSnap.exists ? (priorSnap.data() as Record<string, unknown>) : undefined;

      return {
        date: latestDoc.id,
        totalUsers: num(latest.totalUsers),
        totalPlans: num(latest.totalPlans),
        totalWorkoutSessions: num(latest.totalWorkoutSessions),
        activePlansCount: num(latest.activePlansCount),
        comparedTo: prior ? priorKey : null,
        deltas: computeTotalsDeltas(latest, prior),
      };
    }),

    safeRead(ctx, "yesterday", async () => {
      const [dailySnap, aiSnap] = await Promise.all([
        dashboardDailyCollection(db).doc(yesterdayKey).get(),
        db.collection(AI_USAGE_DAILY_COLLECTION).doc(yesterdayKey).get(),
      ]);
      if (!dailySnap.exists) return null;
      const data = dailySnap.data() as Record<string, unknown>;
      return {
        ...dailyDocToApi(yesterdayKey, data),
        source: typeof data.source === "string" ? data.source : null,
        ai: shapeAiUsageDaily(
          yesterdayKey,
          aiSnap.data() as Record<string, unknown> | undefined,
        ),
      };
    }),

    safeRead(ctx, "trend14d", async () => {
      const daily = await readRecentDateKeyedDocs(dashboardDailyCollection(db), TREND_DAYS);
      const ai = await readRecentDateKeyedDocs(
        db.collection(AI_USAGE_DAILY_COLLECTION),
        TREND_DAYS,
      );
      // Union of both pipelines' days: AI cost exists on days GA4 hasn't
      // delivered yet, and vice-versa after a backfill.
      const dates = Array.from(new Set([...daily.keys(), ...ai.keys()])).sort();
      return dates
        .slice(-TREND_DAYS)
        .map((date) => buildTrendPoint(date, daily.get(date), ai.get(date)));
    }),

    // Latest nightly report. Same ascending-range read as `totals` (a
    // descending documentId() orderBy needs a manual index — see
    // readRecentDateKeyedDocs). Its lookback is 7 days, so a job that has
    // been dead for over a week correctly reads as "no report".
    safeRead(ctx, "nightlyReport", async () => {
      const recent = await readRecentDateKeyedDocs(dashboardReportsCollection(db), 1);
      const latestId = [...recent.keys()].pop();
      if (!latestId) return null;
      return shapeNightlyReport(latestId, recent.get(latestId));
    }),
  ]);

  return {
    page: "overview",
    generatedAt: now.toISOString(),
    today: todayKey,
    live: {
      aiCallsToday,
      aiBudgetLimit: AI_DAILY_BUDGET,
      aiCostTodayUSD: aiToday ? aiToday.totalCostUSD : null,
      aiCallsRecordedToday: aiToday ? aiToday.calls : null,
      aiErrorsToday: aiToday ? aiToday.errors : null,
      aiErrorRateTodayPct: aiToday ? aiToday.errorRatePct : null,
      aiAvgLatencyMsToday: aiToday ? aiToday.avgLatencyMs : null,
      sessionsUploaded24h,
      crashes24h,
      validationFailures,
      missingExerciseImages,
    },
    totals,
    yesterday,
    trend14d: trend,
    nightlyReport,
  };
}

// ---------------------------------------------------------------------------
// Graphs page
// ---------------------------------------------------------------------------

async function buildGraphsPayload(
  db: admin.firestore.Firestore,
  ctx: RequestContext,
  days: number,
  now: Date,
): Promise<Record<string, unknown>> {
  const readMeta = (docId: string) =>
    safeRead(ctx, `meta:${docId}`, async () => {
      const snap = await dashboardMetaCollection(db).doc(docId).get();
      return snap.exists ? (toJsonSafe(snap.data()) as Record<string, unknown>) : null;
    });

  const [daily, aiDaily, screenFlow, funnelSummary, retention] = await Promise.all([
    safeRead(ctx, "dailyWindow", async () => {
      const docs = await readRecentDateKeyedDocs(dashboardDailyCollection(db), days);
      return Array.from(docs.entries()).map(([date, data]) => dailyDocToApi(date, data));
    }),

    safeRead(ctx, "aiDailyWindow", async () => {
      const docs = await readRecentDateKeyedDocs(
        db.collection(AI_USAGE_DAILY_COLLECTION),
        days,
      );
      return Array.from(docs.entries()).map(([date, data]) => shapeAiUsageDaily(date, data));
    }),

    readMeta(META_SCREEN_FLOW),
    readMeta(META_FUNNEL_SUMMARY),
    readMeta(META_RETENTION),
  ]);

  return {
    page: "graphs",
    generatedAt: now.toISOString(),
    windowDays: days,
    daily,
    aiDaily,
    screenFlow,
    funnelSummary,
    retention,
  };
}

// ---------------------------------------------------------------------------
// Cloud Function: dashboardData
// ---------------------------------------------------------------------------

/**
 * GET /dashboardData?page=overview
 * GET /dashboardData?page=graphs&days=7|30|90
 *
 * v1 onRequest in the default us-central1 region — required for the Firebase
 * Hosting rewrite (`/api/dashboard` → this function) that keeps the frontend
 * same-origin, so no CORS handling is needed here.
 */
export const dashboardData = functions
  .runWith({ timeoutSeconds: 60, memory: "256MB" })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("dashboardData");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "GET") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const email = await requireAdmin(req, res);
    if (!email) return;

    const pageParam = req.query.page;
    const page = typeof pageParam === "string" && pageParam.length > 0 ? pageParam : "overview";
    ctx.metadata.page = page;

    try {
      const db = admin.firestore();
      const now = new Date();

      if (page === "overview") {
        // Short private cache: the live tiles poll every 60s, so 30s of edge
        // reuse halves the read load without visibly staling the numbers.
        res.set("Cache-Control", "private, max-age=30");
        res.status(200).json(await buildOverviewPayload(db, ctx, now));
        return;
      }

      if (page === "graphs") {
        const days = parseDaysParam(req.query.days);
        res.set("Cache-Control", "private, max-age=30");
        res.status(200).json(await buildGraphsPayload(db, ctx, days, now));
        return;
      }

      res.status(400).json({ error: "unknown_page" });
    } catch (err) {
      // Section-level failures are already absorbed by safeRead; reaching here
      // means something structural broke.
      logError(ctx, err, { stage: "dashboard_payload" });
      res.status(500).json({ error: "internal" });
    }
  });
