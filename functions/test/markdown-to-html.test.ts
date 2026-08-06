/**
 * `markdownToHtml` renders the nightly report. Its output is stored on the
 * report doc and assigned to `innerHTML` by the dashboard
 * (dashboard/public/js/overview.js:366), and its input is untrusted — either
 * Claude's generated summary or, on the validation-failure path, `metricsText`
 * with raw thrown errors interpolated in.
 *
 * These tests pin both halves of the contract: dangerous markup is escaped,
 * and the markdown the report actually uses still renders.
 */

import { markdownToHtml } from "../src/index";

describe("markdownToHtml — escaping untrusted input", () => {
  it("escapes a script tag rather than emitting it", () => {
    const html = markdownToHtml("<script>alert(1)</script>");
    expect(html).not.toContain("<script>");
    expect(html).toBe("&lt;script&gt;alert(1)&lt;/script&gt;");
  });

  it("escapes an event-handler payload so no attribute is created", () => {
    const html = markdownToHtml('<img src=x onerror="fetch(\'//evil\')">');
    expect(html).not.toContain("<img");
    expect(html).not.toContain("onerror=\"");
    expect(html).toContain("&lt;img");
    expect(html).toContain("&quot;");
  });

  it("escapes raw quotes and ampersands", () => {
    expect(markdownToHtml('a & b "c"')).toBe("a &amp; b &quot;c&quot;");
  });

  it("escapes markup arriving through an interpolated error string", () => {
    // Mirrors `lines.push(\`Firestore aggregate error: ${err}\`)` in index.ts.
    const html = markdownToHtml("Firestore aggregate error: <img src=x onerror=alert(1)>");
    expect(html).not.toContain("<img");
    expect(html).toContain("&lt;img src=x onerror=alert(1)&gt;");
  });

  it("does not double-escape an already-escaped entity into something inert", () => {
    // `&amp;` in the source becomes `&amp;amp;` — displays as the literal
    // "&amp;", which is correct: escaping is applied exactly once, at the edge.
    expect(markdownToHtml("&amp;")).toBe("&amp;amp;");
  });
});

describe("markdownToHtml — markdown still renders", () => {
  it("renders an h2 with the email inline style", () => {
    expect(markdownToHtml("## TL;DR")).toBe(
      "<h2 style=\"color:#6B7F6B;margin:16px 0 8px;font-size:18px;\">TL;DR</h2>",
    );
  });

  it("renders bullets wrapped in a ul", () => {
    const html = markdownToHtml("- first\n- second");
    expect(html).toContain("<ul style=\"padding-left:20px;\">");
    expect(html).toContain("<li style=\"margin:4px 0;\">first</li>");
    expect(html).toContain("<li style=\"margin:4px 0;\">second</li>");
  });

  it("renders bold", () => {
    expect(markdownToHtml("**Steady day.**")).toBe("<strong>Steady day.</strong>");
  });

  it("renders a realistic report section end to end", () => {
    const html = markdownToHtml("## Engagement\n\n- **DAU:** 195\n- Sessions: 283");
    expect(html).toContain("<h2 ");
    expect(html).toContain("<strong>DAU:</strong>");
    expect(html).toContain("<ul ");
    expect(html).not.toContain("&lt;h2");
  });
});
