/**
 * Phase 2 (monitoring dashboard): the pure half of the BigQuery pull.
 *
 * BigQuery itself is NOT exercised here (no network, no credentials, no
 * emulator for it) — that half is verified by deploying and hitting
 * `backfillAnalytics`. What IS pinned here is everything that can silently
 * produce wrong numbers on a dashboard:
 *   - date math: shard suffixes, "yesterday backwards" day lists, window bounds
 *   - the SQL text carrying the workout param-mismatch COALESCE fix and a
 *     single validated shard name (no injectable interpolation)
 *   - row → document shaping: rate/average math that must never emit
 *     NaN/Infinity (Firestore rejects both), Sankey trimming, funnel
 *     conversion, retention long-format → per-cohort arrays
 *   - "shard not found" recognition, which must NOT swallow a dataset or
 *     location misconfiguration
 */

import {
  BQ_DATASET,
  BQ_PROJECT,
  MAX_RETENTION_COHORTS,
  isValidDayKey,
  shardSuffix,
  assertShardSuffix,
  dayKeyOf,
  offsetDayKey,
  recentDayKeys,
  windowSuffixes,
  clampBackfillDays,
  toNumber,
  roundTo,
  isMissingShardError,
  buildDailyQuery,
  buildScreenFlowQuery,
  buildFunnelSummaryQuery,
  buildRetentionQuery,
  shapeDailyMetrics,
  shapeScreenFlow,
  buildFunnelSummarySteps,
  shapeRetentionCohorts,
} from "../src/analytics-pull";

// ---------------------------------------------------------------------------
// Date math
// ---------------------------------------------------------------------------

describe("isValidDayKey", () => {
  it("accepts a real ISO day", () => {
    expect(isValidDayKey("2026-07-26")).toBe(true);
    expect(isValidDayKey("2028-02-29")).toBe(true); // leap year
  });

  it("rejects malformed input", () => {
    expect(isValidDayKey("2026-7-26")).toBe(false);
    expect(isValidDayKey("20260726")).toBe(false);
    expect(isValidDayKey("")).toBe(false);
    expect(isValidDayKey(undefined)).toBe(false);
    expect(isValidDayKey(20260726)).toBe(false);
  });

  it("rejects calendar-impossible dates", () => {
    expect(isValidDayKey("2026-02-30")).toBe(false);
    expect(isValidDayKey("2026-13-01")).toBe(false);
  });

  it("rejects SQL-ish payloads", () => {
    expect(isValidDayKey("2026-07-26' OR '1'='1")).toBe(false);
  });
});

describe("shardSuffix / assertShardSuffix", () => {
  it("converts a day key to a GA4 shard suffix", () => {
    expect(shardSuffix("2026-07-26")).toBe("20260726");
  });

  it("throws rather than returning something interpolatable", () => {
    expect(() => shardSuffix("2026-13-01")).toThrow(/invalid day key/);
    expect(() => assertShardSuffix("2026072")).toThrow(/invalid shard suffix/);
    expect(() => assertShardSuffix("2026072x")).toThrow(/invalid shard suffix/);
  });
});

describe("day key offsets", () => {
  const now = new Date("2026-07-26T17:00:00.000Z");

  it("formats UTC day keys", () => {
    expect(dayKeyOf(now)).toBe("2026-07-26");
    // Late-UTC instants must not roll into the next local day.
    expect(dayKeyOf(new Date("2026-07-26T23:59:59.999Z"))).toBe("2026-07-26");
  });

  it("offsets across month boundaries", () => {
    expect(offsetDayKey(new Date("2026-08-01T12:00:00.000Z"), -1)).toBe("2026-07-31");
    expect(offsetDayKey(now, 1)).toBe("2026-07-27");
  });

  it("lists recent days ending YESTERDAY, newest first", () => {
    // Today's shard doesn't exist yet — GA4 exports next morning.
    expect(recentDayKeys(3, now)).toEqual(["2026-07-25", "2026-07-24", "2026-07-23"]);
  });

  it("returns an empty list for a non-positive count", () => {
    expect(recentDayKeys(0, now)).toEqual([]);
    expect(recentDayKeys(-5, now)).toEqual([]);
  });

  it("builds an inclusive window ending today", () => {
    expect(windowSuffixes(30, now)).toEqual({ start: "20260627", end: "20260726" });
    expect(windowSuffixes(1, now)).toEqual({ start: "20260726", end: "20260726" });
  });
});

