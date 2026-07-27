/**
 * Fixtures for `?mock=1`.
 *
 * Purpose: let the dashboard be built and reviewed before `dashboardData` is
 * deployed. Shapes match the API contract exactly; the numbers are obviously
 * fake (round, smooth, deterministic) so nobody mistakes a mock screenshot for
 * production data.
 *
 * Pure module — imported by the browser AND by dashboard/test/.
 */

/* ------------------------------------------------------------------ helpers */

/** Deterministic 0..1 generator, so every reload draws the same "data". */
function rng(seed) {
  let state = seed >>> 0 || 1;
  return () => {
    state = (state * 1664525 + 1013904223) >>> 0;
    return state / 4294967296;
  };
}

function isoDaysAgo(n, from = new Date()) {
  const d = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), from.getUTCDate()));
  d.setUTCDate(d.getUTCDate() - n);
  return d.toISOString().slice(0, 10);
}

/** Ascending list of ISO dates ending `endOffset` days before today. */
function dateRange(days, endOffset = 1) {
  const out = [];
  for (let i = days - 1; i >= 0; i -= 1) out.push(isoDaysAgo(i + endOffset));
  return out;
}

/** Gentle wave + weekly dip, rounded — reads like real traffic, isn't. */
function wave(index, { base, amp, weekly = 0.18, noise = 0, random = () => 0.5 }) {
  const weekday = index % 7;
  const weekendDip = weekday === 5 || weekday === 6 ? 1 - weekly : 1;
  const swell = 1 + (amp * Math.sin(index / 4.5)) / base;
  const jitter = 1 + (random() - 0.5) * noise;
  return Math.max(0, base * swell * weekendDip * jitter);
}

const AI_REQUEST_TYPES = [
  'analysis',
  'analysis_verify',
  'rehab_plan',
  'exercise_substitute',
  'recovery_insights',
  'form_analysis',
  'wellness_analysis',
  'wellness_verify',
  'wellness_plan',
  'nightly_report',
];

const AI_TYPE_WEIGHT = {
  analysis: 0.26,
  analysis_verify: 0.2,
  rehab_plan: 0.18,
  exercise_substitute: 0.08,
  recovery_insights: 0.07,
  form_analysis: 0.07,
  wellness_analysis: 0.05,
  wellness_verify: 0.04,
  wellness_plan: 0.03,
  nightly_report: 0.02,
};

/* ------------------------------------------------------- screen-flow fixture */

/**
 * 15 screens, ~30 transitions, with deliberate back-navigation cycles
 * (Home <-> My plan, Progress <-> Recovery insights, Profile <-> Settings, and
 * the long Home -> ... -> Workout complete -> Home loop) so the greedy
 * cycle-break in sankey-utils.js is actually exercised.
 */
export const MOCK_SCREEN_FLOW_EDGES = [
  { source: 'Home', target: 'My plan', count: 1200 },
  { source: 'My plan', target: 'Home', count: 600 },
  { source: 'My plan', target: 'Rehab plan', count: 900 },
  { source: 'Home', target: 'Progress', count: 800 },
  { source: 'Progress', target: 'Home', count: 500 },
  { source: 'Home', target: 'Assessment gateway', count: 700 },
  { source: 'Assessment gateway', target: 'Body map', count: 650 },
  { source: 'Body map', target: 'Pain detail', count: 600 },
  { source: 'Pain detail', target: 'Analysis result', count: 550 },
  { source: 'Analysis result', target: 'Rehab plan', count: 500 },
  { source: 'Rehab plan', target: 'Guided workout', count: 450 },
  { source: 'Guided workout', target: 'Workout complete', count: 400 },
  { source: 'Home', target: 'Guided workout', count: 400 },
  { source: 'Workout complete', target: 'Home', count: 350 },
  { source: 'Home', target: 'Profile', count: 300 },
  { source: 'Progress', target: 'Recovery insights', count: 300 },
  { source: 'Profile', target: 'Home', count: 250 },
  { source: 'Assessment gateway', target: 'Wellness goals', count: 250 },
  { source: 'Wellness goals', target: 'Wellness plan', count: 220 },
  { source: 'Workout complete', target: 'My plan', count: 200 },
  { source: 'Rehab plan', target: 'My plan', count: 180 },
  { source: 'Progress', target: 'Settings', count: 150 },
  { source: 'Wellness plan', target: 'My plan', count: 150 },
  { source: 'Guided workout', target: 'Rehab plan', count: 140 },
  { source: 'Recovery insights', target: 'Progress', count: 120 },
  { source: 'Analysis result', target: 'Home', count: 100 },
  { source: 'Profile', target: 'Settings', count: 100 },
  { source: 'Pain detail', target: 'Body map', count: 90 },
  { source: 'Settings', target: 'Profile', count: 90 },
  { source: 'Body map', target: 'Home', count: 80 },
];

