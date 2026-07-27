/**
 * Thin client for the `dashboardData` Cloud Function.
 *
 * Hosting rewrites `/api/dashboard` -> function `dashboardData`, so this is a
 * same-origin call and there is no CORS preflight. The ID token goes in the
 * Authorization header; the function checks it against ADMIN_EMAILS.
 *
 *   GET /api/dashboard?page=overview
 *   GET /api/dashboard?page=graphs&days=7|30|90
 *
 *   401 -> no / invalid token  -> back to the sign-in gate
 *   403 -> {"error":"not_admin"} -> "ask to be added to ADMIN_EMAILS" screen
 */

import { IS_MOCK, showScreen, setScreenMessage } from './ui.js';
import { getIdToken, signOutAndGate } from './auth.js';

const ENDPOINT = '/api/dashboard';

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message ?? `${status} ${code}`);
    this.name = 'ApiError';
    this.status = status;
    this.code = code;
  }
}

/**
 * @param {'overview'|'graphs'} page
 * @param {Record<string, string|number>} params
 * @returns {Promise<object>}
 */
export async function fetchDashboard(page, params = {}) {
  if (IS_MOCK) {
    const mock = await import('./mock-data.js');
    // A beat of latency so the "hold the frame" refetch treatment is real.
    await new Promise((resolve) => setTimeout(resolve, 120));
    return page === 'graphs' ? mock.mockGraphs(Number(params.days) || 30) : mock.mockOverview();
  }

  let token;
  try {
    token = await getIdToken();
  } catch {
    throw new ApiError(401, 'unauthenticated', 'No signed-in user');
  }

  const url = new URL(ENDPOINT, window.location.origin);
  url.searchParams.set('page', page);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
  }

  let res;
  try {
    res = await fetch(url.toString(), {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      cache: 'no-store',
    });
  } catch (err) {
    throw new ApiError(0, 'network', `Network error: ${err?.message ?? err}`);
  }

  if (res.status === 401) throw new ApiError(401, 'unauthenticated', 'Token rejected');
  if (res.status === 403) {
    const body = await res.json().catch(() => ({}));
    throw new ApiError(403, body?.error === 'not_admin' ? 'not_admin' : 'forbidden', 'Not authorised');
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new ApiError(res.status, 'server_error', `${res.status} ${res.statusText}${text ? ` — ${text.slice(0, 200)}` : ''}`);
  }

  try {
    return await res.json();
  } catch (err) {
    throw new ApiError(res.status, 'bad_json', `Malformed JSON: ${err?.message ?? err}`);
  }
}

/**
 * Route an ApiError to the right full-page screen.
 * @returns {boolean} true when the error was handled by switching screens
 *          (the caller should stop rendering), false when it is the caller's.
 */
export function handleApiError(err) {
  if (!(err instanceof ApiError)) return false;

  if (err.status === 401) {
    void signOutAndGate();
    setScreenMessage('screen-signin', 'Your session expired — sign in again.');
    return true;
  }
  if (err.status === 403) {
    showScreen('screen-denied');
    return true;
  }
  showScreen('screen-error');
  setScreenMessage('screen-error', err.message);
  return true;
}
