/**
 * Tier 3 PR B — structural validator for the Claude-generated nightly report.
 *
 * The report is markdown that gets rendered into the daily ops email. Without
 * this check, a malformed Claude output (truncated tables, empty code fences,
 * dangling headings) ships to the inbox as a broken email.
 *
 * What we check (intentionally permissive — we don't enforce specific section
 * names because the system prompt may evolve):
 *   1. Non-empty after trim.
 *   2. Markdown tables: every `|`-delimited table has header + separator
 *      whose column count matches; data rows have the same column count
 *      (allowing for one column variance to tolerate trailing-pipe styles).
 *   3. No empty code fences (``` immediately followed by ```).
 *   4. No "dangling headings" — a heading line followed only by blank lines
 *      and another heading line (no body content in between).
 *
 * What we do NOT check:
 *   - Specific H2 section names. The original spec mandated `## Usage`,
 *     `## Errors`, etc., but the system prompt doesn't enforce them, and a
 *     prompt change shouldn't break the validator.
 *   - Content quality / accuracy — that's the AI's job, not the validator's.
 */

export interface NightlyReportValidationResult {
  ok: boolean;
  /** Empty when ok=true; one short reason per failure when ok=false. */
  reasons: string[];
}

const VALIDATION_OK: NightlyReportValidationResult = { ok: true, reasons: [] };

export function validateNightlyReport(markdown: string): NightlyReportValidationResult {
  const reasons: string[] = [];

  // 1. Non-empty
  if (!markdown || markdown.trim().length === 0) {
    return { ok: false, reasons: ["empty markdown"] };
  }

  const lines = markdown.split(/\r?\n/);

  // 2. Tables — find every contiguous run of `|`-prefixed lines and validate.
  for (const tableReason of validateTables(lines)) {
    reasons.push(tableReason);
  }

  // 3. Code fences — flag empty pairs (``` followed only by blanks then ```).
  for (const fenceReason of validateCodeFences(lines)) {
    reasons.push(fenceReason);
  }

  // 4. Dangling headings — heading followed by another heading with nothing
  //    but blank lines in between.
  for (const headingReason of validateNoHeadingDangling(lines)) {
    reasons.push(headingReason);
  }

  if (reasons.length === 0) {
    return VALIDATION_OK;
  }
  return { ok: false, reasons };
}

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

/**
 * A markdown table has the shape:
 *   | h1 | h2 | h3 |    ← header
 *   | --- | --- | --- |  ← separator (dashes, optionally colons for alignment)
 *   | r1 | r2 | r3 |    ← zero or more data rows
 *
 * We allow leading/trailing pipes to be present or absent (both are valid
 * markdown). Column count is the number of pipe-separated cells AFTER
 * trimming leading/trailing pipes.
 */
function validateTables(lines: string[]): string[] {
  const reasons: string[] = [];
  let i = 0;
  let tableIndex = 0;
  while (i < lines.length) {
    if (looksLikeTableRow(lines[i])) {
      // Collect contiguous table rows.
      const start = i;
      while (i < lines.length && looksLikeTableRow(lines[i])) {
        i++;
      }
      const tableLines = lines.slice(start, i);
      tableIndex++;

      if (tableLines.length < 2) {
        reasons.push(`table ${tableIndex}: needs at least header + separator`);
        continue;
      }

      const headerCols = countTableColumns(tableLines[0]);
      const separator = tableLines[1];

      if (!isSeparatorRow(separator)) {
        reasons.push(`table ${tableIndex}: row 2 isn't a separator (--- pattern)`);
        continue;
      }

      const sepCols = countTableColumns(separator);
      if (sepCols !== headerCols) {
        reasons.push(
          `table ${tableIndex}: separator has ${sepCols} columns but header has ${headerCols}`,
        );
      }

      // Data rows: from index 2 onwards.
      for (let r = 2; r < tableLines.length; r++) {
        const dataCols = countTableColumns(tableLines[r]);
        if (dataCols !== headerCols) {
          reasons.push(
            `table ${tableIndex}: data row ${r - 1} has ${dataCols} columns, expected ${headerCols}`,
          );
        }
      }
    } else {
      i++;
    }
  }
  return reasons;
}

