/**
 * Managed Agents API client for PT Helper.
 * Creates ephemeral sessions, sends recovery data, and extracts structured results
 * from the agent's custom tool call.
 */

import Anthropic from "@anthropic-ai/sdk";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface RecoveryInsightResult {
  headline: string;
  summary: string;
  painAnalysis: {
    trendDirection: "improving" | "stable" | "worsening";
    trendDescription: string;
    averagePain: number;
    regionBreakdown?: Array<{ region: string; trend: string; averagePain: number }> | null;
  };
  adherenceAnalysis: {
    score: number;
    sessionsCompleted: number;
    sessionsExpected: number;
    description: string;
  };
  keyWins: string[];
  focusAreas: string[];
  recommendations: Array<{ icon: string; title: string; description: string }>;
}

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const AGENT_TIMEOUT_MS = 120_000; // 2 minutes

// ---------------------------------------------------------------------------
// Main function
// ---------------------------------------------------------------------------

export async function runRecoveryInsightsAgent(
  userMessage: string
): Promise<RecoveryInsightResult> {
  const agentId = process.env.MANAGED_AGENT_ID?.trim();
  const environmentId = process.env.MANAGED_ENVIRONMENT_ID?.trim();

  if (!agentId || !environmentId) {
    throw new Error("MANAGED_AGENT_ID or MANAGED_ENVIRONMENT_ID not configured");
  }

  const client = new Anthropic();

  // 1. Create ephemeral session
  const session = await client.beta.sessions.create({
    agent: agentId,
    environment_id: environmentId,
    title: `Recovery insights — ${new Date().toISOString()}`,
  });

  console.log(`Created agent session: ${session.id}`);

  // 2. Open stream FIRST (before sending message to avoid missing early events)
  // 3. Send user message
  // 4. Process events with timeout

  return new Promise<RecoveryInsightResult>((resolve, reject) => {
    let result: RecoveryInsightResult | null = null;
    let settled = false;

    const timeout = setTimeout(() => {
      if (!settled) {
        settled = true;
        reject(new Error("Agent timed out after " + AGENT_TIMEOUT_MS + "ms"));
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
              if (toolEvent.name === "submit_recovery_insights" && toolEvent.input) {
                result = toolEvent.input as RecoveryInsightResult;
                console.log("Agent submitted recovery insights via custom tool");
              }
              break;
            }

            case "session.status_idle":
              if (result) {
                settle(() => resolve(result!));
              } else {
                settle(() => reject(new Error("Agent went idle without submitting insights")));
              }
              return;

            case "session.error": {
              const errEvent = event as { error?: { message?: string } };
              settle(() =>
                reject(new Error(`Agent session error: ${errEvent.error?.message || "unknown"}`))
              );
              return;
            }
          }
        }

        // Stream ended without idle event
        if (result) {
          settle(() => resolve(result!));
        } else {
          settle(() => reject(new Error("Agent stream ended without result")));
        }
      } catch (err) {
        settle(() => reject(err));
      }
    })();
  });
}

// ---------------------------------------------------------------------------
// Server-side validation
// ---------------------------------------------------------------------------

const VALID_TREND_DIRECTIONS = new Set(["improving", "stable", "worsening"]);

export function validateInsightResult(result: unknown): result is RecoveryInsightResult {
  if (!result || typeof result !== "object") return false;
  const r = result as Record<string, unknown>;

  // Required string fields
  if (typeof r.headline !== "string" || r.headline.length === 0) return false;
  if (typeof r.summary !== "string" || r.summary.length === 0) return false;

  // Pain analysis
  const pain = r.painAnalysis as Record<string, unknown> | undefined;
  if (!pain || typeof pain !== "object") return false;
  if (!VALID_TREND_DIRECTIONS.has(pain.trendDirection as string)) return false;
  if (typeof pain.averagePain !== "number" || pain.averagePain < 0 || pain.averagePain > 10) return false;

  // Adherence analysis
  const adherence = r.adherenceAnalysis as Record<string, unknown> | undefined;
  if (!adherence || typeof adherence !== "object") return false;
  if (typeof adherence.score !== "number" || adherence.score < 0 || adherence.score > 100) return false;

  // Arrays
  if (!Array.isArray(r.keyWins) || r.keyWins.length === 0) return false;
  if (!Array.isArray(r.focusAreas) || r.focusAreas.length === 0) return false;
  if (!Array.isArray(r.recommendations) || r.recommendations.length === 0) return false;

  return true;
}
