/**
 * BigQuery → Firestore materialization (Phase 2 of the monitoring dashboard).
 *
 * GA4 exports one daily shard per day into
 * `pt-helper-dev.analytics_506142273.events_YYYYMMDD`, landing ~08:00–09:30 PT
 * the following morning. Nothing in the request path may query BigQuery (slow,
 * billed per scan, and unavailable for "today"), so a scheduled job runs the
 * SQL once and writes dashboard-ready documents:
 *
 *   analytics/dashboard/daily/{YYYY-MM-DD}  — one doc per GA4 day
 *   analytics/dashboard/meta/screenFlow     — rolling 30d, overwritten daily
 *   analytics/dashboard/meta/funnelSummary  — rolling 30d distinct-user funnel
 *   analytics/dashboard/meta/retention      — weekly cohorts
 *
 * `dashboardData` then reads only those docs (see dashboard-data.ts).
 *
 * The SQL here is INLINE and self-contained on purpose: the checked-in views
 * under `analytics/bigquery/` are console/ad-hoc tooling and may or may not be
 * deployed, so this job must never depend on them. The logic is ported from
 * them; the two intentional divergences are documented at their query.
 *
 * SQL INJECTION: BigQuery cannot parameterize table names, so shard suffixes
 * are interpolated. Every suffix passes `assertShardSuffix` (exactly 8 digits)
 * first, and the only externally-supplied date (`backfillAnalytics`'s body)
 * additionally passes `isValidDayKey`. Interpolating a value that survived
 * `/^\d{8}$/` cannot inject.
 *
 * FAILURE POSTURE: `materializeDay` and `materializeRollups` never throw —
 * they return per-unit status markers. A missing shard is `no_data` (normal
 * before GA4 lands), everything else is `error` with the message logged. One
 * failed day or rollup never aborts the rest of the run.
 */

import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { BigQuery } from "@google-cloud/bigquery";
import {
  RequestContext,
  newRequestContext,
  logCompleted,
  logError,
  logWarn,
} from "./logger";
import {
  requireAdmin,
  dashboardDailyCollection,
  dashboardMetaCollection,
  META_SCREEN_FLOW,
  META_FUNNEL_SUMMARY,
  META_RETENTION,
} from "./dashboard-data";

export const BQ_PROJECT = "pt-helper-dev";
export const BQ_DATASET = "analytics_506142273";

/** Rolling window for the screen-flow Sankey and the distinct-user funnel. */
export const ROLLUP_WINDOW_DAYS = 30;
/**
 * Retention needs a longer window than the other two rollups: 12 weekly
 * cohorts is 84 days, which 30 days of shards cannot produce.
 */
export const RETENTION_WINDOW_DAYS = 90;
/** Cohorts kept in the retention doc (most recent first). */
export const MAX_RETENTION_COHORTS = 12;
/** Edges kept in the Sankey doc, after the min-count filter. */
export const MAX_SANKEY_EDGES = 80;
/** Edges below this transition count are noise in a Sankey. */
export const MIN_SANKEY_EDGE_COUNT = 2;
/** Hard cap on edge rows pulled back from BigQuery before trimming. */
const EDGE_SCAN_LIMIT = 500;

/** Backfill bounds (`backfillAnalytics` body). */
export const BACKFILL_MIN_DAYS = 1;
export const BACKFILL_MAX_DAYS = 90;
export const BACKFILL_DEFAULT_DAYS = 7;

// ---------------------------------------------------------------------------
// Pure helpers: dates, numbers, validation
// ---------------------------------------------------------------------------