function looksLikeTableRow(line: string): boolean {
  return /^\s*\|/.test(line) || /\|.*\|/.test(line);
}

function countTableColumns(line: string): number {
  // Strip leading/trailing whitespace + leading/trailing pipes, then split.
  let trimmed = line.trim();
  if (trimmed.startsWith("|")) trimmed = trimmed.slice(1);
  if (trimmed.endsWith("|")) trimmed = trimmed.slice(0, -1);
  return trimmed.split("|").length;
}

function isSeparatorRow(line: string): boolean {
  // Each cell in a separator row is dashes with optional surrounding
  // whitespace and optional alignment colons (`:---`, `---:`, `:---:`).
  // GitHub-Flavored Markdown technically requires 3+ dashes, but real-world
  // generators (and many test fixtures) use 1+ — be lenient.
  let trimmed = line.trim();
  if (trimmed.startsWith("|")) trimmed = trimmed.slice(1);
  if (trimmed.endsWith("|")) trimmed = trimmed.slice(0, -1);
  const cells = trimmed.split("|");
  return cells.every((cell) => /^\s*:?-+:?\s*$/.test(cell));
}

// ---------------------------------------------------------------------------
// Code fences
// ---------------------------------------------------------------------------

function validateCodeFences(lines: string[]): string[] {
  const reasons: string[] = [];
  const fenceRegex = /^```/;
  let i = 0;
  let fenceIndex = 0;
  while (i < lines.length) {
    if (fenceRegex.test(lines[i])) {
      const openLine = i;
      i++;
      // Find the closing fence.
      while (i < lines.length && !fenceRegex.test(lines[i])) {
        i++;
      }
      if (i >= lines.length) {
        // Unclosed fence.
        reasons.push(`code fence ${++fenceIndex}: unclosed (started at line ${openLine + 1})`);
        break;
      }
      // Inspect the body between openLine and i (exclusive).
      const body = lines.slice(openLine + 1, i);
      const nonBlank = body.filter((l) => l.trim().length > 0);
      if (nonBlank.length === 0) {
        reasons.push(`code fence ${++fenceIndex}: empty body (line ${openLine + 1})`);
      } else {
        fenceIndex++;
      }
      i++; // skip the closing fence
    } else {
      i++;
    }
  }
  return reasons;
}

// ---------------------------------------------------------------------------
// Dangling headings
// ---------------------------------------------------------------------------

function headingLevel(line: string): number {
  // Returns the count of leading `#` characters (1-6) for a heading line.
  // 0 if the line isn't a heading.
  const match = /^\s{0,3}(#{1,6})\s/.exec(line);
  return match ? match[1].length : 0;
}

/**
 * A heading is "dangling" if the next non-blank line is ANOTHER heading at
 * the SAME LEVEL or HIGHER (smaller `#` count = higher level). A title
 * (`# Title`) immediately followed by a section heading (`## Section`) is
 * structural nesting, NOT dangling — the title's "body" is the section.
 */
function validateNoHeadingDangling(lines: string[]): string[] {
  const reasons: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    const currentLevel = headingLevel(lines[i]);
    if (currentLevel === 0) continue;

    let j = i + 1;
    while (j < lines.length && lines[j].trim().length === 0) j++;
    if (j >= lines.length) continue;

    const nextLevel = headingLevel(lines[j]);
    if (nextLevel === 0) continue;  // next non-blank is real content
    if (nextLevel > currentLevel) continue;  // structural nesting — fine

    const headingText = lines[i].trim();
    reasons.push(
      `dangling heading at line ${i + 1}: "${headingText}" has no body before next heading at same/higher level`,
    );
  }
  return reasons;
}
