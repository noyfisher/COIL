/**
 * Managed Agents API client for cross-session form analysis.
 * Creates ephemeral sessions, sends prior form-session history + current-session
 * pose metrics, and extracts the structured result from the agent's
 * `submit_form_analysis` custom tool call.
 *
 * Structural mirror of managed-agent.ts (recovery insights) — kept in a
 * separate file so the recovery agent path stays untouched.
 */

import Anthropic from "@anthropic-ai/sdk";
import { agentFormAnalysisSchema } from "./response-schemas";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface FormAgentResult {
  // Same shape as the single-call form_analysis response …
  overallScore: number;
  verdict: "excellent" | "good" | "needs_work" | "concern";
  corrections: Array<{
    bodyPart: string;
    issue: string;
    howToFix: string;
    severity: "minor" | "moderate" | "major";
    dataReference?: string;
  }>;
  positivePoints: string[];
  safetyNotes: string[];
  dataLimitations?: string[];
  // … plus cross-session fields:
  progressTrends: Array<{
    metric: string;
    direction: "improving" | "stable" | "declining";
    description: string;
  }>;
  recurringIssues: Array<{
    issue: string;
    sessionsObserved: number;
    description: string;
  }>;
  sessionComparison: string;
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const AGENT_TIMEOUT_MS = 120_000; // 2 minutes — same budget as recovery agent

// ---------------------------------------------------------------------------
// Main function
// ---------------------------------------------------------------------------

export async function runFormAnalysisAgent(
  userMessage: string
): Promise<FormAgentResult> {
  const agentId = process.env.FORM_AGENT_ID?.trim();
  // Environment is shared with the recovery agent (generic no-network env).
  const environmentId = process.env.MANAGED_ENVIRONMENT_ID?.trim();

  if (!agentId || !environmentId) {
    throw new Error("FORM_AGENT_ID or MANAGED_ENVIRONMENT_ID not configured");
  }

  const client = new Anthropic();

  // 1. Create ephemeral session
  const session = await client.beta.sessions.create({
    agent: agentId,
    environment_id: environmentId,
    title: `Form analysis — ${new Date().toISOString()}`,
  });

  console.log(`Created form agent session: ${session.id}`);

  // 2. Open stream FIRST (before sending message to avoid missing early events)
  // 3. Send user message
  // 4. Process events with timeout

  const runPromise = new Promise<FormAgentResult>((resolve, reject) => {
    let result: FormAgentResult | null = null;
    let settled = false;

    const timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error("Form agent timed out after " + AGENT_TIMEOUT_MS + "ms"));
      }
    }, AGENT_TIMEOUT_MS);

    const settle = (fn: () => void) => {
      if (!settled) {
        settled = true;
        clearTimeout(timeout);
        fn();
      }
    };

    (async () => {
      try {
        // Open the event stream (must await the APIPromise to get the Stream)
        const stream = await client.beta.sessions.events.stream(session.id);

        // Send the user message (after stream is opened)
        await client.beta.sessions.events.send(session.id, {
          events: [
            {
              type: "user.message",
              content: [{ type: "text", text: userMessage }],
            },
          ],
        });

        // Process events
        for await (const event of stream) {
          if (settled) break;

          switch (event.type) {
            case "agent.custom_tool_use": {
              const toolEvent = event as { name?: string; input?: unknown };
              if (toolEvent.name === "submit_form_analysis" && toolEvent.input) {
                result = toolEvent.input as FormAgentResult;
                console.log("Agent submitted form analysis via custom tool");
              }
              break;
            }

            case "session.status_idle":
              if (result) {
                settle(() => resolve(result!));
              } else {
                settle(() => reject(new Error("Form agent went idle without submitting analysis")));
              }
              return;

            case "session.error": {
              const errEvent = event as { error?: { message?: string } };
              settle(() =>
                reject(new Error(`Form agent session error: ${errEvent.error?.message || "unknown"}`))
              );
              return;
            }
          }
        }

        // Stream ended without idle event
        if (result) {
          settle(() => resolve(result!));
        } else {
          settle(() => reject(new Error("Form agent stream ended without result")));
        }
      } catch (err) {
        settle(() => reject(err));
      }
    })();
  });

  try {
    return await runPromise;
  } finally {
    // Best-effort delete of the ephemeral session so the user's form-analysis
    // data does not persist at the provider after this one-shot use — on
    // success, error, OR timeout. A failed delete must not change the caller's
    // result, and (per P1-02) it means account deletion has nothing to reach here.
    try {
      await client.beta.sessions.delete(session.id);
      console.log(`Deleted form agent session: ${session.id}`);
    } catch (delErr) {
      console.error(`Failed to delete form agent session ${session.id}:`, delErr);
    }
  }
}

// ---------------------------------------------------------------------------
// Server-side validation
// ---------------------------------------------------------------------------

/**
 * Validate the agent's tool output against the extended form-analysis schema
 * (single-call shape + cross-session fields). Reuses zod rather than the
 * hand-rolled type-guard style of validateInsightResult — the base schema
 * already exists in response-schemas.ts.
 */
export function validateFormResult(result: unknown): result is FormAgentResult {
  return agentFormAnalysisSchema.safeParse(result).success;
}