/* ------------------------------------------------------------------ overview */

export function mockOverview() {
  const random = rng(20260726);
  const today = isoDaysAgo(0);
  const yesterday = isoDaysAgo(1);

  const trend14d = dateRange(14, 1).map((date, i) => {
    const dau = Math.round(wave(i, { base: 180, amp: 30, noise: 0.08, random }) / 5) * 5;
    return {
      date,
      dau,
      sessions: Math.round((dau * 1.45) / 5) * 5,
      workoutsCompleted: Math.round((dau * 0.5) / 5) * 5,
      aiCostUSD: Number((dau * 0.0028).toFixed(2)),
    };
  });

  const last = trend14d[trend14d.length - 1];

  return {
    now: { serverTime: new Date().toISOString(), date: today },
    live: {
      aiCallsToday: 84,
      aiBudgetLimit: 200,
      aiCostTodayUSD: 0.42,
      aiErrorsToday: 3,
      aiAvgLatencyMsToday: 2400,
      sessionsUploaded24h: 145,
      crashes24h: 2,
      validationFailures: {
        contraindication: 3,
        anatomical_relevance: 2,
        parameter_range: 1,
      },
      missingExerciseImages: 5,
    },
    totals: {
      totalUsers: 1250,
      totalPlans: 3400,
      totalWorkoutSessions: 9800,
      activePlansCount: 260,
      asOf: `${today}T01:00:00.000Z`,
      totalUsersDelta7d: 45,
      totalPlansDelta7d: 120,
    },
    yesterday: {
      date: yesterday,
      dau: last.dau,
      sessions: last.sessions,
      workoutsCompleted: last.workoutsCompleted,
      plansGenerated: 25,
      aiCostUSD: last.aiCostUSD,
    },
    trend14d,
  };
}

/* -------------------------------------------------------------------- graphs */

