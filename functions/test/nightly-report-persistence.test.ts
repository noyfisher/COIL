/**
 * Nightly report → dashboard persistence (SendGrid is no longer the only
 * channel, so the report must survive a dead mailbox).
 *
 * What MUST be pinned here:
 *   - a report that was never sent reads as "skipped", NOT as "sent" — the
 *     pre-send write happens before any attempt, so an optimistic default
 *     would misreport delivery for every run that later fails
 *   - a send failure is recorded as "failed" with a SHORT message (SendGrid
 *     throws fat response objects; the doc has a 1 MiB ceiling)
 *   - `emailError` is explicitly nulled on non-failures, so a same-day re-run
 *     that succeeds cannot leave the earlier failure's text behind
 *   - the API shaper drops the markdown/metrics copies and never lets a
 *     malformed doc claim `validationPassed`
 *
 * Firestore isn't exercised — everything below is pure.
 */

import {
  shortErrorMessage,
  resolveEmailOutcome,
  buildNightlyReportDoc,
  NIGHTLY_REPORT_MAX_FIELD_CHARS,
} from "../src/index";
import { shapeNightlyReport } from "../src/dashboard-data";

// ---------------------------------------------------------------------------
// shortErrorMessage
// ---------------------------------------------------------------------------

describe("shortErrorMessage", () => {
  it("takes an Error's message", () => {
    expect(shortErrorMessage(new Error("Forbidden"))).toBe("Forbidden");
  });

  it("stringifies non-Error throws", () => {
    expect(shortErrorMessage("plain string")).toBe("plain string");
    expect(shortErrorMessage(401)).toBe("401");
  });

  it("collapses whitespace so a multi-line SendGrid dump stays one line", () => {
    expect(shortErrorMessage(new Error("line one\n  line two\ttabbed"))).toBe(
      "line one line two tabbed",
    );
  });

  it("truncates long messages with an ellipsis", () => {
    const long = "x".repeat(500);
    const out = shortErrorMessage(new Error(long));
    expect(out).toHaveLength(200);
    expect(out.endsWith("…")).toBe(true);
  });

  it("respects a custom max length", () => {
    expect(shortErrorMessage(new Error("abcdefghij"), 5)).toBe("abcd…");
  });

  it("falls back to a placeholder for an empty message", () => {
    expect(shortErrorMessage(new Error("   "))).toBe("unknown error");
  });
});

// ---------------------------------------------------------------------------
// resolveEmailOutcome
// ---------------------------------------------------------------------------

describe("resolveEmailOutcome", () => {
  it("is 'skipped' with no recipient configured", () => {
    expect(
      resolveEmailOutcome({ recipientConfigured: false, sendgridConfigured: true }),
    ).toEqual({ emailStatus: "skipped", emailError: null });
  });

  it("is 'skipped' with no SendGrid key configured", () => {
    expect(
      resolveEmailOutcome({ recipientConfigured: true, sendgridConfigured: false }),
    ).toEqual({ emailStatus: "skipped", emailError: null });
  });

  it("is 'skipped' before the send is attempted — never optimistically 'sent'", () => {
    expect(
      resolveEmailOutcome({ recipientConfigured: true, sendgridConfigured: true }),
    ).toEqual({ emailStatus: "skipped", emailError: null });
  });

  it("is 'sent' once an attempt resolves without error", () => {
    expect(
      resolveEmailOutcome({
        recipientConfigured: true,
        sendgridConfigured: true,
        attempted: true,
        sendError: null,
      }),
    ).toEqual({ emailStatus: "sent", emailError: null });
  });

  it("is 'failed' with a short message when the send throws", () => {
    expect(
      resolveEmailOutcome({
        recipientConfigured: true,
        sendgridConfigured: true,
        attempted: true,
        sendError: new Error("Unauthorized: account deactivated"),
      }),
    ).toEqual({ emailStatus: "failed", emailError: "Unauthorized: account deactivated" });
  });

  it("shortens a fat SendGrid error object", () => {
    const outcome = resolveEmailOutcome({
      recipientConfigured: true,
      sendgridConfigured: true,
      attempted: true,
      sendError: new Error("y".repeat(1000)),
    });
    expect(outcome.emailStatus).toBe("failed");
    expect(outcome.emailError).toHaveLength(200);
  });

  it("stays 'skipped' when config is missing even if an attempt is claimed", () => {
    expect(
      resolveEmailOutcome({
        recipientConfigured: false,
        sendgridConfigured: false,
        attempted: true,
        sendError: new Error("nope"),
      }),
    ).toEqual({ emailStatus: "skipped", emailError: null });
  });
});

// ---------------------------------------------------------------------------
// buildNightlyReportDoc
// ---------------------------------------------------------------------------

