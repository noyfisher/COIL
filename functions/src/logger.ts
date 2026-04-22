/**
 * Structured request-scoped logger for Cloud Functions.
 *
 * Emits JSON-structured events to Cloud Logging via firebase-functions'
 * logger so they become queryable / alertable (vs. unstructured console.log).
 *
 * Intended usage on an HTTP handler:
 *   const ctx = newRequestContext("claudeProxy");
 *   ctx.uid = uid;
 *   // ... do work ...
 *   logCompleted(ctx, 200, { requestType, tokensIn, tokensOut });
 *
 * On error paths, call `logError(ctx, err, { extra })` before responding.
 *
 * Every log carries: requestId (random 8 chars), functionName, uid (if set),
 * durationMs (from ctx creation to log emission). Caller-supplied `extra`
 * fields are merged into the top level so they're directly filterable in
 * Cloud Logging (avoid nesting).
 */

import * as functions from "firebase-functions/v1";

export interface RequestContext {
  requestId: string;
  functionName: string;
  uid?: string;
  startedAt: number;
  /**
   * Bag for late-bound fields (e.g. requestType once parsed, tokenCounts
   * after Claude responds). Merged into every log emitted for this context.
   */
  metadata: Record<string, unknown>;
}

function randomId(): string {
  return Math.random().toString(36).slice(2, 10);
}

export function newRequestContext(functionName: string, uid?: string): RequestContext {
  return {
    requestId: randomId(),
    functionName,
    uid,
    startedAt: Date.now(),
    metadata: {},
  };
}

function baseFields(ctx: RequestContext): Record<string, unknown> {
  return {
    requestId: ctx.requestId,
    functionName: ctx.functionName,
    uid: ctx.uid,
    durationMs: Date.now() - ctx.startedAt,
    ...ctx.metadata,
  };
}

export function logCompleted(
  ctx: RequestContext,
  status: number,
  extra: Record<string, unknown> = {},
): void {
  functions.logger.info("request_completed", {
    ...baseFields(ctx),
    status,
    ...extra,
  });
}

export function logError(
  ctx: RequestContext,
  error: unknown,
  extra: Record<string, unknown> = {},
): void {
  functions.logger.error("request_error", {
    ...baseFields(ctx),
    errorMessage: error instanceof Error ? error.message : String(error),
    errorStack: error instanceof Error ? error.stack : undefined,
    ...extra,
  });
}

/**
 * For warnings that aren't full errors (e.g. upstream retries, fallbacks).
 */
export function logWarn(
  ctx: RequestContext,
  message: string,
  extra: Record<string, unknown> = {},
): void {
  functions.logger.warn(message, {
    ...baseFields(ctx),
    ...extra,
  });
}
