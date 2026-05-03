/**
 * Response schemas for Claude API responses, one per `AIRequestType`.
 *
 * Used by `claudeProxy` (see `index.ts`) as a safety net: after Anthropic returns a
 * response, we extract the text from `content[0].text`, strip any markdown fences,
 * parse as JSON, and validate against the per-type schema. If validation fails, we
 * return HTTP 502 with `{ error: "ai_response_invalid" }` instead of passing a
 * malformed payload through to the iOS client.
 *
 * Enums (e.g. priorityLevel, verdict) use a `.toLowerCase()` coercion before the
 * literal check to tolerate title-case from Claude — the model occasionally emits
 * "High" / "Low" / "Excellent" instead of lowercase.
 *
 * Schemas NOT covered here:
 * - `recovery_insights`: validated by `validateInsightResult` in managed-agent.ts
 *   (and again client-side in Tier 1).
 * - `nightly_report`: markdown output, not JSON.
 * - `cross_verify`: validated inside the `crossVerify` function (separate function,
 *   not routed through `claudeProxy`).
 */

import { z } from "zod";

// Shared helpers -------------------------------------------------------------

const lowercaseEnum = <T extends [string, ...string[]]>(values: T) =>
  z
    .string()
    .transform((s) => s.toLowerCase())
    .pipe(z.enum(values));

// Injury analysis (primary + verify) ----------------------------------------

const conditionSchema = z.object({
  conditionName: z.string().min(1),
  commonName: z.string().min(1),
  confidence: z.number().min(0).max(100),
  explanation: z.string().min(1),
  whatItMeans: z.string().min(1),
  howToManage: z.string(),
  isRedFlag: z.boolean(),
  redFlagMessage: z.string(),  // may be ""
  nextSteps: z.array(z.string()),
});

export const analysisSchema = z.object({
  conditions: z.array(conditionSchema).min(1),
  overallSummary: z.string().min(1),
  disclaimerText: z.string().min(1),
});

// analysis_verify shares the same payload shape as analysis.
export const analysisVerifySchema = analysisSchema;

// Rehab plan + wellness plan (same shape) -----------------------------------

const exerciseSchema = z.object({
  name: z.string().min(1),
  targetArea: z.string().min(1),
  description: z.string().min(1),
  sets: z.number().int().min(0),
  reps: z.string().min(1),
  restSeconds: z.number().int().min(0),
  difficulty: lowercaseEnum(["beginner", "intermediate", "advanced"]),
  demonstrationIcon: z.string(),
  tips: z.array(z.string()),
  contraindications: z.array(z.string()),
  startPosition: z.string().optional(),
  movement: z.string().optional(),
  endPosition: z.string().optional(),
  exerciseCategory: z.string().optional(),
  imageFileName: z.string().optional(),
  // Catalog-substitution signal: true when Claude picked an anatomically-adjacent
  // exercise because the patient's primary target_area had no exact match.
  // Optional so older clients/responses without the field decode cleanly.
  catalogSubstitution: z.boolean().optional(),
  // Per-exercise notes — populated by Claude only when catalogSubstitution is true.
  notes: z.string().optional(),
});

export const rehabPlanSchema = z.object({
  planName: z.string().min(1),
  exercises: z.array(exerciseSchema).min(1),
  totalWeeks: z.number().int().min(1).max(52),
  notes: z.string().optional(),
});

export const wellnessPlanSchema = rehabPlanSchema;

// Exercise substitute -------------------------------------------------------

const substituteExerciseSchema = exerciseSchema.extend({
  whyItHelps: z.string().optional(),
});

export const exerciseSubstituteSchema = z.object({
  substitutes: z.array(substituteExerciseSchema).min(1),
});

// Form analysis -------------------------------------------------------------

const correctionSchema = z.object({
  bodyPart: z.string().min(1),
  issue: z.string().min(1),
  howToFix: z.string().min(1),
  severity: lowercaseEnum(["minor", "moderate", "major"]),
  dataReference: z.string().optional(),
});

