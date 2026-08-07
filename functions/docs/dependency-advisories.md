# Cloud Functions — Dependency Advisory Register

Tracks the state of `npm audit --omit=dev` (production/runtime dependencies) for the
Cloud Functions package, and records any **accepted residual** advisories with their
reachability rationale and compensating controls.

The CI job **"Cloud Functions (build, test, audit)"** in `.github/workflows/ci.yml`
fails the build on any **HIGH** or **CRITICAL** runtime advisory
(`npm audit --omit=dev --audit-level=high`). MODERATE advisories are allowed through
only when listed as an accepted residual below.

## Current state (PR-5, in-range fix — P1-06)

`npm audit fix --omit=dev` (non-`--force`, no major bumps) reduced the runtime advisory
count from **24 (2 critical, 7 high, 14 moderate, 1 low)** to **9 (all moderate)**.
`firebase-admin` stays at v12 and `@anthropic-ai/sdk` at ^0.88 — no breaking bumps.
Build clean, full jest suite green (93 tests).

### Cleared (0 remaining)
- **Critical:** `protobufjs` (RCE + parsing/prototype/DoS chain), `websocket-driver` (resource-limit bypass / message corruption).
- **High:** `@grpc/grpc-js`, `axios` (SSRF/prototype-pollution/DoS set), `brace-expansion`, `fast-xml-parser`, `form-data`, `node-forge`, `path-to-regexp`.
- **Low:** `@tootallnate/once`.

These were all resolved in-range (`package-lock.json` only). No `overrides` were added:
a plain `npm audit fix` reached every critical/high advisory, and the patched versions
are the newest-in-range, so a fresh resolve keeps them. The CI advisory gate is the
durable backstop against any regression.

### 2026-08-06 — `brace-expansion` returned, fixed in-range again

The gate caught a **second** high on the same package, published after the PR-5 sweep:
GHSA-rgw5-rvv9-x895 (CVSS 7.5), which bypasses the CVE-2026-14257 mitigation that the
first fix relied on, plus GHSA-mh99-v99m-4gvg. Reached transitively via
`@google-cloud/billing → google-gax → rimraf → glob → minimatch`.

Fixed with `npm update brace-expansion` (2.1.2 → 2.1.4); `minimatch` declares
`^2.0.2`, so this is in-range and lockfile-only. Build clean, 291 tests green.

This is the gate working as designed — the advisory set drifts over time even when
the lockfile does not, so a previously-cleared package can go red again without any
dependency change on our side.

## Accepted residuals (9 moderate)

| Package | Advisory | Fix requires | Accepted because |
|---|---|---|---|
| `@anthropic-ai/sdk` | Insecure default file permissions in the **Local Filesystem Memory Tool** | `@anthropic-ai/sdk@0.112.5` (semver-major, 0.88→0.112 across 24 pre-1.0 minors) | **Unreachable** — this app never uses the memory tool. The SDK is used only for `client.beta.sessions/agents/environments.*` (managed-agent recovery-insights + form-analysis). Bumping 24 beta-API minors risks breaking those features with no security benefit. Revisit when we next touch the managed-agent SDK surface. |
| `uuid` | Missing buffer bounds check in v3/v5/v6 **when `buf` is provided** | `firebase-admin@14.2.0` (semver-major) | **Unreachable** — the vulnerable path only triggers when a caller passes a `buf` argument; Firebase's internal uuid usage does not. |
| `@google-cloud/firestore` | (via `google-gax` → `uuid`) | `firebase-admin@14.2.0` | Transitive root is the unreachable `uuid` bug above. |
| `@google-cloud/storage` | (via `retry-request` / `teeny-request` → `uuid`) | `firebase-admin@14.2.0` | Same `uuid` root. |
| `firebase-admin` | (via `@google-cloud/firestore` / `@google-cloud/storage` / `uuid`) | `firebase-admin@14.2.0` | Same `uuid` root. |
| `gaxios` | (via `uuid`) | in-range but gated by the `uuid` chain | Same `uuid` root. |
| `google-gax` | (via `retry-request` / `uuid`) | `firebase-admin@14.2.0` | Same `uuid` root. |
| `retry-request` | (via `teeny-request` → `uuid`) | `firebase-admin@14.2.0` | Same `uuid` root. |
| `teeny-request` | (via `uuid`) | `firebase-admin@14.2.0` | Same `uuid` root. |

**Root cause:** 8 of the 9 residuals collapse to a single unreachable `uuid` bounds-check
advisory reached through the `firebase-admin` → `@google-cloud/*` → `google-gax` →
`teeny-request`/`retry-request` dependency chain. `firebase-functions@7.2.2`'s peer
`firebase-admin` range (`^11 || ^12 || ^13`) excludes admin v14, so the only fix
(`firebase-admin@14.2.0`) forces both a `firebase-functions` major bump **and** a
~50-call-site migration off the removed legacy namespace API.

### Compensating control / follow-up
The **firebase-admin v14 modernization** is tracked as a standalone, non-security-gating
follow-up (see the deferred section of the remediation plan). Doing it clears all 8
`uuid`-chain moderates at once. Until then, the CI gate holds the line at high/critical,
and this register documents why the moderates are safe to carry.

## Re-audit checklist (run before each release)
1. `cd functions && npm audit --omit=dev` — confirm 0 high/critical.
2. Any **new** high/critical must be fixed (in-range) or explicitly accepted here before release.
3. If the residual count changes, update the table above and the totals.
