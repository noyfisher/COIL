import {
  validateClaudeResponse,
  stripMarkdownFences,
  RESPONSE_SCHEMAS,
} from "../src/response-schemas";

// -------------------------------------------------------------------------
// Helpers
// -------------------------------------------------------------------------

/** Wrap a JSON payload in the Anthropic response envelope. */
function wrap(jsonPayload: unknown): { content: Array<{ type: string; text: string }> } {
  return {
    content: [{ type: "text", text: JSON.stringify(jsonPayload) }],
  };
}

// Minimal valid fixtures ----------------------------------------------------

const validAnalysis = {
  conditions: [
    {
      conditionName: "Patellofemoral Pain Syndrome",
      commonName: "Runner's Knee",
      confidence: 70,
      explanation: "Pain around the kneecap.",
      whatItMeans: "The cushion under your kneecap is irritated.",
      howToManage: "Rest and ice.",
      isRedFlag: false,
      redFlagMessage: "",
      nextSteps: ["Ice 15 minutes twice a day."],
    },
  ],
  overallSummary: "Looks like runner's knee.",
  disclaimerText: "Not medical advice.",
};

const validRehabPlan = {
  planName: "Knee Plan",
  exercises: [
    {
      name: "Quad Sets",
      targetArea: "Knee",
      description: "Press knee into floor.",
      sets: 3,
      reps: "10",
      restSeconds: 30,
      difficulty: "beginner",
      demonstrationIcon: "figure.flexibility",
      tips: ["Keep leg straight."],
      contraindications: ["Stop if painful."],
    },
  ],
  totalWeeks: 4,
};

const validSubstitute = {
  substitutes: [
    {
      name: "Wall Sit",
      targetArea: "Knee",
      description: "Static hold against wall.",
      sets: 3,
      reps: "30 seconds",
      restSeconds: 45,
      difficulty: "beginner",
      demonstrationIcon: "figure.cooldown",
      tips: ["Keep back flat."],
      contraindications: ["Avoid if knee pain worsens."],
    },
  ],
};

const validFormAnalysis = {
  overallScore: 75,
  verdict: "good",
  corrections: [],
  positivePoints: ["Good depth"],
  safetyNotes: [],
};

const validWellnessAnalysis = {
  recommendations: [
    {
      goalCategory: "improve_posture",
      title: "Your Desk Posture Plan",
      currentStateAssessment: "You sit 8 hours a day.",
      rootCauses: ["Prolonged sitting"],
      expectedTimeline: "2-3 weeks",
      keyInsight: "Hip tightness affects posture.",
      priorityLevel: "high",
      relatedGoals: ["reduce_back_pain"],
    },
  ],
  overallSummary: "Focus on posture.",
  disclaimerText: "Not medical advice.",
};

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

describe("stripMarkdownFences", () => {
  it("strips ```json ... ``` wrapper", () => {
    expect(stripMarkdownFences("```json\n{\"a\":1}\n```")).toBe("{\"a\":1}");
  });
  it("strips plain ``` wrapper", () => {
    expect(stripMarkdownFences("```\n{\"a\":1}\n```")).toBe("{\"a\":1}");
  });
  it("leaves unfenced JSON untouched", () => {
    expect(stripMarkdownFences("{\"a\":1}")).toBe("{\"a\":1}");
  });
});

describe("RESPONSE_SCHEMAS dispatch", () => {
  it("has schemas for all in-scope request types", () => {
    const expected = [
      "analysis",
      "analysis_verify",
      "rehab_plan",
      "exercise_substitute",
      "form_analysis",
      "wellness_analysis",
      "wellness_verify",
      "wellness_plan",
    ];
    for (const t of expected) {
      expect(RESPONSE_SCHEMAS[t]).toBeDefined();
    }
  });
  it("does NOT have schemas for recovery_insights or nightly_report", () => {
    expect(RESPONSE_SCHEMAS["recovery_insights"]).toBeUndefined();
    expect(RESPONSE_SCHEMAS["nightly_report"]).toBeUndefined();
  });
});