export const formAnalysisSchema = z.object({
  overallScore: z.number().min(0).max(100),
  verdict: lowercaseEnum(["excellent", "good", "needs_work", "concern"]),
  corrections: z.array(correctionSchema),
  positivePoints: z.array(z.string()).min(1),
  safetyNotes: z.array(z.string()),
  dataLimitations: z.array(z.string()).optional(),
});

// Wellness analysis (primary + verify) --------------------------------------

const wellnessRecommendationSchema = z.object({
  goalCategory: z.string().min(1),
  title: z.string().min(1),
  currentStateAssessment: z.string().min(1),
  rootCauses: z.array(z.string()),
  expectedTimeline: z.string().min(1),
  keyInsight: z.string().min(1),
  priorityLevel: lowercaseEnum(["high", "medium", "low"]),
  relatedGoals: z.array(z.string()),
});

export const wellnessAnalysisSchema = z.object({
  recommendations: z.array(wellnessRecommendationSchema).min(1),
  overallSummary: z.string().min(1),
  disclaimerText: z.string().min(1),
});

export const wellnessVerifySchema = wellnessAnalysisSchema;

// Dispatch table ------------------------------------------------------------

/**
 * Per-requestType schemas. A requestType not present here is NOT validated — that's
 * intentional for `recovery_insights`, `nightly_report`, and `cross_verify`, which
 * have dedicated validation elsewhere.
 */
export const RESPONSE_SCHEMAS: Record<string, z.ZodTypeAny> = {
  analysis: analysisSchema,
  analysis_verify: analysisVerifySchema,
  rehab_plan: rehabPlanSchema,
  exercise_substitute: exerciseSubstituteSchema,
  form_analysis: formAnalysisSchema,
  wellness_analysis: wellnessAnalysisSchema,
  wellness_verify: wellnessVerifySchema,
  wellness_plan: wellnessPlanSchema,
};

/**
 * Strip Claude's occasional markdown code fences (` ```json ... ``` `) from a
 * response text. The system prompts explicitly forbid markdown, but we defend
 * against it anyway — Claude sometimes wraps its JSON when asked about "format".
 */
export function stripMarkdownFences(text: string): string {
  return text
    .replace(/^\s*```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();
}

/**
 * Extract the JSON payload from an Anthropic messages response object and validate
 * it against the schema for the given requestType.
 *
 * Returns:
 * - `{ ok: true }` if validation passed OR there's no schema for this requestType.
 * - `{ ok: false, reason }` if extraction or validation failed.
 *
 * Note: we do NOT mutate the response — this is a *check*, not a transform. The
 * caller returns the original response to the client on success; on failure they
 * return HTTP 502.
 */
export function validateClaudeResponse(
  requestType: string,
  responseData: unknown,
): { ok: true } | { ok: false; reason: string } {
  const schema = RESPONSE_SCHEMAS[requestType];
  if (!schema) return { ok: true };  // intentionally unvalidated

  // Anthropic response shape: { content: [{ type: "text", text: "..." }, ...], ... }
  const response = responseData as {
    content?: Array<{ type?: string; text?: string }>;
  };
  const block = response?.content?.find((b) => b?.type === "text");
  const rawText = block?.text;
  if (typeof rawText !== "string" || rawText.length === 0) {
    return { ok: false, reason: "no text block in response" };
  }

  const cleaned = stripMarkdownFences(rawText);
  let parsed: unknown;
  try {
    parsed = JSON.parse(cleaned);
  } catch (e) {
    return {
      ok: false,
      reason: `JSON parse failed: ${e instanceof Error ? e.message : String(e)}`,
    };
  }

  const result = schema.safeParse(parsed);
  if (!result.success) {
    // Keep the reason short — first issue is enough for logging.
    const first = result.error.issues[0];
    const path = first?.path?.join(".") ?? "(root)";
    return { ok: false, reason: `schema: ${path} — ${first?.message}` };
  }

  return { ok: true };
}
