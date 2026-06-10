# Virtual Users

Synthetic users that sign into the **real app** (production code path: Firebase Auth,
Firestore writes, SessionLogger, Analytics) to verify logging/tracking coverage and
chart rendering against seeded ground truth.

## Run protocol

1. Mint a token: `VIRTUAL_USER_ID=vuser-<persona> node virtual-users/mint_app_token.js`
   (requires gcloud ADC with Service Account Token Creator on the Admin SDK SA).
2. Seed (veteran persona only): `node virtual-users/seed_vuser_data.js`, then `--verify`.
3. Launch the simulator app with `--virtual-user-token <token>` (DEBUG builds only;
   takes precedence over `--uitesting`). Confirm `[VirtualUser] signed in as <uid>`
   in the runtime log before driving.
4. Drive the persona journey (`personas/*.json`), recording a ground-truth JSON of
   actions + expected events under `results/<date>/<vuser-id>/`.
5. Validate: `node virtual-users/validator/validate.js` → findings into
   `results/<date>/validation-report.md`. Firebase Analytics (BigQuery) checks run
   next-day (GA4 export lags up to 24h).
6. Cleanup: `node virtual-users/seed_vuser_data.js --cleanup` — deletes ALL `vuser-*`
   Firestore trees, sessionLogs, Storage trails, rateLimits, and Auth records so
   `aggregateDailyMetrics` / the nightly report stay clean.
   **Then neutralize the simulator too**, or later launches (e.g. test hosts) will
   re-upload leftover trails and re-create Auth records (observed 2026-06-09):
   ```
   xcrun simctl terminate <udid> com.noyfisher.pthelper
   find "$(xcrun simctl get_app_container <udid> com.noyfisher.pthelper data)" \
     -name "session_log_*.json" -delete
   xcrun simctl uninstall <udid> com.noyfisher.pthelper   # clears keychain vuser session
   ```
   Re-run `--verify` afterwards to confirm zero vuser docs.

## Bug classification rule

**A behavior may be classified as a BUG finding only after it has been reproduced
twice** — two independent occurrences (separate attempts, ideally from fresh app
state). Until then it is recorded as **ANOMALY (unconfirmed, 1/2 repros)** with
exact repro steps, and the next run must attempt reproduction before promoting it.

Rationale: UI automation introduces its own failure modes (missed taps, stale
accessibility trees, races with animations). One observation can't distinguish an
app bug from a driver artifact; two reproductions with documented steps can.

Applied to the 2026-06-09 run (rule adopted afterwards):
- F1 Generate Plan freeze — reproduced 2/2 → BUG (qualifies).
- F5 dead tap zones — reproduced repeatedly within the run → BUG (qualifies).
- F6 carousel xmark unreachable — 2 failed taps → BUG (qualifies, borderline).
- F2 analysis unreachable after relaunch — observed once → **downgrade to ANOMALY**;
  next run must reproduce before treating as a bug.
- F7 workout summary 0 Completed/0 Skipped — observed once → already labeled ANOMALY;
  stays unconfirmed until reproduced.

Findings that are *measurements* rather than behaviors (e.g. F3 upload-trigger gap,
F4 missing screen tracking) are verified by reading code + observed data, not by
reproduction counts — the rule does not apply to those.

## Files

- `mint_app_token.js` — mint a Firebase custom token for app sign-in
- `seed_vuser_data.js` — seed veteran data / `--cleanup` / `--verify`
- `validator/validate.js` — Firestore + Storage-trail validation vs persona expectations
- `personas/` — journey specs and per-persona expectations
- `results/<date>/` — ground truth, screenshots, evidence, validation report