describe("validateClaudeResponse — happy path", () => {
  it("passes for valid analysis", () => {
    expect(validateClaudeResponse("analysis", wrap(validAnalysis)).ok).toBe(true);
  });
  it("passes for valid analysis_verify", () => {
    expect(validateClaudeResponse("analysis_verify", wrap(validAnalysis)).ok).toBe(true);
  });
  it("passes for valid rehab_plan", () => {
    expect(validateClaudeResponse("rehab_plan", wrap(validRehabPlan)).ok).toBe(true);
  });
  it("passes for valid wellness_plan", () => {
    expect(validateClaudeResponse("wellness_plan", wrap(validRehabPlan)).ok).toBe(true);
  });
  it("passes for valid exercise_substitute", () => {
    expect(validateClaudeResponse("exercise_substitute", wrap(validSubstitute)).ok).toBe(true);
  });
  it("passes for valid form_analysis", () => {
    expect(validateClaudeResponse("form_analysis", wrap(validFormAnalysis)).ok).toBe(true);
  });
  it("passes for valid wellness_analysis", () => {
    expect(validateClaudeResponse("wellness_analysis", wrap(validWellnessAnalysis)).ok).toBe(true);
  });
  it("passes for valid wellness_verify", () => {
    expect(validateClaudeResponse("wellness_verify", wrap(validWellnessAnalysis)).ok).toBe(true);
  });
  it("bypasses validation for unknown request types", () => {
    expect(validateClaudeResponse("recovery_insights", wrap({})).ok).toBe(true);
  });
});

describe("validateClaudeResponse — malformed responses", () => {
  it("fails when response has no text block", () => {
    const result = validateClaudeResponse("analysis", { content: [] });
    expect(result.ok).toBe(false);
  });

  it("fails on non-JSON text", () => {
    const result = validateClaudeResponse("analysis", {
      content: [{ type: "text", text: "I can't help with that." }],
    });
    expect(result.ok).toBe(false);
  });

  it("fails on missing required field (conditions)", () => {
    const bad = { ...validAnalysis, conditions: undefined };
    expect(validateClaudeResponse("analysis", wrap(bad)).ok).toBe(false);
  });

  it("fails on empty conditions array", () => {
    const bad = { ...validAnalysis, conditions: [] };
    expect(validateClaudeResponse("analysis", wrap(bad)).ok).toBe(false);
  });

  it("fails on out-of-range confidence", () => {
    const bad = {
      ...validAnalysis,
      conditions: [{ ...validAnalysis.conditions[0], confidence: 150 }],
    };
    expect(validateClaudeResponse("analysis", wrap(bad)).ok).toBe(false);
  });

  it("fails on invalid verdict enum (form_analysis)", () => {
    const bad = { ...validFormAnalysis, verdict: "perfect" };
    expect(validateClaudeResponse("form_analysis", wrap(bad)).ok).toBe(false);
  });

  it("fails on invalid priorityLevel enum (wellness_analysis)", () => {
    const bad = {
      ...validWellnessAnalysis,
      recommendations: [{ ...validWellnessAnalysis.recommendations[0], priorityLevel: "maximum" }],
    };
    expect(validateClaudeResponse("wellness_analysis", wrap(bad)).ok).toBe(false);
  });

  it("fails on empty substitutes array", () => {
    const bad = { substitutes: [] };
    expect(validateClaudeResponse("exercise_substitute", wrap(bad)).ok).toBe(false);
  });

  it("fails on totalWeeks out of range (rehab_plan)", () => {
    const bad = { ...validRehabPlan, totalWeeks: 100 };
    expect(validateClaudeResponse("rehab_plan", wrap(bad)).ok).toBe(false);
  });
});

describe("validateClaudeResponse — case coercion on enums", () => {
  it("accepts title-case priorityLevel (wellness_analysis)", () => {
    const titleCase = {
      ...validWellnessAnalysis,
      recommendations: [{ ...validWellnessAnalysis.recommendations[0], priorityLevel: "High" }],
    };
    expect(validateClaudeResponse("wellness_analysis", wrap(titleCase)).ok).toBe(true);
  });

  it("accepts title-case verdict (form_analysis)", () => {
    const titleCase = { ...validFormAnalysis, verdict: "Good" };
    expect(validateClaudeResponse("form_analysis", wrap(titleCase)).ok).toBe(true);
  });

  it("accepts uppercase difficulty (rehab_plan)", () => {
    const upper = {
      ...validRehabPlan,
      exercises: [{ ...validRehabPlan.exercises[0], difficulty: "BEGINNER" }],
    };
    expect(validateClaudeResponse("rehab_plan", wrap(upper)).ok).toBe(true);
  });
});

describe("validateClaudeResponse — markdown-fenced responses", () => {
  it("handles ```json wrapped payload", () => {
    const wrapped = {
      content: [
        {
          type: "text",
          text: "```json\n" + JSON.stringify(validAnalysis) + "\n```",
        },
      ],
    };
    expect(validateClaudeResponse("analysis", wrapped).ok).toBe(true);
  });
});
