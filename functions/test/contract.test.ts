/**
 * P3-02: cross-stack contract for AI request types. The canonical list lives in
 * contracts/ai-request-types.json; this asserts the SERVER side matches it —
 * every contract type is client-callable AND has both a system prompt and a
 * model config, and the allow-list carries no extras. The iOS side pins the same
 * list in AIRequestTypeContractTests.swift, so client/server can't drift apart.
 */

import { readFileSync } from "fs";
import { resolve } from "path";
import { ALLOWED_REQUEST_TYPES } from "../src/index";
import { SYSTEM_PROMPTS, MODEL_CONFIG } from "../src/prompts";

const contract = JSON.parse(
  readFileSync(resolve(__dirname, "../../contracts/ai-request-types.json"), "utf8"),
) as { clientRequestTypes: string[] };

describe("AI request-type contract (server side)", () => {
  it("ALLOWED_REQUEST_TYPES exactly matches the contract", () => {
    expect([...ALLOWED_REQUEST_TYPES].sort()).toEqual([...contract.clientRequestTypes].sort());
  });

  it("every contract type has a system prompt", () => {
    for (const type of contract.clientRequestTypes) {
      expect(Object.keys(SYSTEM_PROMPTS)).toContain(type);
    }
  });

  it("every contract type has a model config (no unsafe fallback)", () => {
    for (const type of contract.clientRequestTypes) {
      expect(Object.keys(MODEL_CONFIG)).toContain(type);
    }
  });

  it("does not expose the scheduled-only nightly_report to clients", () => {
    expect(contract.clientRequestTypes).not.toContain("nightly_report");
    expect(ALLOWED_REQUEST_TYPES.has("nightly_report")).toBe(false);
  });
});
