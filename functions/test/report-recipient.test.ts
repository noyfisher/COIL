/**
 * P3-03: the nightly report must NOT fall back to a hardcoded personal email.
 * `resolveReportRecipient` returns null when no org recipient is configured so
 * the scheduled job skips sending rather than leaking operational data.
 */

import { resolveReportRecipient, resolveReportSender } from "../src/index";

describe("resolveReportRecipient", () => {
  it("returns the configured recipient", () => {
    expect(resolveReportRecipient({ REPORT_RECIPIENT_EMAIL: "reports@org.example" } as NodeJS.ProcessEnv))
      .toBe("reports@org.example");
  });

  it("trims surrounding whitespace", () => {
    expect(resolveReportRecipient({ REPORT_RECIPIENT_EMAIL: "  reports@org.example  " } as NodeJS.ProcessEnv))
      .toBe("reports@org.example");
  });

  it("returns null when unset — no personal-email fallback", () => {
    expect(resolveReportRecipient({} as NodeJS.ProcessEnv)).toBeNull();
  });

  it("returns null when blank", () => {
    expect(resolveReportRecipient({ REPORT_RECIPIENT_EMAIL: "   " } as NodeJS.ProcessEnv)).toBeNull();
  });
});

describe("resolveReportSender", () => {
  it("returns the configured sender", () => {
    expect(resolveReportSender({ REPORT_SENDER_EMAIL: "no-reply@org.example" } as NodeJS.ProcessEnv))
      .toBe("no-reply@org.example");
  });

  it("trims surrounding whitespace", () => {
    expect(resolveReportSender({ REPORT_SENDER_EMAIL: "  no-reply@org.example  " } as NodeJS.ProcessEnv))
      .toBe("no-reply@org.example");
  });

  it("returns null when unset — no hardcoded sender fallback", () => {
    expect(resolveReportSender({} as NodeJS.ProcessEnv)).toBeNull();
  });

  it("returns null when blank", () => {
    expect(resolveReportSender({ REPORT_SENDER_EMAIL: "   " } as NodeJS.ProcessEnv)).toBeNull();
  });
});
