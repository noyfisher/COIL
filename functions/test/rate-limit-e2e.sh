#!/usr/bin/env bash
#
# Tier 2 PR B — staging dry-run for the Firestore-backed rate limiter.
#
# Fires N parallel authenticated POSTs at `claudeProxy` and reports the
# HTTP status distribution. With N=30 and the limit at 20/min, a healthy
# deploy should land exactly 20 × 200 and 10 × 429.
#
# Also measures p95 latency on a serial warm-path run (K=100 sequential
# requests, one per second well under the limit) so you can compare
# against a pre-deploy baseline — the Tier 2 PR B DoD requires staying
# within baseline + 200 ms.
#
# Usage:
#   ./test/rate-limit-e2e.sh BURST --uid=U --token=T --url=U...
#   ./test/rate-limit-e2e.sh LATENCY --uid=U --token=T --url=U...
#
# Arguments:
#   --token    Firebase ID token for a test user (get via
#              `firebase auth:export` then mint via Admin SDK, or just
#              sign in from the iOS app with `--uitesting` and copy the
#              token from the logs).
#   --url      `claudeProxy` URL for staging (NOT prod). Defaults to
#              https://us-central1-pt-helper-dev.cloudfunctions.net/claudeProxy
#   --n        Number of parallel requests for BURST (default 30).
#   --k        Number of sequential requests for LATENCY (default 100).
#   --body     Request body JSON file. Defaults to a tiny analysis request.
#
# The script does NOT automate the pre-baseline measurement — you need
# to capture that BEFORE deploying PR B, as the DoD requires comparing
# post-deploy p95 against a known pre-deploy number.
#
# WARNING: each request counts against the user's daily/monthly quota
# and costs real Claude tokens. Use a dedicated staging test account.

set -euo pipefail

MODE=${1:-}
shift || true

if [[ "$MODE" != "BURST" && "$MODE" != "LATENCY" ]]; then
  echo "Usage: $0 BURST|LATENCY --token=T [--url=U] [--n=30] [--k=100] [--body=file]" >&2
  exit 2
fi

URL="https://us-central1-pt-helper-dev.cloudfunctions.net/claudeProxy"
N=30
K=100
TOKEN=""
BODY_FILE=""

for arg in "$@"; do
  case $arg in
    --token=*) TOKEN="${arg#*=}" ;;
    --url=*)   URL="${arg#*=}" ;;
    --n=*)     N="${arg#*=}" ;;
    --k=*)     K="${arg#*=}" ;;
    --body=*)  BODY_FILE="${arg#*=}" ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if [[ -z "$TOKEN" ]]; then
  echo "Error: --token is required" >&2
  exit 2
fi

# Default request body: a minimal analysis request. Kept tiny so the
# Anthropic cost is as small as possible while still exercising the full
# claudeProxy path (auth → rate-limit → quota → Claude → schema).
if [[ -z "$BODY_FILE" ]]; then
  BODY_FILE=$(mktemp)
  trap 'rm -f "$BODY_FILE"' EXIT
  # Realistic body — the response MUST satisfy the server-side Zod schema
  # for `analysis` (non-empty `conditions` array etc.), otherwise we'd get
  # 502s and confuse a rate-limiter dry-run with a schema-validation failure.
  cat > "$BODY_FILE" <<'EOF'
{
  "requestType": "analysis",
  "messages": [
    {
      "role": "user",
      "content": "PATIENT PROFILE:\n- Age: 35\n- Sex: male\n- Activity Level: Moderate\n- Medical Conditions: None\n- Medications: None\n\nPAIN ASSESSMENT:\n- Region: Right Knee\n- Intensity: 5/10\n- Onset: 2 weeks ago\n- Aggravating: running, stairs\n- Relieving: rest, ice"
    }
  ]
}
EOF
fi

# ---------------------------------------------------------------------------
# BURST: fire N parallel requests, count 200s vs 429s.
# Expected with default limit (20/min) + N=30: 20 × 200, 10 × 429.
# ---------------------------------------------------------------------------

