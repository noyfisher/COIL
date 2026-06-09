/**
 * Tests for validateFormResult — the server-side guard on the form agent's
 * submit_form_analysis tool output. Mirrors response-schemas.test.ts style,
 * but validates the raw tool input object directly (no Anthropic envelope —
 * the agent path extracts the tool input before validation).
 */

import { validateFormResult } from "../src/form-agent";

// Minimal valid agent result -------------------------------------------------

const validAgentResult = {
  overallScore: 78,
  verdict: "good",
  corrections: [
    {
      bodyPart: "knees",
      issue: "Knees showing 8° inward collapse during descent",
      howToFix: "Push your knees outward in line with your toes as you lower.",
      severity: "moderate",
      dataReference: "symmetry.knee: 8.2° left-right difference",
    },
  ],
  positivePoints: ["Good depth achieved on each rep"],
  safetyNotes: [],
  dataLimitations: ["Only 3 reps detected"],
  progressTrends: [
    {
      metric: "Knee range of motion",
      direction: "improving",
      description: "Knee ROM increased from 78° to 91° across 4 sessions",
    },
  ],
  recurringIssues: [
    {
      issue: "Left knee valgus",
      sessionsObserved: 3,
      description: "Inward knee collapse present in 3 of 4 sessions",
    },
  ],
  sessionComparison:
    "Today's depth was your best yet — knee ROM hit 91° vs an 80° average across prior sessions. The left-knee collapse is still present but narrowed from 11° to 8°.",
};

describe("validateFormResult", () => {
  // Happy path ---------------------------------------------------------------

  it("accepts a fully valid agent result", () => {
    expect(validateFormResult(validAgentResult)).toBe(true);
  });

  it("accepts an empty recurringIssues array (recurrence not guaranteed)", () => {
    expect(validateFormResult({ ...validAgentResult, recurringIssues: [] })).toBe(true);
  });

  it("accepts empty corrections (excellent form)", () => {
    expect(validateFormResult({ ...validAgentResult, corrections: [] })).toBe(true);
  });

  it("accepts a result without optional dataLimitations", () => {
    const { dataLimitations: _omitted, ...rest } = validAgentResult;
    expect(validateFormResult(rest)).toBe(true);
  });

  // Cross-session field requirements ------------------------------------------

  it("rejects when sessionComparison is missing", () => {
    const { sessionComparison: _omitted, ...rest } = validAgentResult;
    expect(validateFormResult(rest)).toBe(false);
  });

  it("rejects when progressTrends is missing", () => {
    const { progressTrends: _omitted, ...rest } = validAgentResult;
    expect(validateFormResult(rest)).toBe(false);
  });

  it("rejects when recurringIssues is missing", () => {
    const { recurringIssues: _omitted, ...rest } = validAgentResult;
    expect(validateFormResult(rest)).toBe(false);
  });

  it("rejects an empty sessionComparison", () => {
    expect(validateFormResult({ ...validAgentResult, sessionComparison: "" })).toBe(false);
  });

  it("rejects an over-length sessionComparison (>1200 chars)", () => {
    expect(
      validateFormResult({ ...validAgentResult, sessionComparison: "x".repeat(1201) })
    ).toBe(false);
  });

  // Enum validation ------------------------------------------------------------

  it("rejects an invalid trend direction", () => {
    const bad = {
      ...validAgentResult,
      progressTrends: [
        { metric: "Tempo", direction: "worsening", description: "Tempo got faster" },
      ],
    };
    expect(validateFormResult(bad)).toBe(false);
  });

  it("rejects an invalid verdict", () => {
    expect(validateFormResult({ ...validAgentResult, verdict: "amazing" })).toBe(false);
  });

  it("accepts uppercase enum variants (lowercase coercion)", () => {
    const upper = {
      ...validAgentResult,
      verdict: "Good",
      progressTrends: [
        {
          metric: "Knee range of motion",
          direction: "Improving",
          description: "Knee ROM increased from 78° to 91°",
        },
      ],
    };
    expect(validateFormResult(upper)).toBe(true);
  });

  // Base-schema constraints still enforced --------------------------------------

  it("rejects an out-of-range overallScore", () => {
    expect(validateFormResult({ ...validAgentResult, overallScore: 101 })).toBe(false);
  });

  it("rejects when positivePoints is empty (base schema requires ≥1)", () => {
    expect(validateFormResult({ ...validAgentResult, positivePoints: [] })).toBe(false);
  });

  it("rejects a correction missing howToFix", () => {
    const bad = {
      ...validAgentResult,
      corrections: [
        {
          bodyPart: "knees",
          issue: "Inward collapse",
          severity: "moderate",
        },
      ],
    };
    expect(validateFormResult(bad)).toBe(false);
  });

  it("rejects recurringIssues with sessionsObserved below 2", () => {
    const bad = {
      ...validAgentResult,
      recurringIssues: [
        { issue: "Left knee valgus", sessionsObserved: 1, description: "Seen once" },
      ],
    };
    expect(validateFormResult(bad)).toBe(false);
  });

  // Garbage inputs ---------------------------------------------------------------

  it("rejects null, non-objects, and empty objects", () => {
    expect(validateFormResult(null)).toBe(false);
    expect(validateFormResult("a string")).toBe(false);
    expect(validateFormResult(42)).toBe(false);
    expect(validateFormResult({})).toBe(false);
  });
});
