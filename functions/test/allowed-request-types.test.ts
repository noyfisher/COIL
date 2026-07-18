/**
 * WS12-01: guards the client-callable request-type allow-list.
 *
 * `nightly_report` has no Zod response schema and is scheduled-job-only —
 * it must never become client-callable through `claudeProxy`. This asserts
 * the allow-list's exact shape so a future edit can't silently widen it.
 */

import { ALLOWED_REQUEST_TYPES, SYSTEM_PROMPTS } from "../src/index";

describe("ALLOWED_REQUEST_TYPES", () => {
  it("has exactly 9 members", () => {
    expect(ALLOWED_REQUEST_TYPES.size).toBe(9);
  });

  it("does not contain nightly_report", () => {
    expect(ALLOWED_REQUEST_TYPES.has("nightly_report")).toBe(false);
  });

  it("every member is a key of SYSTEM_PROMPTS", () => {
    for (const type of ALLOWED_REQUEST_TYPES) {
      expect(Object.keys(SYSTEM_PROMPTS)).toContain(type);
    }
  });
});