describe("clampBackfillDays", () => {
  it("defaults to 7", () => {
    expect(clampBackfillDays(undefined)).toBe(7);
    expect(clampBackfillDays(null)).toBe(7);
    expect(clampBackfillDays("abc")).toBe(7);
  });

  it("clamps to [1, 90]", () => {
    expect(clampBackfillDays(0)).toBe(1);
    expect(clampBackfillDays(-3)).toBe(1);
    expect(clampBackfillDays(500)).toBe(90);
    expect(clampBackfillDays(90)).toBe(90);
  });

  it("accepts numeric strings and truncates fractions", () => {
    expect(clampBackfillDays("14")).toBe(14);
    expect(clampBackfillDays(7.9)).toBe(7);
  });
});

// ---------------------------------------------------------------------------
// Value coercion
// ---------------------------------------------------------------------------

describe("toNumber", () => {
  it("passes finite numbers through", () => {
    expect(toNumber(42)).toBe(42);
    expect(toNumber(0)).toBe(0);
  });

  it("parses the string and wrapped-INT64 forms BigQuery can return", () => {
    expect(toNumber("1234")).toBe(1234);
    expect(toNumber({ value: "1234" })).toBe(1234);
  });

  it("falls back for null/undefined/NaN", () => {
    expect(toNumber(null)).toBe(0);
    expect(toNumber(undefined)).toBe(0);
    expect(toNumber(NaN)).toBe(0);
    expect(toNumber("nope", -1)).toBe(-1);
  });
});

describe("roundTo", () => {
  it("rounds to the requested precision", () => {
    expect(roundTo(12.3456, 1)).toBe(12.3);
    expect(roundTo(12.3456, 2)).toBe(12.35);
    expect(roundTo(0, 2)).toBe(0);
  });
});

// ---------------------------------------------------------------------------
// Error classification
// ---------------------------------------------------------------------------