do_burst() {
  echo "BURST mode: $N parallel requests → $URL" >&2
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  # Use xargs for simple parallelism. `-P $N` runs all N concurrently.
  seq 1 "$N" | xargs -n1 -P "$N" -I{} bash -c '
    out=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" \
      -X POST \
      -H "Authorization: Bearer '"$TOKEN"'" \
      -H "Content-Type: application/json" \
      --data "@'"$BODY_FILE"'" \
      "'"$URL"'")
    echo "$out" > "'"$tmpdir"'/$1"
  ' _ {}

  local count_200 count_429 count_5xx count_other count_through
  # `grep -l` exits 1 when no matches; with `set -euo pipefail` that would
  # kill the script before the report. Force success via `|| true`.
  count_200=$( (grep -l '^200 ' "$tmpdir"/* 2>/dev/null || true) | wc -l | tr -d ' ')
  count_429=$( (grep -l '^429 ' "$tmpdir"/* 2>/dev/null || true) | wc -l | tr -d ' ')
  count_5xx=$( (grep -lE '^5[0-9][0-9] ' "$tmpdir"/* 2>/dev/null || true) | wc -l | tr -d ' ')
  count_other=$(( N - count_200 - count_429 - count_5xx ))
  # "through" = anything not gated by the rate limiter. The rate limiter's
  # job is to reject ~10 of 30; the disposition of the other ~20 is a
  # downstream concern (Claude flake, schema validation, etc.).
  count_through=$(( count_200 + count_5xx ))

  echo ""
  echo "=== BURST result ==="
  echo "  HTTP 200 (allowed, succeeded)         : $count_200"
  echo "  HTTP 5xx (allowed, downstream failed) : $count_5xx"
  echo "  HTTP 429 (rate-limited)               : $count_429"
  echo "  Other                                 : $count_other"
  echo "  → THROUGH limiter (200+5xx)           : $count_through"
  echo ""
  if [[ "$count_through" -ge 18 && "$count_through" -le 22 && "$count_429" -ge 8 ]]; then
    echo "PASS: rate limiter respected — let through $count_through (target 20 ±2),"
    echo "      rejected $count_429 (target ≥ 8)."
    if [[ "$count_5xx" -gt 0 ]]; then
      echo "NOTE: $count_5xx of the allowed requests failed downstream (schema or Claude)."
      echo "      That is unrelated to the rate limiter; investigate separately if needed."
    fi
  else
    echo "FAIL: through=$count_through, 429=$count_429. Expected through≈20 ±2 / 429≥8."
    return 1
  fi
}

# ---------------------------------------------------------------------------
# LATENCY: K sequential requests spaced 3s apart (to stay well under
# the 20/min limit). Reports p50 / p95 / p99 in milliseconds.
# ---------------------------------------------------------------------------

do_latency() {
  echo "LATENCY mode: $K sequential requests (3s spacing) → $URL" >&2
  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN

  for i in $(seq 1 "$K"); do
    code_and_time=$(curl -s -o /dev/null -w "%{http_code} %{time_total}" \
      -X POST \
      -H "Authorization: Bearer $TOKEN" \
      -H "Content-Type: application/json" \
      --data "@$BODY_FILE" \
      "$URL" || true)
    echo "$code_and_time" >> "$tmpfile"
    printf "  %d/%d  %s\n" "$i" "$K" "$code_and_time" >&2
    sleep 3
  done

  # Extract time_total (seconds), convert to ms, compute p50/p95/p99.
  awk '{print $2 * 1000}' "$tmpfile" | sort -n | awk -v k="$K" '
  {
    arr[NR] = $1
  }
  END {
    p50_idx = int(NR * 0.50 + 0.5); if (p50_idx < 1) p50_idx = 1
    p95_idx = int(NR * 0.95 + 0.5); if (p95_idx < 1) p95_idx = 1
    p99_idx = int(NR * 0.99 + 0.5); if (p99_idx < 1) p99_idx = 1
    printf "\n=== LATENCY result (%d samples) ===\n", NR
    printf "  p50: %.0f ms\n", arr[p50_idx]
    printf "  p95: %.0f ms\n", arr[p95_idx]
    printf "  p99: %.0f ms\n", arr[p99_idx]
    printf "\nCompare p95 against your pre-PR-B baseline. DoD: stay within baseline + 200 ms.\n"
  }'
}

case "$MODE" in
  BURST)   do_burst ;;
  LATENCY) do_latency ;;
esac
