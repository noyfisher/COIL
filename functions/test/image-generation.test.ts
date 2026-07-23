/**
 * P1-08: the on-demand image-generation endpoint must accept only well-formed
 * requests for exercises the server actually catalogues — so arbitrary /
 * AI-hallucinated names can't create cost, poison the shared alias mapping, or
 * promote an unvetted illustration into shared state.
 */

import { validateGenerateRequest, isCanonicalExercise } from "../src/image-generation";

describe("validateGenerateRequest", () => {
  it("accepts a well-formed request", () => {
    expect(validateGenerateRequest({ exerciseName: "Bird Dog" })).toBeNull();
  });

  it("accepts optional metadata within limits", () => {
    expect(validateGenerateRequest({
      exerciseName: "Bird Dog",
      targetArea: "Core",
      bodyPosition: "quadruped",
      poseDescription: "on hands and knees",
    })).toBeNull();
  });

  it("rejects a missing / empty / non-string exerciseName", () => {
    expect(validateGenerateRequest({ exerciseName: "" })).toBe("exerciseName is required");
    expect(validateGenerateRequest({ exerciseName: "   " })).toBe("exerciseName is required");
    // @ts-expect-error deliberately wrong type at runtime
    expect(validateGenerateRequest({ exerciseName: 123 })).toBe("exerciseName is required");
  });

  it("rejects an over-long exerciseName", () => {
    expect(validateGenerateRequest({ exerciseName: "x".repeat(101) })).toBe("exerciseName is too long");
  });

  it("rejects an over-long metadata field", () => {
    expect(validateGenerateRequest({
      exerciseName: "Bird Dog",
      poseDescription: "y".repeat(201),
    })).toBe("poseDescription is invalid");
  });
});

describe("isCanonicalExercise", () => {
  // "90-90 Hip Flexor Stretch" is the first entry of the generated catalog.
  it("accepts a catalogued exercise, case- and whitespace-insensitively", () => {
    expect(isCanonicalExercise("90-90 Hip Flexor Stretch")).toBe(true);
    expect(isCanonicalExercise("  90-90 hip flexor stretch  ")).toBe(true);
  });

  it("accepts the catalog slug form", () => {
    expect(isCanonicalExercise("90-90-hip-flexor-stretch")).toBe(true);
  });

  it("rejects an off-catalog / hallucinated name", () => {
    expect(isCanonicalExercise("Totally Fake Made Up Exercise ZZZ")).toBe(false);
  });
});