/** `YYYY-MM-DD` that is also a real calendar date. */
export function isValidDayKey(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

/** `2026-07-25` → `20260725`. Throws on anything that isn't a valid day key. */
export function shardSuffix(dayKey: string): string {
  if (!isValidDayKey(dayKey)) throw new Error(`invalid day key: ${String(dayKey)}`);
  return dayKey.replace(/-/g, "");
}

/**
 * Last line of defence before a suffix reaches a SQL string. Anything that is
 * not exactly 8 digits throws rather than being interpolated.
 */
export function assertShardSuffix(suffix: string): string {
  if (!/^\d{8}$/.test(suffix)) throw new Error(`invalid shard suffix: ${String(suffix)}`);
  return suffix;
}

/** UTC day key, `YYYY-MM-DD`. */
export function dayKeyOf(at: Date): string {
  return at.toISOString().slice(0, 10);
}

/** UTC day key `deltaDays` from `at` (negative = earlier). */
export function offsetDayKey(at: Date, deltaDays: number): string {
  return dayKeyOf(new Date(at.getTime() + deltaDays * 86_400_000));
}

/**
 * `count` day keys ending YESTERDAY, most recent first.
 * Today is excluded: GA4 has not exported a daily shard for it yet.
 */
export function recentDayKeys(count: number, now: Date): string[] {
  const days: string[] = [];
  for (let i = 1; i <= Math.max(0, Math.floor(count)); i++) {
    days.push(offsetDayKey(now, -i));
  }
  return days;
}

/**
 * Inclusive `_TABLE_SUFFIX` bounds for a window of `days` ending YESTERDAY.
 *
 * Today is excluded for the same reason as in `recentDayKeys`: GA4 has not
 * exported a shard for it. Ending on today would scan one fewer completed day
 * than the caller asked for while the meta doc still advertised the full
 * `windowDays` — a "30-day" rollup built from 29 days of data.
 */
export function windowSuffixes(days: number, now: Date): { start: string; end: string } {
  const span = Math.max(1, Math.floor(days));
  return {
    start: assertShardSuffix(shardSuffix(offsetDayKey(now, -span))),
    end: assertShardSuffix(shardSuffix(offsetDayKey(now, -1))),
  };
}

/** Backfill `days`, clamped to [1, 90]; anything unusable → 7. */
export function clampBackfillDays(raw: unknown): number {
  const parsed = typeof raw === "number" ? raw : parseInt(String(raw ?? ""), 10);
  if (!Number.isFinite(parsed)) return BACKFILL_DEFAULT_DAYS;
  const floored = Math.floor(parsed);
  if (floored < BACKFILL_MIN_DAYS) return BACKFILL_MIN_DAYS;
  if (floored > BACKFILL_MAX_DAYS) return BACKFILL_MAX_DAYS;
  return floored;
}

/**
 * BigQuery INT64/NUMERIC can arrive as a number, a string, or a wrapped
 * `{value}` object depending on magnitude and client options. Normalize.
 */
export function toNumber(value: unknown, fallback = 0): number {
  if (typeof value === "number") return Number.isFinite(value) ? value : fallback;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  if (value && typeof value === "object" && "value" in (value as Record<string, unknown>)) {
    return toNumber((value as Record<string, unknown>).value, fallback);
  }
  return fallback;
}

export function roundTo(value: number, decimals: number): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

/**
 * True only for "the shard doesn't exist" — the normal state before GA4
 * exports a day.
 *
 * Deliberately matches `Not found: Table` and NOT a bare "not found": a
 * dataset/location misconfiguration also says "Not found: Dataset", and
 * silently reporting that as `no_data` would hide a broken pipeline forever.
 */
export function isMissingShardError(err: unknown): boolean {
  const message = err instanceof Error ? err.message : String(err ?? "");
  return /not found:\s*table/i.test(message);
}

// ---------------------------------------------------------------------------
// SQL builders (pure — exported so the shapes are unit-testable)
// ---------------------------------------------------------------------------

function shardTable(suffix: string): string {
  return `\`${BQ_PROJECT}.${BQ_DATASET}.events_${assertShardSuffix(suffix)}\``;
}

function wildcardTable(): string {
  return `\`${BQ_PROJECT}.${BQ_DATASET}.events_*\``;
}

/**
 * One job, one shard, every daily metric.
 *
 * Ports v_engagement_daily.sql + v_workout_metrics.sql (including its
 * COALESCE fix: `workout_ended_early` emits completed_count/skipped_count
 * rather than exercises_completed/exercises_skipped) and the per-step distinct
 * user counts, collapsed into a single scan of the day's shard.
 *
 * Divergence from v_engagement_daily.sql: session identity uses an explicit
 * `CAST(ga_session_id AS STRING)`. CONCAT does not implicitly coerce INT64.
 */
export function buildDailyQuery(dayKey: string): string {
  const table = shardTable(shardSuffix(dayKey));
  return `
WITH ev AS (
  SELECT
    user_pseudo_id,
    event_name,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'duration_seconds') AS duration_seconds,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'exercises_completed') AS exercises_completed,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'exercises_skipped') AS exercises_skipped,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'completed_count') AS completed_count,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'skipped_count') AS skipped_count
  FROM ${table}
)
SELECT
  -- engagement
  COUNT(DISTINCT user_pseudo_id) AS dau,
  COUNT(DISTINCT CASE
    WHEN ga_session_id IS NOT NULL
    THEN CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))
  END) AS total_sessions,
  COUNTIF(event_name = 'workout_started') AS workouts_started,
  COUNTIF(event_name = 'workout_completed') AS workouts_completed,
  COUNTIF(event_name = 'workout_ended_early') AS workouts_ended_early,
  COUNTIF(event_name = 'exercise_skipped') AS exercises_skipped_count,
  COUNTIF(event_name = 'exercise_swapped') AS exercises_swapped_count,
  COUNT(DISTINCT CASE WHEN event_name = 'recovery_insights_viewed' THEN user_pseudo_id END) AS users_viewed_insights,
  COUNT(DISTINCT CASE WHEN event_name = 'achievement_earned' THEN user_pseudo_id END) AS users_earned_achievement,
  COUNT(DISTINCT CASE WHEN event_name = 'reassessment_started' THEN user_pseudo_id END) AS users_reassessed,
  COUNT(DISTINCT CASE WHEN event_name = 'pdf_exported' THEN user_pseudo_id END) AS users_exported_pdf,
  COUNT(DISTINCT CASE WHEN event_name = 'exercise_swapped' THEN user_pseudo_id END) AS users_swapped_exercise,

  -- funnel (distinct users per step)
  COUNT(DISTINCT CASE WHEN event_name = 'sign_in_completed' THEN user_pseudo_id END) AS f_sign_ins,
  COUNT(DISTINCT CASE WHEN event_name = 'onboarding_completed' THEN user_pseudo_id END) AS f_onboarding_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'onboarding_skipped' THEN user_pseudo_id END) AS f_onboarding_skipped,
  COUNT(DISTINCT CASE WHEN event_name = 'body_map_opened' THEN user_pseudo_id END) AS f_body_map_opened,
  COUNT(DISTINCT CASE WHEN event_name = 'regions_selected' THEN user_pseudo_id END) AS f_regions_selected,
  COUNT(DISTINCT CASE WHEN event_name = 'assessment_completed' THEN user_pseudo_id END) AS f_assessment_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'analysis_completed' THEN user_pseudo_id END) AS f_analysis_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'analysis_failed' THEN user_pseudo_id END) AS f_analysis_failed,
  COUNT(DISTINCT CASE WHEN event_name = 'rehab_plan_generated' THEN user_pseudo_id END) AS f_rehab_plan_generated,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_started' THEN user_pseudo_id END) AS f_workout_started,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_completed' THEN user_pseudo_id END) AS f_workout_completed,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_ended_early' THEN user_pseudo_id END) AS f_workout_ended_early,

  -- workout averages (COALESCE bridges the workout_ended_early param mismatch)
  AVG(CASE WHEN event_name = 'workout_completed' THEN duration_seconds END) AS avg_duration_seconds,
  AVG(CASE WHEN event_name = 'workout_completed' THEN COALESCE(exercises_completed, completed_count) END) AS avg_exercises_completed,
  AVG(CASE WHEN event_name IN ('workout_completed', 'workout_ended_early') THEN COALESCE(exercises_skipped, skipped_count) END) AS avg_exercises_skipped
FROM ev
`.trim();
}

/**
 * Screen-to-screen transitions over the window, plus the session denominator.
 *
 * Ports v_screen_flow_daily.sql, aggregated across the window instead of per
 * day. `total_sessions` rides along on every edge row (CROSS JOIN of a scalar)
 * so this stays ONE job; the shaper reads it off the first row.
 */
export function buildScreenFlowQuery(start: string, end: string): string {
  const startSuffix = assertShardSuffix(start);
  const endSuffix = assertShardSuffix(end);
  return `
WITH sv AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    -- The SDK exports the screen name as 'firebase_screen', NOT 'screen_name'
    -- (verified against the live dataset — 'screen_name' never appears).
    -- COALESCE keeps a fallback in case a future SDK reverts the mapping.
    COALESCE(
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'firebase_screen'),
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'screen_name')
    ) AS screen_name,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS ga_session_id
  FROM ${wildcardTable()}
  WHERE event_name = 'screen_view'
    AND _TABLE_SUFFIX BETWEEN '${startSuffix}' AND '${endSuffix}'
),

nav AS (
  SELECT
    screen_name AS source_screen,
    LEAD(screen_name) OVER (
      PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp
    ) AS target_screen
  FROM sv
  WHERE screen_name IS NOT NULL
),

edges AS (
  SELECT source_screen, target_screen, COUNT(*) AS transition_count
  FROM nav
  WHERE target_screen IS NOT NULL AND target_screen != source_screen
  GROUP BY source_screen, target_screen
  ORDER BY transition_count DESC
  LIMIT ${EDGE_SCAN_LIMIT}
),

totals AS (
  SELECT COUNT(DISTINCT CONCAT(user_pseudo_id, '-', CAST(ga_session_id AS STRING))) AS total_sessions
  FROM sv
  WHERE ga_session_id IS NOT NULL
)

SELECT e.source_screen, e.target_screen, e.transition_count, t.total_sessions
FROM edges e
CROSS JOIN totals t
ORDER BY e.transition_count DESC
`.trim();
}

/** The 10 funnel steps of v_funnel_summary.sql, in order. */
export const FUNNEL_STEPS: ReadonlyArray<{ name: string; column: string }> = [
  { name: "Sign In", column: "step_1" },
  { name: "Onboarding", column: "step_2" },
  { name: "Body Map", column: "step_3" },
  { name: "Regions Selected", column: "step_4" },
  { name: "Assessment", column: "step_5" },
  { name: "Analysis", column: "step_6" },
  { name: "Rehab Plan", column: "step_7" },
  { name: "Workout Started", column: "step_8" },
  { name: "Workout Completed", column: "step_9" },
  { name: "Form Check Done", column: "step_10" },
];

/**
 * Distinct users per funnel step over the window.
 *
 * Divergence from v_funnel_summary.sql: the view UNION ALLs ten separate
 * scans of the same wildcard table. Identical numbers come out of ONE scan
 * with ten conditional distinct counts, at a tenth of the bytes billed. The
 * conversion percentages are derived in `buildFunnelSummarySteps`.
 */
export function buildFunnelSummaryQuery(start: string, end: string): string {
  const startSuffix = assertShardSuffix(start);
  const endSuffix = assertShardSuffix(end);
  return `
SELECT
  COUNT(DISTINCT CASE WHEN event_name = 'sign_in_completed' THEN user_pseudo_id END) AS step_1,
  COUNT(DISTINCT CASE WHEN event_name IN ('onboarding_completed', 'onboarding_skipped') THEN user_pseudo_id END) AS step_2,
  COUNT(DISTINCT CASE WHEN event_name = 'body_map_opened' THEN user_pseudo_id END) AS step_3,
  COUNT(DISTINCT CASE WHEN event_name = 'regions_selected' THEN user_pseudo_id END) AS step_4,
  COUNT(DISTINCT CASE WHEN event_name = 'assessment_completed' THEN user_pseudo_id END) AS step_5,
  COUNT(DISTINCT CASE WHEN event_name = 'analysis_completed' THEN user_pseudo_id END) AS step_6,
  COUNT(DISTINCT CASE WHEN event_name = 'rehab_plan_generated' THEN user_pseudo_id END) AS step_7,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_started' THEN user_pseudo_id END) AS step_8,
  COUNT(DISTINCT CASE WHEN event_name = 'workout_completed' THEN user_pseudo_id END) AS step_9,
  COUNT(DISTINCT CASE WHEN event_name = 'form_analysis_completed' THEN user_pseudo_id END) AS step_10
FROM ${wildcardTable()}
WHERE _TABLE_SUFFIX BETWEEN '${startSuffix}' AND '${endSuffix}'
`.trim();
}

/**
 * Weekly signup cohorts × weeks-since-signup activity.
 *
 * Ports v_retention_cohorts.sql with one CORRECTION: that view computes
 * `cohort_size` as `COUNT(DISTINCT f.user_pseudo_id)` inside the same
 * (signup_week, weeks_since_signup) group as `active_users`. After the LEFT
 * JOIN both count the same set of users, so its retention_pct is 100% in
 * every cell. Cohort size is computed here in its own CTE, independent of the
 * activity join, which is what makes the percentage mean anything.
 *
 * Also bounded by `_TABLE_SUFFIX` (the view scans every shard ever exported).
 * Consequence: a user whose first sign-in predates the window is treated as a
 * member of the earliest in-window cohort, so the oldest cohort row is an
 * over-count. The shaper keeps only the most recent cohorts, where this does
 * not bite.
 */
export function buildRetentionQuery(start: string, end: string): string {
  const startSuffix = assertShardSuffix(start);
  const endSuffix = assertShardSuffix(end);
  return `
WITH ev AS (
  SELECT
    user_pseudo_id,
    event_name,
    PARSE_DATE('%Y%m%d', event_date) AS event_day
  FROM ${wildcardTable()}
  WHERE _TABLE_SUFFIX BETWEEN '${startSuffix}' AND '${endSuffix}'
),

first_seen AS (
  SELECT user_pseudo_id, DATE_TRUNC(MIN(event_day), WEEK) AS signup_week
  FROM ev
  WHERE event_name = 'sign_in_completed'
  GROUP BY user_pseudo_id
),

cohort_sizes AS (
  SELECT signup_week, COUNT(DISTINCT user_pseudo_id) AS cohort_size
  FROM first_seen
  GROUP BY signup_week
),

activity AS (
  SELECT DISTINCT user_pseudo_id, DATE_TRUNC(event_day, WEEK) AS activity_week
  FROM ev
  WHERE event_name IN ('app_opened', 'workout_started', 'analysis_completed', 'rehab_plan_generated')
)

SELECT
  FORMAT_DATE('%Y-%m-%d', f.signup_week) AS cohort_week,
  DATE_DIFF(a.activity_week, f.signup_week, WEEK) AS weeks_since_signup,
  COUNT(DISTINCT a.user_pseudo_id) AS active_users,
  ANY_VALUE(c.cohort_size) AS cohort_size
FROM first_seen f
JOIN cohort_sizes c ON c.signup_week = f.signup_week
LEFT JOIN activity a
  ON a.user_pseudo_id = f.user_pseudo_id AND a.activity_week >= f.signup_week
GROUP BY cohort_week, weeks_since_signup
HAVING weeks_since_signup IS NOT NULL AND weeks_since_signup >= 0
ORDER BY cohort_week DESC, weeks_since_signup
`.trim();
}

// ---------------------------------------------------------------------------
// Pure row → document shapers
// ---------------------------------------------------------------------------

export interface DailyMetrics {
  engagement: Record<string, number>;
  funnel: Record<string, number>;
  workout: Record<string, number>;
}

/** The single aggregate row of `buildDailyQuery` → the daily doc's payload. */
export function shapeDailyMetrics(row: Record<string, unknown> | undefined): DailyMetrics {
  const r = row ?? {};
  const started = toNumber(r.workouts_started);
  const completed = toNumber(r.workouts_completed);

  return {
    engagement: {
      dau: toNumber(r.dau),
      totalSessions: toNumber(r.total_sessions),
      workoutsStarted: started,
      workoutsCompleted: completed,
      exercisesSkipped: toNumber(r.exercises_skipped_count),
      exercisesSwapped: toNumber(r.exercises_swapped_count),
      usersViewedInsights: toNumber(r.users_viewed_insights),
      usersEarnedAchievement: toNumber(r.users_earned_achievement),
      usersReassessed: toNumber(r.users_reassessed),
      usersExportedPdf: toNumber(r.users_exported_pdf),
      usersSwappedExercise: toNumber(r.users_swapped_exercise),
    },
    funnel: {
      signIns: toNumber(r.f_sign_ins),
      onboardingCompleted: toNumber(r.f_onboarding_completed),
      onboardingSkipped: toNumber(r.f_onboarding_skipped),
      bodyMapOpened: toNumber(r.f_body_map_opened),
      regionsSelected: toNumber(r.f_regions_selected),
      assessmentCompleted: toNumber(r.f_assessment_completed),
      analysisCompleted: toNumber(r.f_analysis_completed),
      analysisFailed: toNumber(r.f_analysis_failed),
      rehabPlanGenerated: toNumber(r.f_rehab_plan_generated),
      workoutStarted: toNumber(r.f_workout_started),
      workoutCompleted: toNumber(r.f_workout_completed),
      workoutEndedEarly: toNumber(r.f_workout_ended_early),
    },
    workout: {
      started,
      completed,
      endedEarly: toNumber(r.workouts_ended_early),
      // Zero starts → 0%, never NaN/Infinity (Firestore rejects both).
      completionRatePct: started > 0 ? roundTo((completed / started) * 100, 1) : 0,
      avgDurationSeconds: roundTo(toNumber(r.avg_duration_seconds), 1),
      avgExercisesCompleted: roundTo(toNumber(r.avg_exercises_completed), 2),
      avgExercisesSkipped: roundTo(toNumber(r.avg_exercises_skipped), 2),
    },
  };
}

export interface ScreenFlowEdge {
  source: string;
  target: string;
  count: number;
}

export interface ScreenFlowShape {
  nodes: string[];
  edges: ScreenFlowEdge[];
  totalSessions: number;
}

/**
 * Edge rows → Sankey payload. Drops sub-threshold edges, keeps the top N by
 * volume, then derives the node list from the SURVIVING edges only (a node
 * whose every edge was trimmed must not appear as an orphan in the diagram).
 */
export function shapeScreenFlow(
  rows: Array<Record<string, unknown>>,
  maxEdges: number = MAX_SANKEY_EDGES,
  minCount: number = MIN_SANKEY_EDGE_COUNT,
): ScreenFlowShape {
  const edges: ScreenFlowEdge[] = [];
  for (const row of rows ?? []) {
    const source = typeof row.source_screen === "string" ? row.source_screen : "";
    const target = typeof row.target_screen === "string" ? row.target_screen : "";
    const count = toNumber(row.transition_count);
    if (!source || !target || count < minCount) continue;
    edges.push({ source, target, count });
  }

  edges.sort((a, b) => b.count - a.count);
  const kept = edges.slice(0, Math.max(0, maxEdges));

  const nodes: string[] = [];
  const seen = new Set<string>();
  for (const edge of kept) {
    for (const node of [edge.source, edge.target]) {
      if (!seen.has(node)) {
        seen.add(node);
        nodes.push(node);
      }
    }
  }

  return {
    nodes: nodes.sort(),
    edges: kept,
    totalSessions: toNumber(rows?.[0]?.total_sessions),
  };
}

export interface FunnelStep {
  order: number;
  name: string;
  uniqueUsers: number;
  conversionPct: number;
}

/**
 * The one aggregate row of `buildFunnelSummaryQuery` → ordered steps.
 *
 * `conversionPct` is percent-of-PREVIOUS-step (the view's definition). Step 1
 * is the base and is reported as 100 rather than the view's NULL, so the bar
 * chart has a number to draw. A zero previous step yields 0, never NaN.
 */
export function buildFunnelSummarySteps(row: Record<string, unknown> | undefined): FunnelStep[] {
  const r = row ?? {};
  const steps: FunnelStep[] = [];
  let previous: number | null = null;

  FUNNEL_STEPS.forEach((step, index) => {
    const uniqueUsers = toNumber(r[step.column]);
    const conversionPct = previous === null
      ? 100
      : (previous > 0 ? roundTo((uniqueUsers / previous) * 100, 1) : 0);
    steps.push({ order: index + 1, name: step.name, uniqueUsers, conversionPct });
    previous = uniqueUsers;
  });

  return steps;
}

export interface RetentionCohort {
  week: string;
  size: number;
  retentionPct: number[];
}

/**
 * Long-format retention rows → one row per cohort with a dense percentage
 * array indexed by weeks-since-signup (index 0 = signup week itself).
 * Offsets with no activity row become 0, so the heatmap has no holes.
 */
export function shapeRetentionCohorts(
  rows: Array<Record<string, unknown>>,
  maxCohorts: number = MAX_RETENTION_COHORTS,
): RetentionCohort[] {
  const byWeek = new Map<string, { size: number; offsets: Map<number, number> }>();

  for (const row of rows ?? []) {
    const week = typeof row.cohort_week === "string" ? row.cohort_week : "";
    if (!week) continue;
    const offset = toNumber(row.weeks_since_signup, -1);
    if (offset < 0 || !Number.isInteger(offset)) continue;

    const entry = byWeek.get(week) ?? { size: toNumber(row.cohort_size), offsets: new Map() };
    entry.size = Math.max(entry.size, toNumber(row.cohort_size));
    entry.offsets.set(offset, toNumber(row.active_users));
    byWeek.set(week, entry);
  }

  // Most recent cohorts first, then trimmed, then re-sorted oldest→newest so
  // the heatmap reads top-to-bottom in chronological order.
  const weeks = Array.from(byWeek.keys()).sort().reverse().slice(0, Math.max(0, maxCohorts));

  return weeks.sort().map((week) => {
    const entry = byWeek.get(week)!;
    const maxOffset = Math.max(0, ...entry.offsets.keys());
    const retentionPct: number[] = [];
    for (let offset = 0; offset <= maxOffset; offset++) {
      const active = entry.offsets.get(offset) ?? 0;
      retentionPct.push(entry.size > 0 ? roundTo((active / entry.size) * 100, 1) : 0);
    }
    return { week, size: entry.size, retentionPct };
  });
}

// ---------------------------------------------------------------------------
// BigQuery access
// ---------------------------------------------------------------------------

let bigqueryClient: BigQuery | null = null;

/**
 * Lazily constructed so importing this module (tests, cold starts that only
 * touch other exports) never builds a client. Auth comes from the functions
 * service account's ADC — no key material anywhere in this repo.
 */
function bq(): BigQuery {
  if (!bigqueryClient) bigqueryClient = new BigQuery({ projectId: BQ_PROJECT });
  return bigqueryClient;
}

async function runQuery(sql: string): Promise<Array<Record<string, unknown>>> {
  const [rows] = await bq().query({ query: sql });
  return (rows ?? []) as Array<Record<string, unknown>>;
}

// ---------------------------------------------------------------------------
// Materialization
// ---------------------------------------------------------------------------

export type MaterializeStatus = "ok" | "no_data" | "error";

export interface DayResult {
  date: string;
  status: MaterializeStatus;
  error?: string;
}

/**
 * Materialize ONE GA4 day into `analytics/dashboard/daily/{dateStr}`.
 *
 * Never throws. `no_data` means the shard doesn't exist yet (expected before
 * GA4's morning export); `error` means the query or the write failed and the
 * details are in Cloud Logging.
 */
export async function materializeDay(
  dateStr: string,
  parentCtx?: RequestContext,
): Promise<DayResult> {
  const ctx = parentCtx ?? newRequestContext("materializeDay");

  if (!isValidDayKey(dateStr)) {
    logWarn(ctx, "materialize_day_invalid_date", { date: String(dateStr) });
    return { date: String(dateStr), status: "error", error: "invalid_date" };
  }

  try {
    const rows = await runQuery(buildDailyQuery(dateStr));
    const metrics = shapeDailyMetrics(rows[0]);

    await dashboardDailyCollection(admin.firestore()).doc(dateStr).set({
      date: dateStr,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      source: "bigquery",
      engagement: metrics.engagement,
      funnel: metrics.funnel,
      workout: metrics.workout,
    });

    logCompleted(ctx, 200, {
      stage: "materialize_day",
      date: dateStr,
      dau: metrics.engagement.dau,
      workoutsCompleted: metrics.workout.completed,
    });
    return { date: dateStr, status: "ok" };
  } catch (err) {
    if (isMissingShardError(err)) {
      logWarn(ctx, "materialize_day_no_shard", { date: dateStr });
      return { date: dateStr, status: "no_data" };
    }
    logError(ctx, err, { stage: "materialize_day", date: dateStr });
    return {
      date: dateStr,
      status: "error",
      error: err instanceof Error ? err.message : String(err),
    };
  }
}

export interface RollupResults {
  screenFlow: MaterializeStatus;
  funnelSummary: MaterializeStatus;
  retention: MaterializeStatus;
}

/** Run one rollup in isolation; a failure is contained to its own doc. */
async function runRollup(
  ctx: RequestContext,
  name: string,
  build: () => Promise<Record<string, unknown>>,
): Promise<MaterializeStatus> {
  try {
    const payload = await build();
    await dashboardMetaCollection(admin.firestore()).doc(name).set(payload);
    logCompleted(ctx, 200, { stage: "materialize_rollup", rollup: name });
    return "ok";
  } catch (err) {
    logError(ctx, err, { stage: "materialize_rollup", rollup: name });
    return "error";
  }
}

/**
 * Rebuild the three rolling-window meta docs. Each is overwritten wholesale
 * (they are derived views, not accumulators) and each is independently
 * wrapped. Never throws.
 */
export async function materializeRollups(parentCtx?: RequestContext): Promise<RollupResults> {
  const ctx = parentCtx ?? newRequestContext("materializeRollups");
  const now = new Date();
  const window = windowSuffixes(ROLLUP_WINDOW_DAYS, now);
  const retentionWindow = windowSuffixes(RETENTION_WINDOW_DAYS, now);
  // Must name the last shard actually aggregated, not "now" — `windowSuffixes`
  // ends on yesterday, so dating these docs today would make the stored
  // metadata contradict the data it describes.
  const windowEnd = offsetDayKey(now, -1);
  const serverTimestamp = () => admin.firestore.FieldValue.serverTimestamp();

  const screenFlow = await runRollup(ctx, META_SCREEN_FLOW, async () => {
    const rows = await runQuery(buildScreenFlowQuery(window.start, window.end));
    const shaped = shapeScreenFlow(rows);
    return {
      generatedAt: serverTimestamp(),
      windowDays: ROLLUP_WINDOW_DAYS,
      windowEnd,
      nodes: shaped.nodes,
      edges: shaped.edges,
      totalSessions: shaped.totalSessions,
    };
  });

  const funnelSummary = await runRollup(ctx, META_FUNNEL_SUMMARY, async () => {
    const rows = await runQuery(buildFunnelSummaryQuery(window.start, window.end));
    return {
      generatedAt: serverTimestamp(),
      windowDays: ROLLUP_WINDOW_DAYS,
      windowEnd,
      steps: buildFunnelSummarySteps(rows[0]),
    };
  });

  const retention = await runRollup(ctx, META_RETENTION, async () => {
    const rows = await runQuery(
      buildRetentionQuery(retentionWindow.start, retentionWindow.end),
    );
    return {
      generatedAt: serverTimestamp(),
      windowDays: RETENTION_WINDOW_DAYS,
      windowEnd,
      cohorts: shapeRetentionCohorts(rows),
    };
  });

  return { screenFlow, funnelSummary, retention };
}

// ---------------------------------------------------------------------------
// Cloud Function: pullDailyAnalytics (scheduled)
// ---------------------------------------------------------------------------

/**
 * Name the steps that failed, or `null` when the run was clean.
 *
 * `no_data` is NOT a failure: a day with no GA4 rows is a legitimate outcome
 * (a quiet day, or a shard GA4 published empty). Only `"error"` counts.
 *
 * Exported and pure so the fail-closed behavior below is testable — the
 * `onSchedule` handler itself is never invoked by the Jest suite.
 */
export function summarizeRunFailures(
  results: DayResult[],
  rollups: RollupResults,
): string | null {
  const failedDays = results.filter((r) => r.status === "error").map((r) => r.date);
  const failedRollups = (Object.keys(rollups) as (keyof RollupResults)[])
    .filter((k) => rollups[k] === "error");

  if (failedDays.length === 0 && failedRollups.length === 0) return null;

  const parts: string[] = [];
  if (failedDays.length > 0) parts.push(`days: ${failedDays.join(", ")}`);
  if (failedRollups.length > 0) parts.push(`rollups: ${failedRollups.join(", ")}`);
  return `pullDailyAnalytics had failing steps — ${parts.join("; ")}`;
}

/**
 * 17:00 UTC — comfortably after GA4's daily export lands (~08:00–09:30 PT,
 * i.e. 15:00–16:30 UTC).
 *
 * Re-materializes yesterday AND the day before: GA4 restates a shard for up to
 * ~72h after it first appears, so a day pulled the moment it lands can still
 * change. Each step is isolated — a failed day never blocks the rollups.
 */
export const pullDailyAnalytics = onSchedule(
  {
    schedule: "every day 17:00",
    timeZone: "UTC",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async () => {
    const ctx = newRequestContext("pullDailyAnalytics");
    const days = recentDayKeys(2, new Date());
    const results: DayResult[] = [];

    for (const day of days) {
      try {
        results.push(await materializeDay(day, ctx));
      } catch (err) {
        // materializeDay is written not to throw; belt-and-braces so one
        // unexpected failure cannot skip the remaining day or the rollups.
        logError(ctx, err, { stage: "pull_daily_unexpected", date: day });
        results.push({ date: day, status: "error" });
      }
    }

    let rollups: RollupResults = {
      screenFlow: "error",
      funnelSummary: "error",
      retention: "error",
    };
    try {
      rollups = await materializeRollups(ctx);
    } catch (err) {
      logError(ctx, err, { stage: "pull_daily_rollups_unexpected" });
    }

    logCompleted(ctx, 200, {
      stage: "pull_daily_complete",
      days: results.map((r) => `${r.date}:${r.status}`).join(","),
      rollups: `screenFlow:${rollups.screenFlow},funnelSummary:${rollups.funnelSummary},retention:${rollups.retention}`,
    });

    // Fail the execution if any step errored. Every step above is deliberately
    // isolated so one failure cannot skip the rest — but swallowing them all
    // and returning normally made a total outage (expired BigQuery
    // permissions, say) indistinguishable from a clean run, leaving the
    // dashboard silently stale. Throw AFTER the completion log so the
    // per-step detail is still recorded.
    const failure = summarizeRunFailures(results, rollups);
    if (failure) throw new Error(failure);
  },
);

// ---------------------------------------------------------------------------
// Cloud Function: backfillAnalytics (admin-gated HTTP)
// ---------------------------------------------------------------------------

/**
 * POST { days?: 1..90 (default 7) } or POST { date: "YYYY-MM-DD" }
 *
 * The same-day verification path for the whole pipeline: GA4's next-morning
 * latency otherwise makes the scheduled job impossible to test until tomorrow.
 * Days are processed sequentially — one BigQuery job at a time keeps the run
 * inside the concurrent-query quota and makes the log readable.
 */
export const backfillAnalytics = functions
  .runWith({ timeoutSeconds: 540, memory: "512MB" })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("backfillAnalytics");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const email = await requireAdmin(req, res);
    if (!email) return;

    const body = (req.body ?? {}) as { days?: unknown; date?: unknown };

    let targets: string[];
    if (body.date !== undefined && body.date !== null) {
      if (!isValidDayKey(body.date)) {
        res.status(400).json({ error: "invalid_date", expected: "YYYY-MM-DD" });
        return;
      }
      targets = [body.date];
    } else {
      targets = recentDayKeys(clampBackfillDays(body.days), new Date());
    }

    const days: DayResult[] = [];
    for (const day of targets) {
      days.push(await materializeDay(day, ctx));
    }

    const rollups = await materializeRollups(ctx);

    res.status(200).json({ days, rollups });
  });
