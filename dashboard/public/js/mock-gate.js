/**
 * Where fixture mode is allowed to run.
 *
 * `?mock=1` short-circuits authentication and serves fixtures (js/mock-data.js),
 * so it is gated to local hosts. On a deployed origin the flag is ignored
 * outright: a real dashboard URL must never render fabricated operational data,
 * however clearly the mock badge labels it.
 *
 * This lives in its own module — rather than in ui.js, where it is consumed —
 * because ui.js touches `window` at module scope and so cannot be imported by a
 * node test. Keeping the predicate pure is what makes the NEGATIVE case
 * testable at all: it cannot be reproduced in a browser locally, since the
 * Firebase emulator serves on `localhost`, which is precisely the allowed host.
 *
 * Same rationale as sankey-utils.js. Tests: dashboard/test/mock-gate.test.mjs
 */

/** Local development and the Firebase emulator. `''` covers `file://`. */
const LOCAL_HOSTS = ['localhost', '127.0.0.1', '::1', ''];

/**
 * @param {string} hostname - `window.location.hostname`
 * @param {string} search   - `window.location.search`
 * @returns {boolean} true only on a local host WITH `mock=1` present.
 */
export function isMockAllowed(hostname, search) {
  // IPv6 literals arrive bracketed from location.hostname ("[::1]").
  const host = String(hostname ?? '').replace(/^\[|\]$/g, '');
  if (!LOCAL_HOSTS.includes(host)) return false;
  return new URLSearchParams(search ?? '').get('mock') === '1';
}