export function mockGraphs(days = 30) {
  const span = [7, 30, 90].includes(Number(days)) ? Number(days) : 30;
  const random = rng(506142273);
  const dates = dateRange(span, 1);

  const daily = dates.map((date, i) => {
    const dau = Math.round(wave(i, { base: 180, amp: 35, noise: 0.08, random }) / 5) * 5;
    const totalSessions = Math.round((dau * 1.45) / 5) * 5;
    const workoutsStarted = Math.round((dau * 0.62) / 5) * 5;
    const workoutsCompleted = Math.round(workoutsStarted * 0.78 / 5) * 5;
    const endedEarly = Math.max(0, workoutsStarted - workoutsCompleted);
    const signIns = Math.round(dau * 1.1);

    return {
      date,
      engagement: {
        dau,
        totalSessions,
        workoutsStarted,
        workoutsCompleted,
        exercisesSkipped: Math.round(workoutsStarted * 0.4),
        exercisesSwapped: Math.round(workoutsStarted * 0.12),
        usersViewedInsights: Math.round(dau * 0.15),
        usersEarnedAchievement: Math.round(dau * 0.1),
        usersReassessed: Math.round(dau * 0.05),
        usersExportedPdf: Math.round(dau * 0.03),
        usersSwappedExercise: Math.round(dau * 0.09),
      },
      funnel: {
        signIns,
        onboardingCompleted: Math.round(signIns * 0.82),
        assessmentsStarted: Math.round(signIns * 0.6),
        assessmentsSubmitted: Math.round(signIns * 0.48),
        analysisViewed: Math.round(signIns * 0.44),
        plansGenerated: Math.round(signIns * 0.3),
        plansViewed: Math.round(signIns * 0.28),
        workoutsStarted,
        workoutsCompleted,
        workoutEndedEarly: endedEarly,
        exercisesSwapped: Math.round(workoutsStarted * 0.12),
        reassessmentsStarted: Math.round(dau * 0.05),
      },
      workout: {
        started: workoutsStarted,
        completed: workoutsCompleted,
        endedEarly,
        completionRatePct: workoutsStarted ? Number(((workoutsCompleted / workoutsStarted) * 100).toFixed(1)) : 0,
        avgDurationSeconds: Math.round(wave(i, { base: 1080, amp: 120, weekly: 0.05, noise: 0.06, random })),
        avgExercisesCompleted: Number((5 + random() * 1.5).toFixed(1)),
        avgExercisesSkipped: Number((0.6 + random() * 0.6).toFixed(1)),
      },
    };
  });

  const aiDaily = dates.map((date, i) => {
    const calls = Math.round(wave(i, { base: 90, amp: 25, noise: 0.12, random }) / 2) * 2;
    const errors = i % 9 === 0 ? 6 : i % 4 === 0 ? 2 : 1;
    const totalCostUSD = Number((calls * 0.005).toFixed(3));
    const byTypeCostUSD = {};
    for (const type of AI_REQUEST_TYPES) {
      byTypeCostUSD[type] = Number((totalCostUSD * AI_TYPE_WEIGHT[type]).toFixed(4));
    }
    return {
      date,
      calls,
      errors,
      totalCostUSD,
      avgLatencyMs: Math.round(wave(i, { base: 2400, amp: 400, weekly: 0.02, noise: 0.1, random }) / 10) * 10,
      byTypeCostUSD,
    };
  });

  const funnelSteps = [
    ['Signed in', 1000],
    ['Completed onboarding', 820],
    ['Started assessment', 600],
    ['Submitted assessment', 480],
    ['Viewed analysis', 440],
    ['Generated a plan', 300],
    ['Viewed the plan', 280],
    ['Started a workout', 220],
    ['Completed a workout', 170],
    ['Returned the next day', 110],
  ];
  const funnelTop = funnelSteps[0][1];

  const retention = {
    cohorts: Array.from({ length: 8 }, (_, c) => {
      const size = 200 - c * 10;
      const weeks = 8 - c;
      return {
        week: `2026-W${String(22 + c).padStart(2, '0')}`,
        size,
        retentionPct: Array.from({ length: weeks }, (_, w) =>
          w === 0 ? 100 : Number(Math.max(6, 100 * Math.exp(-w / 2.6) - c).toFixed(1)),
        ),
      };
    }),
  };

  return {
    daily,
    aiDaily,
    screenFlow: {
      generatedAt: new Date().toISOString(),
      windowDays: 30,
      nodes: [...new Set(MOCK_SCREEN_FLOW_EDGES.flatMap((e) => [e.source, e.target]))],
      edges: MOCK_SCREEN_FLOW_EDGES,
      totalSessions: 4200,
    },
    funnelSummary: {
      steps: funnelSteps.map(([name, uniqueUsers], i) => ({
        order: i + 1,
        name,
        uniqueUsers,
        conversionPct: Number(((uniqueUsers / funnelTop) * 100).toFixed(1)),
      })),
    },
    retention,
  };
}
