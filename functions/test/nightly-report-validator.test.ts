import { validateNightlyReport } from "../src/nightly-report-validator";

// ---------------------------------------------------------------------------
// Happy path
// ---------------------------------------------------------------------------

describe("validateNightlyReport — happy paths", () => {
  it("accepts a minimal valid report", () => {
    const md = `# Daily Report

Healthy.
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(true);
    expect(result.reasons).toEqual([]);
  });

  it("accepts a report with one well-formed table", () => {
    const md = `# Daily Report

## Usage
| Metric | Today | Yesterday |
| ------ | ----- | --------- |
| DAU    | 50    | 48        |
| Sessions | 120 | 110       |
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });

  it("accepts a report with multiple tables and headings", () => {
    const md = `# Daily Report

## Users
| Metric | Value |
| ------ | ----- |
| DAU    | 50    |

## Engagement
Most users completed at least one workout.

| Metric | Value |
| ------ | ----- |
| Workouts | 40 |
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });

  it("accepts a report with a non-empty code fence", () => {
    const md = `## Errors

\`\`\`
Stack trace here
\`\`\`
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });

  it("accepts tables without leading/trailing pipes", () => {
    const md = `## Stats

Metric | Value
------ | -----
DAU    | 50
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Empty / whitespace
// ---------------------------------------------------------------------------

describe("validateNightlyReport — empty input", () => {
  it("rejects empty string", () => {
    const result = validateNightlyReport("");
    expect(result.ok).toBe(false);
    expect(result.reasons).toContain("empty markdown");
  });

  it("rejects whitespace-only input", () => {
    const result = validateNightlyReport("   \n\n\t  \n");
    expect(result.ok).toBe(false);
    expect(result.reasons).toContain("empty markdown");
  });
});

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

describe("validateNightlyReport — table validation", () => {
  it("rejects table where data row column count differs from header", () => {
    const md = `## Stats

| A | B | C |
| - | - | - |
| 1 | 2 |
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("data row"))).toBe(true);
  });

  it("rejects table where separator column count differs from header", () => {
    const md = `## Stats

| A | B | C |
| - | - |
| 1 | 2 | 3 |
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("separator"))).toBe(true);
  });

  it("rejects table missing the separator row", () => {
    const md = `## Stats

| A | B |
| 1 | 2 |
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("isn't a separator"))).toBe(true);
  });

  it("rejects table with only one row (header without separator)", () => {
    const md = `## Stats

| A | B | C |
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("at least header + separator"))).toBe(true);
  });

  it("accepts table with alignment colons in separator", () => {
    const md = `## Stats

| Left | Center | Right |
| :--- | :----: | ----: |
| a    | b      | c     |
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });

  it("multiple bad tables: each gets its own reason", () => {
    const md = `## Stats

| A | B | C |
| - | - |
| 1 | 2 | 3 |

## More

| X | Y |
| - | - |
| 1 |
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.length).toBeGreaterThanOrEqual(2);
  });
});

// ---------------------------------------------------------------------------
// Code fences
// ---------------------------------------------------------------------------

describe("validateNightlyReport — code fence validation", () => {
  it("rejects empty code fence", () => {
    const md = `## Errors

\`\`\`
\`\`\`
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("empty body"))).toBe(true);
  });

  it("rejects code fence containing only blank lines", () => {
    const md = `## Errors

\`\`\`



\`\`\`
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("empty body"))).toBe(true);
  });

  it("rejects unclosed code fence", () => {
    const md = `## Errors

\`\`\`
some text but no closing fence
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("unclosed"))).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Dangling headings
// ---------------------------------------------------------------------------

describe("validateNightlyReport — dangling headings", () => {
  it("rejects heading immediately followed by another heading", () => {
    const md = `## Section A
## Section B

Content here.
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("dangling heading"))).toBe(true);
  });

  it("rejects heading followed by blanks then another heading", () => {
    const md = `## Section A



## Section B

Content here.
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    expect(result.reasons.some((r) => r.includes("dangling heading"))).toBe(true);
  });

  it("accepts heading followed by content then another heading", () => {
    const md = `## Section A

Some content.

## Section B

More content.
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });

  it("does not flag the LAST heading as dangling", () => {
    const md = `## A

content

## B

content

## C
`;
    // C has no body, but there's no FOLLOWING heading, so it shouldn't fire.
    const result = validateNightlyReport(md);
    // (Note: C dangling is allowed by current rule — only "heading followed by
    // heading with nothing between" fires.)
    expect(result.ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Composite failures
// ---------------------------------------------------------------------------

describe("validateNightlyReport — composite failures", () => {
  it("collects multiple distinct failure reasons", () => {
    const md = `## Section A
## Section B

| A | B | C |
| - | - |
| 1 | 2 | 3 |

\`\`\`
\`\`\`
`;
    const result = validateNightlyReport(md);
    expect(result.ok).toBe(false);
    // Should have: 1 dangling heading + 1 separator mismatch + 1 empty fence
    expect(result.reasons.length).toBeGreaterThanOrEqual(3);
  });
});

// ---------------------------------------------------------------------------
// Realistic Claude output
// ---------------------------------------------------------------------------

describe("validateNightlyReport — realistic Claude outputs", () => {
  it("accepts a full realistic report mirroring the system-prompt structure", () => {
    const md = `## TL;DR
App is healthy. DAU steady, no errors.

## Users
| Metric | Today | Yesterday |
| ------ | ----- | --------- |
| DAU    | 50    | 48        |
| Signups | 3    | 5         |

## Engagement
| Metric | Value |
| ------ | ----- |
| Sessions | 120 |
| Workouts | 80  |

## Funnel
Conversion at each step:
- Onboarding → Plan: 70%
- Plan → First Workout: 60%

## Stability
| Metric | Value |
| ------ | ----- |
| API success rate | 99.5% |
| Errors | 2 |

## Action Items
- Look into the 2 errors in claudeProxy.
`;
    expect(validateNightlyReport(md).ok).toBe(true);
  });
});