describe("buildNightlyReportDoc", () => {
  const base = {
    date: "2026-07-27",
    summaryMarkdown: "## TL;DR\n\n- all good",
    summaryHtml: "<h2>TL;DR</h2><ul><li>all good</li></ul>",
    validationPassed: true,
    metricsText: "Report date: 2026-07-27",
  };

  it("carries every field the dashboard and debugging need", () => {
    expect(
      buildNightlyReportDoc({
        ...base,
        outcome: { emailStatus: "sent", emailError: null },
      }),
    ).toEqual({
      date: "2026-07-27",
      summaryMarkdown: "## TL;DR\n\n- all good",
      summaryHtml: "<h2>TL;DR</h2><ul><li>all good</li></ul>",
      validationPassed: true,
      metricsText: "Report date: 2026-07-27",
      emailStatus: "sent",
      emailError: null,
    });
  });

  it("records a degraded report as validationPassed:false, still persisted", () => {
    const doc = buildNightlyReportDoc({
      ...base,
      validationPassed: false,
      summaryMarkdown: "## Report generation issue",
      outcome: { emailStatus: "failed", emailError: "Unauthorized" },
    });
    expect(doc.validationPassed).toBe(false);
    expect(doc.summaryMarkdown).toContain("Report generation issue");
    expect(doc.emailError).toBe("Unauthorized");
  });

  it("truncates oversized text so the write can't be rejected outright", () => {
    const doc = buildNightlyReportDoc({
      ...base,
      metricsText: "m".repeat(NIGHTLY_REPORT_MAX_FIELD_CHARS + 50),
      outcome: { emailStatus: "skipped", emailError: null },
    });
    expect(doc.metricsText.startsWith("m".repeat(100))).toBe(true);
    expect(doc.metricsText.endsWith("…[truncated]")).toBe(true);
    expect(doc.metricsText.length).toBeLessThan(NIGHTLY_REPORT_MAX_FIELD_CHARS + 20);
  });

  it("leaves normal-sized text untouched", () => {
    const doc = buildNightlyReportDoc({
      ...base,
      outcome: { emailStatus: "skipped", emailError: null },
    });
    expect(doc.summaryHtml).toBe(base.summaryHtml);
    expect(doc.metricsText).toBe(base.metricsText);
  });
});

// ---------------------------------------------------------------------------
// shapeNightlyReport (API side)
// ---------------------------------------------------------------------------

describe("shapeNightlyReport", () => {
  it("returns null when no report doc exists", () => {
    expect(shapeNightlyReport("2026-07-27", undefined)).toBeNull();
  });

  it("shapes a stored doc for the API", () => {
    expect(
      shapeNightlyReport("2026-07-27", {
        date: "2026-07-27",
        generatedAt: new Date("2026-07-27T04:03:00.000Z"),
        summaryMarkdown: "## TL;DR",
        summaryHtml: "<h2>TL;DR</h2>",
        metricsText: "Report date: 2026-07-27",
        validationPassed: true,
        emailStatus: "failed",
        emailError: "Unauthorized",
      }),
    ).toEqual({
      date: "2026-07-27",
      generatedAt: "2026-07-27T04:03:00.000Z",
      summaryHtml: "<h2>TL;DR</h2>",
      validationPassed: true,
      emailStatus: "failed",
    });
  });

  it("omits the markdown and raw metrics — the API ships HTML only", () => {
    const shaped = shapeNightlyReport("2026-07-27", {
      summaryMarkdown: "## TL;DR",
      metricsText: "big blob",
      summaryHtml: "<h2>TL;DR</h2>",
    });
    expect(shaped).not.toHaveProperty("summaryMarkdown");
    expect(shaped).not.toHaveProperty("metricsText");
  });

  it("falls back to the doc id when the date field is missing", () => {
    expect(shapeNightlyReport("2026-07-27", { summaryHtml: "<p>x</p>" })?.date).toBe("2026-07-27");
  });

  it("nulls a generatedAt that never got a server timestamp", () => {
    expect(shapeNightlyReport("2026-07-27", { summaryHtml: "" })?.generatedAt).toBeNull();
  });

  it("defaults validationPassed to false on a malformed doc", () => {
    expect(
      shapeNightlyReport("2026-07-27", { validationPassed: "yes" })?.validationPassed,
    ).toBe(false);
  });

  it("nulls an emailStatus outside the known union", () => {
    expect(shapeNightlyReport("2026-07-27", { emailStatus: "queued" })?.emailStatus).toBeNull();
    expect(shapeNightlyReport("2026-07-27", {})?.emailStatus).toBeNull();
  });

  it("keeps each known emailStatus verbatim", () => {
    for (const status of ["sent", "failed", "skipped"]) {
      expect(shapeNightlyReport("2026-07-27", { emailStatus: status })?.emailStatus).toBe(status);
    }
  });

  it("coerces a missing summaryHtml to an empty string, not undefined", () => {
    expect(shapeNightlyReport("2026-07-27", { date: "2026-07-27" })?.summaryHtml).toBe("");
  });
});
