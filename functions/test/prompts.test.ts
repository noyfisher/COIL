/**
 * WS12-03: byte-freeze + key-parity guard for the extracted prompts module.
 *
 * No prior test referenced SYSTEM_PROMPTS/MODEL_CONFIG, so a dropped key or
 * an altered wording during the index.ts -> prompts.ts move would have been
 * invisible. These snapshots + parity checks close that gap.
 */

import { SYSTEM_PROMPTS, MODEL_CONFIG, MINOR_SAFETY_PROMPT } from "../src/prompts";
import { RESPONSE_SCHEMAS } from "../src/response-schemas";

describe("prompts module", () => {
  it("system prompts are byte-frozen", () => {
    expect(SYSTEM_PROMPTS).toMatchSnapshot();
  });

  it("model config is byte-frozen", () => {
    expect(MODEL_CONFIG).toMatchSnapshot();
  });

  it("minor safety prompt is byte-frozen", () => {
    expect(MINOR_SAFETY_PROMPT).toMatchSnapshot();
  });

  it("SYSTEM_PROMPTS has the expected 10 keys", () => {
    expect(Object.keys(SYSTEM_PROMPTS).sort()).toEqual([
      "analysis", "analysis_verify", "exercise_substitute", "form_analysis",
      "nightly_report", "recovery_insights", "rehab_plan", "wellness_analysis",
      "wellness_plan", "wellness_verify",
    ].sort());
  });

  it("MODEL_CONFIG has the expected 10 keys", () => {
    expect(Object.keys(MODEL_CONFIG).sort()).toEqual(Object.keys(SYSTEM_PROMPTS).sort());
  });

  it("every RESPONSE_SCHEMAS key has a prompt and a model config", () => {
    for (const type of Object.keys(RESPONSE_SCHEMAS)) {
      expect(Object.keys(SYSTEM_PROMPTS)).toContain(type);
      expect(Object.keys(MODEL_CONFIG)).toContain(type);
    }
  });
});