describe("isMissingShardError", () => {
  it("recognizes a missing daily shard", () => {
    expect(isMissingShardError(new Error(
      "Not found: Table pt-helper-dev:analytics_506142273.events_20260726 was not found in location US",
    ))).toBe(true);
  });

  it("does NOT swallow a dataset/location misconfiguration", () => {
    // This one must surface as a real error — reporting it as "no data yet"
    // would hide a permanently broken pipeline.
    expect(isMissingShardError(new Error(
      "Not found: Dataset pt-helper-dev:analytics_506142273 was not found in location US",
    ))).toBe(false);
  });

  it("does not treat permission or generic failures as missing shards", () => {
    expect(isMissingShardError(new Error("Access Denied: Project pt-helper-dev"))).toBe(false);
    expect(isMissingShardError(new Error("quota exceeded"))).toBe(false);
    expect(isMissingShardError(undefined)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// SQL builders
// ---------------------------------------------------------------------------

describe("buildDailyQuery", () => {
  const sql = buildDailyQuery("2026-07-25");

  it("targets exactly the requested day's shard", () => {
    expect(sql).toContain(`\`${BQ_PROJECT}.${BQ_DATASET}.events_20260725\``);
    expect(sql).not.toContain("events_*");
  });

  it("carries the workout_ended_early param-mismatch COALESCE fix", () => {
    expect(sql).toContain("COALESCE(exercises_skipped, skipped_count)");
    expect(sql).toContain("COALESCE(exercises_completed, completed_count)");
  });

  it("counts sessions with an explicit CAST (CONCAT does not coerce INT64)", () => {
    expect(sql).toContain("CAST(ga_session_id AS STRING)");
  });

  it("covers all 12 funnel steps", () => {
    for (const event of [
      "sign_in_completed", "onboarding_completed", "onboarding_skipped",
      "body_map_opened", "regions_selected", "assessment_completed",
      "analysis_completed", "analysis_failed", "rehab_plan_generated",
      "workout_started", "workout_completed", "workout_ended_early",
    ]) {
      expect(sql).toContain(`'${event}'`);
    }
  });

  it("refuses an unvalidated date instead of interpolating it", () => {
    expect(() => buildDailyQuery("2026-07-25'; DROP TABLE x; --")).toThrow(/invalid day key/);
  });
});

describe("rollup queries", () => {
  it("bounds the wildcard scan by _TABLE_SUFFIX", () => {
    const sql = buildScreenFlowQuery("20260627", "20260726");
    expect(sql).toContain(`\`${BQ_PROJECT}.${BQ_DATASET}.events_*\``);
    expect(sql).toContain("_TABLE_SUFFIX BETWEEN '20260627' AND '20260726'");
  });

  it("derives screen transitions with LEAD over the session and drops self-loops", () => {
    const sql = buildScreenFlowQuery("20260627", "20260726");
    expect(sql).toContain("LEAD(screen_name) OVER");
    expect(sql).toContain("PARTITION BY user_pseudo_id, ga_session_id ORDER BY event_timestamp");
    expect(sql).toContain("target_screen != source_screen");
  });

  it("emits all 10 funnel steps in a single scan", () => {
    const sql = buildFunnelSummaryQuery("20260627", "20260726");
    for (let step = 1; step <= 10; step++) expect(sql).toContain(`AS step_${step}`);
    expect(sql.match(/FROM `/g)?.length).toBe(1);
  });

  it("computes retention cohort size independently of the activity join", () => {
    const sql = buildRetentionQuery("20260427", "20260726");
    expect(sql).toContain("cohort_sizes AS");
    expect(sql).toContain("ANY_VALUE(c.cohort_size)");
  });

  it("rejects an unvalidated suffix", () => {
    expect(() => buildScreenFlowQuery("2026", "20260726")).toThrow(/invalid shard suffix/);
    expect(() => buildFunnelSummaryQuery("20260627", "' OR '1'='1")).toThrow(/invalid shard suffix/);
    expect(() => buildRetentionQuery("20260627", "2026072x")).toThrow(/invalid shard suffix/);
  });
});

// ---------------------------------------------------------------------------
// Daily row → document
// ---------------------------------------------------------------------------

describe("shapeDailyMetrics", () => {
  const row = {
    dau: 42,
    total_sessions: 61,
    workouts_started: 20,
    workouts_completed: 15,
    workouts_ended_early: 4,
    exercises_skipped_count: 33,
    exercises_swapped_count: 7,
    users_viewed_insights: 9,
    users_earned_achievement: 5,
    users_reassessed: 2,
    users_exported_pdf: 3,
    users_swapped_exercise: 6,
    f_sign_ins: 40,
    f_onboarding_completed: 30,
    f_onboarding_skipped: 4,
    f_body_map_opened: 25,
    f_regions_selected: 22,
    f_assessment_completed: 20,
    f_analysis_completed: 18,
    f_analysis_failed: 1,
    f_rehab_plan_generated: 16,
    f_workout_started: 12,
    f_workout_completed: 10,
    f_workout_ended_early: 3,
    avg_duration_seconds: 912.44,
    avg_exercises_completed: 5.678,
    avg_exercises_skipped: 1.234,
  };

  it("maps the row into the engagement/funnel/workout blocks", () => {
    const shaped = shapeDailyMetrics(row);
    expect(shaped.engagement).toEqual({
      dau: 42,
      totalSessions: 61,
      workoutsStarted: 20,
      workoutsCompleted: 15,
      exercisesSkipped: 33,
      exercisesSwapped: 7,
      usersViewedInsights: 9,
      usersEarnedAchievement: 5,
      usersReassessed: 2,
      usersExportedPdf: 3,
      usersSwappedExercise: 6,
    });
    expect(shaped.funnel).toEqual({
      signIns: 40,
      onboardingCompleted: 30,
      onboardingSkipped: 4,
      bodyMapOpened: 25,
      regionsSelected: 22,
      assessmentCompleted: 20,
      analysisCompleted: 18,
      analysisFailed: 1,
      rehabPlanGenerated: 16,
      workoutStarted: 12,
      workoutCompleted: 10,
      workoutEndedEarly: 3,
    });
  });

  it("derives the completion rate and rounds the averages", () => {
    const shaped = shapeDailyMetrics(row);
    expect(shaped.workout).toEqual({
      started: 20,
      completed: 15,
      endedEarly: 4,
      completionRatePct: 75,
      avgDurationSeconds: 912.4,
      avgExercisesCompleted: 5.68,
      avgExercisesSkipped: 1.23,
    });
  });

  it("emits 0 — never NaN/Infinity — for a day with no workouts", () => {
    const shaped = shapeDailyMetrics({ dau: 3 });
    expect(shaped.workout.completionRatePct).toBe(0);
    expect(shaped.workout.avgDurationSeconds).toBe(0);
    expect(Number.isFinite(shaped.workout.completionRatePct)).toBe(true);
  });

  it("survives an empty result row", () => {
    const shaped = shapeDailyMetrics(undefined);
    expect(shaped.engagement.dau).toBe(0);
    expect(shaped.funnel.signIns).toBe(0);
    expect(shaped.workout.started).toBe(0);
  });

  it("accepts BigQuery's string/wrapped INT64 forms", () => {
    const shaped = shapeDailyMetrics({ dau: "17", total_sessions: { value: "25" } });
    expect(shaped.engagement.dau).toBe(17);
    expect(shaped.engagement.totalSessions).toBe(25);
  });
});

// ---------------------------------------------------------------------------
// Screen flow → Sankey
// ---------------------------------------------------------------------------

describe("shapeScreenFlow", () => {
  const rows = [
    { source_screen: "Home", target_screen: "MyPlan", transition_count: 50, total_sessions: 120 },
    { source_screen: "MyPlan", target_screen: "Workout", transition_count: 30, total_sessions: 120 },
    { source_screen: "Workout", target_screen: "Home", transition_count: 1, total_sessions: 120 },
  ];

  it("keeps edges at or above the minimum count and reads totalSessions off the rows", () => {
    const shaped = shapeScreenFlow(rows);
    expect(shaped.edges).toEqual([
      { source: "Home", target: "MyPlan", count: 50 },
      { source: "MyPlan", target: "Workout", count: 30 },
    ]);
    expect(shaped.totalSessions).toBe(120);
  });

  it("derives nodes from the SURVIVING edges only", () => {
    // "Workout"→"Home" is trimmed, but Workout survives as MyPlan's target.
    // Home survives as a source. No orphan nodes.
    expect(shapeScreenFlow(rows).nodes).toEqual(["Home", "MyPlan", "Workout"]);
    expect(shapeScreenFlow([rows[2]]).nodes).toEqual([]);
  });

  it("caps the edge list, keeping the highest-volume edges", () => {
    const many = Array.from({ length: 200 }, (_, i) => ({
      source_screen: `S${i}`,
      target_screen: `T${i}`,
      transition_count: i + 2,
      total_sessions: 10,
    }));
    const shaped = shapeScreenFlow(many, 5);
    expect(shaped.edges).toHaveLength(5);
    expect(shaped.edges[0].count).toBe(201);
    expect(shaped.edges[4].count).toBe(197);
  });

  it("drops rows with a missing screen name", () => {
    expect(shapeScreenFlow([
      { source_screen: null, target_screen: "Home", transition_count: 99 },
    ]).edges).toEqual([]);
  });

  it("returns an empty graph for no rows", () => {
    expect(shapeScreenFlow([])).toEqual({ nodes: [], edges: [], totalSessions: 0 });
  });
});

// ---------------------------------------------------------------------------
// Funnel summary
// ---------------------------------------------------------------------------

describe("buildFunnelSummarySteps", () => {
  const row = {
    step_1: 100, step_2: 80, step_3: 60, step_4: 55, step_5: 50,
    step_6: 45, step_7: 40, step_8: 20, step_9: 10, step_10: 0,
  };

  it("returns the 10 ordered steps", () => {
    const steps = buildFunnelSummarySteps(row);
    expect(steps).toHaveLength(10);
    expect(steps[0]).toEqual({ order: 1, name: "Sign In", uniqueUsers: 100, conversionPct: 100 });
    expect(steps[9]).toEqual({
      order: 10, name: "Form Check Done", uniqueUsers: 0, conversionPct: 0,
    });
  });

  it("computes conversion against the PREVIOUS step", () => {
    const steps = buildFunnelSummarySteps(row);
    expect(steps[1].conversionPct).toBe(80); // 80/100
    expect(steps[7].conversionPct).toBe(50); // 20/40
  });

  it("returns 0 rather than NaN once a step hits zero", () => {
    const steps = buildFunnelSummarySteps({ step_1: 0 });
    expect(steps[0].conversionPct).toBe(100);
    expect(steps[1].conversionPct).toBe(0);
    expect(steps.every((s) => Number.isFinite(s.conversionPct))).toBe(true);
  });

  it("survives a missing row", () => {
    expect(buildFunnelSummarySteps(undefined)).toHaveLength(10);
  });
});

// ---------------------------------------------------------------------------
// Retention cohorts
// ---------------------------------------------------------------------------

describe("shapeRetentionCohorts", () => {
  const rows = [
    { cohort_week: "2026-07-19", weeks_since_signup: 0, active_users: 10, cohort_size: 10 },
    { cohort_week: "2026-07-19", weeks_since_signup: 1, active_users: 4, cohort_size: 10 },
    { cohort_week: "2026-07-12", weeks_since_signup: 0, active_users: 8, cohort_size: 8 },
    { cohort_week: "2026-07-12", weeks_since_signup: 2, active_users: 2, cohort_size: 8 },
  ];

  it("pivots the long format into one dense array per cohort", () => {
    expect(shapeRetentionCohorts(rows)).toEqual([
      { week: "2026-07-12", size: 8, retentionPct: [100, 0, 25] },
      { week: "2026-07-19", size: 10, retentionPct: [100, 40] },
    ]);
  });

  it("orders cohorts oldest → newest", () => {
    expect(shapeRetentionCohorts(rows).map((c) => c.week))
      .toEqual(["2026-07-12", "2026-07-19"]);
  });

  it("keeps only the most recent N cohort weeks", () => {
    const many = Array.from({ length: 20 }, (_, i) => ({
      cohort_week: `2026-01-${String(i + 1).padStart(2, "0")}`,
      weeks_since_signup: 0,
      active_users: 1,
      cohort_size: 1,
    }));
    const shaped = shapeRetentionCohorts(many);
    expect(shaped).toHaveLength(MAX_RETENTION_COHORTS);
    expect(shaped[shaped.length - 1].week).toBe("2026-01-20");
    expect(shaped[0].week).toBe("2026-01-09");
  });

  it("returns 0% instead of NaN for an empty cohort", () => {
    expect(shapeRetentionCohorts([
      { cohort_week: "2026-07-19", weeks_since_signup: 0, active_users: 0, cohort_size: 0 },
    ])).toEqual([{ week: "2026-07-19", size: 0, retentionPct: [0] }]);
  });

  it("ignores malformed rows", () => {
    expect(shapeRetentionCohorts([
      { cohort_week: null, weeks_since_signup: 0, active_users: 5, cohort_size: 5 },
      { cohort_week: "2026-07-19", weeks_since_signup: -1, active_users: 5, cohort_size: 5 },
    ])).toEqual([]);
  });

  it("returns an empty list for no rows", () => {
    expect(shapeRetentionCohorts([])).toEqual([]);
  });
});
