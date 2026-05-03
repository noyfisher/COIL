#!/usr/bin/env python3
"""
Tier 2 PR C-1 — generate a draft knowledge-graph expansion via Claude Haiku.

For every (condition, exercise) pair in the seed lists, asks Claude
whether the exercise is "safe", "contraindicated", or "unclear" for that
condition. Batches 10 pairs per call, uses prompt caching on the static
prefix (~60-70% input-cost savings), and writes one row per verdict to
`scripts/output/knowledge_graph_v2_draft.json`.

The output is a DRAFT — every `contraindicated` verdict + a 10% sample of
`safe` verdicts MUST be reviewed by a clinician (or in-house dev as
fallback) via `scripts/review_kg_candidates.py` BEFORE the file is
promoted to the iOS bundle.

Resilience (addresses MEMORY.md known-failure modes):
  * SIGALRM 90s timeout per Anthropic call
  * 429 / PROHIBITED_CONTENT → exponential backoff + skip to next batch,
    logged to scripts/output/kg_failed_pairs.json
  * Checkpoint every 50 batches to scripts/output/kg_progress.json,
    resume on re-run by loading already-completed pair set
  * Partial-array recovery: per-object try/except so a truncated trailing
    object doesn't lose the whole batch
  * No-schema fallback parse + `_normalize_kg_keys()` (variant key names
    → canonical schema)

Usage:
  # Use defaults (v1 conditions + top-200 exercises from stockpile metadata)
  ANTHROPIC_API_KEY=... python scripts/expand_knowledge_graph.py

  # Limit scope for a smoke test
  ANTHROPIC_API_KEY=... python scripts/expand_knowledge_graph.py --max-conditions 5 --max-exercises 10

  # Resume from existing progress checkpoint
  ANTHROPIC_API_KEY=... python scripts/expand_knowledge_graph.py --resume

  # Use custom seed lists
  ANTHROPIC_API_KEY=... python scripts/expand_knowledge_graph.py \
      --conditions-file path/to/conditions.txt \
      --exercises-file path/to/exercises.txt

API cost estimate: ~1000 calls × ~3K input + ~500 output tokens at Haiku
4.5 pricing ≈ $3-15 depending on cache hit rate.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

try:
    from anthropic import Anthropic
except ImportError:
    print(
        "ERROR: anthropic SDK not installed. Run:\n"
        "  pip install anthropic\n",
        file=sys.stderr,
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent
KG_V1_PATH = REPO_ROOT / "ios/PT-Helper/PT-Helper/Resources/medical_knowledge_graph.json"
EXERCISE_METADATA_PATH = REPO_ROOT / "scripts/output/all_exercises_metadata.json"
OUTPUT_DIR = REPO_ROOT / "scripts/output"
DRAFT_OUTPUT = OUTPUT_DIR / "knowledge_graph_v2_draft.json"
PROGRESS_FILE = OUTPUT_DIR / "kg_progress.json"
FAILED_PAIRS_FILE = OUTPUT_DIR / "kg_failed_pairs.json"

MODEL = "claude-haiku-4-5-20251001"
PAIRS_PER_BATCH = 10
CALL_TIMEOUT_SECONDS = 90
CHECKPOINT_EVERY_BATCHES = 50
MAX_RETRIES_429 = 3
RETRY_BACKOFF_SECONDS = [5, 15, 45]


# ---------------------------------------------------------------------------
# Prompt construction (cached static prefix)
# ---------------------------------------------------------------------------

# The static prefix is what gets cached. It's the most expensive part
# (~2-3K tokens) and runs identically on every call. Anthropic caches
# it for 5 minutes; at our throughput we hit the cache for nearly every
# call after the first.
SYSTEM_PROMPT = """You are a licensed Doctor of Physical Therapy reviewing exercise contraindications for a clinical safety database.

For each (condition, exercise) pair given by the user, decide whether the exercise is:
  - "safe": appropriate as part of a typical rehab progression for this condition
  - "contraindicated": likely to aggravate the condition or create injury risk
  - "unclear": context-dependent (depends on phase of recovery, severity, modifications) — when uncertain, choose this rather than guessing

YOU MUST follow these rules:
  1. Be conservative on contraindications. Only mark "contraindicated" when there is a clear biomechanical or clinical reason (e.g. high-impact for osteoporosis, deep flexion under load for herniated disc, valsalva for uncontrolled hypertension).
  2. The reason must be one short sentence (max 100 chars) describing the mechanism — NOT generic advice.
  3. contraindication_severity: "absolute" (never appropriate), "relative" (avoid in most cases but possible with modification), or null for safe/unclear.

Few-shot examples:

INPUT: [{"condition_id":"osteoporosis","exercise_id":"jump-squat"}]
OUTPUT: [{"condition_id":"osteoporosis","exercise_id":"jump-squat","verdict":"contraindicated","reason":"High-impact landing creates vertebral compression load above bone-density safety threshold.","contraindication_severity":"absolute"}]

INPUT: [{"condition_id":"patellofemoral-pain-syndrome","exercise_id":"quad-sets"}]
OUTPUT: [{"condition_id":"patellofemoral-pain-syndrome","exercise_id":"quad-sets","verdict":"safe","reason":"Isometric quad activation without joint loading; standard early-stage PFPS exercise.","contraindication_severity":null}]

INPUT: [{"condition_id":"rotator-cuff-tear","exercise_id":"pendulum-swings"}]
OUTPUT: [{"condition_id":"rotator-cuff-tear","exercise_id":"pendulum-swings","verdict":"unclear","reason":"Appropriate for grade 1-2; should be cleared by treating PT for grade 3 or post-op.","contraindication_severity":null}]

RESPONSE FORMAT: respond with ONLY a valid JSON array of verdicts in the exact order of input pairs. No markdown, no preamble. Each entry MUST have all 5 fields: condition_id, exercise_id, verdict, reason, contraindication_severity."""


def build_user_message(pairs: list[tuple[str, str]]) -> str:
    """One per-batch payload. Just the pair list — system prompt is cached."""
    payload = [
        {"condition_id": cond, "exercise_id": ex}
        for (cond, ex) in pairs
    ]
    return json.dumps(payload, ensure_ascii=False)


# ---------------------------------------------------------------------------
# Output schema + key normalization
# ---------------------------------------------------------------------------

CANONICAL_KEYS = {
    "condition_id",
    "exercise_id",
    "verdict",
    "reason",
    "contraindication_severity",
}

# Variants Haiku has been observed to emit. Map → canonical.
KEY_VARIANT_MAP = {
    "conditionId": "condition_id",
    "condition": "condition_id",
    "exerciseId": "exercise_id",
    "exercise": "exercise_id",
    "tier": "verdict",
    "classification": "verdict",
    "explanation": "reason",
    "rationale": "reason",
    "severity": "contraindication_severity",
    "contraindicationSeverity": "contraindication_severity",
}


def _normalize_kg_keys(obj: dict[str, Any]) -> dict[str, Any]:
    """Map common variant keys to the canonical schema.

    Direction is variant → canonical (NEVER the reverse). Required by the
    Tier 2 plan; if Haiku emits "verdict" correctly we leave it alone, but
    if it emits "tier" we rewrite to "verdict".
    """
    return {KEY_VARIANT_MAP.get(k, k): v for k, v in obj.items()}


# ---------------------------------------------------------------------------
# SIGALRM timeout
# ---------------------------------------------------------------------------


class CallTimeout(Exception):
    pass


def _timeout_handler(signum, frame):
    raise CallTimeout(f"Anthropic call exceeded {CALL_TIMEOUT_SECONDS}s")


def call_with_timeout(fn, *args, **kwargs):
    """Run fn under a SIGALRM timeout. Anthropic calls have been observed
    to hang indefinitely on certain inputs (see MEMORY.md)."""
    old_handler = signal.signal(signal.SIGALRM, _timeout_handler)
    signal.alarm(CALL_TIMEOUT_SECONDS)
    try:
        return fn(*args, **kwargs)
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)


# ---------------------------------------------------------------------------
# Seed loading
# ---------------------------------------------------------------------------

DEFAULT_FALLBACK_CONDITIONS = [
    # Backstop set if v1 graph is missing — keep alphabetized for review.
    "achilles-tendinitis", "acl-sprain", "ankle-sprain", "carpal-tunnel-syndrome",
    "cervical-radiculopathy", "frozen-shoulder", "golfers-elbow", "hamstring-strain",
    "herniated-disc", "hip-bursitis", "il-tibial-band-syndrome", "lower-back-strain",
    "meniscus-tear", "osteoarthritis-knee", "osteoporosis", "patellofemoral-pain-syndrome",
    "plantar-fasciitis", "rotator-cuff-tear", "sciatica", "shin-splints",
    "shoulder-impingement", "tennis-elbow", "thoracic-outlet-syndrome",
    "trochanteric-bursitis", "whiplash",
]


def load_seed_conditions(path: Path | None, max_n: int | None) -> list[str]:
    if path:
        ids = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    elif KG_V1_PATH.exists():
        v1 = json.loads(KG_V1_PATH.read_text())
        ids = sorted(v1.get("conditions", {}).keys())
    else:
        ids = list(DEFAULT_FALLBACK_CONDITIONS)
    if max_n is not None:
        ids = ids[:max_n]
    return ids


def load_seed_exercises(path: Path | None, max_n: int | None) -> list[str]:
    if path:
        ids = [line.strip() for line in path.read_text().splitlines() if line.strip()]
    elif EXERCISE_METADATA_PATH.exists():
        data = json.loads(EXERCISE_METADATA_PATH.read_text())
        # Production shape: {"exercises": [{"normalized_filename": "...", ...}, ...]}.
        # Tolerate flat-dict and bare-list shapes too.
        items: list[dict[str, Any]] = []
        ids = []
        if isinstance(data, dict):
            if "exercises" in data and isinstance(data["exercises"], list):
                items = [it for it in data["exercises"] if isinstance(it, dict)]
            else:
                ids = sorted(data.keys())
        elif isinstance(data, list):
            items = [it for it in data if isinstance(it, dict)]
        if items and not ids:
            ids = sorted(
                {
                    str(item.get("normalized_filename") or item.get("id") or item.get("name") or "").strip()
                    for item in items
                }
                - {""}
            )
    else:
        # Fall back to whatever exercises are referenced in the v1 KG.
        ids = []
        if KG_V1_PATH.exists():
            v1 = json.loads(KG_V1_PATH.read_text())
            seen: set[str] = set()
            for cond in v1.get("conditions", {}).values():
                seen.update(cond.get("safeExercises", []))
                seen.update(cond.get("unsafeExercises", []))
            ids = sorted(seen)
    if max_n is not None:
        ids = ids[:max_n]
    return ids


# ---------------------------------------------------------------------------
# Checkpointing
# ---------------------------------------------------------------------------

@dataclass
class Progress:
    completed_pair_keys: set[str] = field(default_factory=set)
    verdicts: list[dict[str, Any]] = field(default_factory=list)
    failed_pairs: list[dict[str, Any]] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {
            "completed_pair_keys": sorted(self.completed_pair_keys),
            "verdicts": self.verdicts,
            "failed_pairs": self.failed_pairs,
        }

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Progress:
        return cls(
            completed_pair_keys=set(data.get("completed_pair_keys", [])),
            verdicts=list(data.get("verdicts", [])),
            failed_pairs=list(data.get("failed_pairs", [])),
        )


def pair_key(cond: str, ex: str) -> str:
    return f"{cond}|{ex}"


def load_progress() -> Progress:
    if PROGRESS_FILE.exists():
        try:
            return Progress.from_json(json.loads(PROGRESS_FILE.read_text()))
        except Exception as e:
            print(f"WARNING: progress checkpoint unreadable, starting fresh: {e}", file=sys.stderr)
    return Progress()


def save_progress(progress: Progress) -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    PROGRESS_FILE.write_text(json.dumps(progress.to_json(), indent=2))


# ---------------------------------------------------------------------------
# Batched generation
# ---------------------------------------------------------------------------

def chunked(iterable: Iterable, n: int):
    buf = []
    for item in iterable:
        buf.append(item)
        if len(buf) == n:
            yield buf
            buf = []
    if buf:
        yield buf


def parse_response_text(text: str, expected_pairs: list[tuple[str, str]]) -> list[dict[str, Any]]:
    """Parse Haiku's response into a list of canonical-keyed verdict dicts.

    Resilience layers:
      - Strip markdown fences if present
      - Try strict JSON parse
      - On failure: per-object try/except on the array (mid-object truncation
        recovery)
      - Always normalize keys (variant → canonical)
      - Drop entries missing required fields after normalization
    """
    cleaned = text.strip()
    # Strip ```json ... ``` if present
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned.rsplit("```", 1)[0]
    cleaned = cleaned.strip()

    raw_objects: list[dict[str, Any]] = []
    try:
        parsed = json.loads(cleaned)
        if isinstance(parsed, list):
            raw_objects = [obj for obj in parsed if isinstance(obj, dict)]
        elif isinstance(parsed, dict):
            raw_objects = [parsed]
    except json.JSONDecodeError:
        # Partial-array recovery: walk the text, extract balanced { ... }
        # objects one at a time, parse each, skip ones that fail.
        depth = 0
        start = -1
        for i, ch in enumerate(cleaned):
            if ch == "{":
                if depth == 0:
                    start = i
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0 and start >= 0:
                    chunk = cleaned[start : i + 1]
                    try:
                        obj = json.loads(chunk)
                        if isinstance(obj, dict):
                            raw_objects.append(obj)
                    except json.JSONDecodeError:
                        pass
                    start = -1

    normalized: list[dict[str, Any]] = []
    for obj in raw_objects:
        canonical = _normalize_kg_keys(obj)
        # Require the 4 most important fields. severity may be null.
        if not all(k in canonical for k in ("condition_id", "exercise_id", "verdict", "reason")):
            continue
        if canonical.get("verdict") not in ("safe", "contraindicated", "unclear"):
            continue
        # Default missing severity to null.
        canonical.setdefault("contraindication_severity", None)
        normalized.append(canonical)

    return normalized


def request_batch_verdicts(
    client: Anthropic,
    pairs: list[tuple[str, str]],
) -> list[dict[str, Any]]:
    """One Anthropic call. Returns parsed verdicts. Raises on auth / 4xx /
    persistent timeouts; transient 429 is retried internally."""
    user_message = build_user_message(pairs)

    last_exc: Exception | None = None
    for attempt in range(MAX_RETRIES_429):
        try:
            def do_call():
                return client.messages.create(
                    model=MODEL,
                    max_tokens=2048,
                    temperature=0.2,
                    system=[
                        {
                            "type": "text",
                            "text": SYSTEM_PROMPT,
                            "cache_control": {"type": "ephemeral"},
                        }
                    ],
                    messages=[{"role": "user", "content": user_message}],
                )

            response = call_with_timeout(do_call)
            text_blocks = [b.text for b in response.content if hasattr(b, "text")]
            if not text_blocks:
                raise RuntimeError("Empty response from Haiku")
            return parse_response_text(text_blocks[0], pairs)

        except CallTimeout as e:
            last_exc = e
            print(f"  TIMEOUT on attempt {attempt + 1}: {e}", file=sys.stderr)
        except Exception as e:
            msg = str(e).lower()
            if "rate" in msg or "429" in msg or "overloaded" in msg:
                last_exc = e
                wait = RETRY_BACKOFF_SECONDS[min(attempt, len(RETRY_BACKOFF_SECONDS) - 1)]
                print(f"  RATE LIMIT / OVERLOAD on attempt {attempt + 1}: backing off {wait}s", file=sys.stderr)
                time.sleep(wait)
                continue
            if "prohibited_content" in msg or "blocked" in msg:
                # Don't retry — the input itself triggered the safety filter.
                raise
            # Other errors: retry with backoff
            last_exc = e
            wait = RETRY_BACKOFF_SECONDS[min(attempt, len(RETRY_BACKOFF_SECONDS) - 1)]
            print(f"  ERROR on attempt {attempt + 1} ({type(e).__name__}: {e}): backing off {wait}s", file=sys.stderr)
            time.sleep(wait)

    raise RuntimeError(f"All {MAX_RETRIES_429} attempts failed; last error: {last_exc}")


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Generate KG v2 draft via Claude Haiku")
    parser.add_argument("--max-conditions", type=int, default=None, help="Limit conditions for smoke test")
    parser.add_argument("--max-exercises", type=int, default=None, help="Limit exercises for smoke test")
    parser.add_argument("--conditions-file", type=Path, default=None, help="Custom condition seed file (one ID per line)")
    parser.add_argument("--exercises-file", type=Path, default=None, help="Custom exercise seed file (one ID per line)")
    parser.add_argument("--resume", action="store_true", help="Resume from kg_progress.json")
    parser.add_argument("--dry-run", action="store_true", help="Print pair count + estimated cost, don't call API")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key and not args.dry_run:
        print("ERROR: set ANTHROPIC_API_KEY env var", file=sys.stderr)
        sys.exit(1)

    conditions = load_seed_conditions(args.conditions_file, args.max_conditions)
    exercises = load_seed_exercises(args.exercises_file, args.max_exercises)
    print(f"Seeds: {len(conditions)} conditions × {len(exercises)} exercises = {len(conditions) * len(exercises)} pairs")
    if not conditions or not exercises:
        print("ERROR: empty seed list — check --conditions-file / --exercises-file", file=sys.stderr)
        sys.exit(2)

    all_pairs = [(c, e) for c in conditions for e in exercises]

    progress = load_progress() if args.resume else Progress()
    if args.resume:
        print(f"Resuming: {len(progress.completed_pair_keys)} pairs already done, {len(progress.verdicts)} verdicts on file")

    pending = [
        (c, e) for (c, e) in all_pairs
        if pair_key(c, e) not in progress.completed_pair_keys
    ]
    print(f"Pending: {len(pending)} pairs in {(len(pending) + PAIRS_PER_BATCH - 1) // PAIRS_PER_BATCH} batches")

    if args.dry_run:
        # Rough Haiku 4.5 pricing (per Anthropic docs as of plan-write):
        # input ~$1/MTok cached, ~$4/MTok uncached; output ~$5/MTok.
        # Assume 3K cached tokens prefix, 200 input tokens per pair, 50 output per pair.
        n_batches = (len(pending) + PAIRS_PER_BATCH - 1) // PAIRS_PER_BATCH
        cached_in_cost = (n_batches * 3000 * 1) / 1_000_000  # cache hits cost ~25% of full
        var_in_cost = (len(pending) * 200 * 4) / 1_000_000
        out_cost = (len(pending) * 50 * 5) / 1_000_000
        first_call_overhead = 3000 * 4 / 1_000_000  # first call writes cache at full cost
        total = cached_in_cost + var_in_cost + out_cost + first_call_overhead
        print(f"\nEstimated cost: ~${total:.2f} (very rough)")
        print(f"  - {n_batches} batches × ~3K cached prefix tokens")
        print(f"  - {len(pending)} pairs × ~200 variable input tokens")
        print(f"  - {len(pending)} pairs × ~50 output tokens")
        return

    client = Anthropic(api_key=api_key)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    batches = list(chunked(pending, PAIRS_PER_BATCH))
    started_at = time.time()

    for batch_index, batch in enumerate(batches, start=1):
        try:
            print(f"\nBatch {batch_index}/{len(batches)} ({len(batch)} pairs) — {batch[0][0]}/{batch[0][1]}…")
            verdicts = request_batch_verdicts(client, batch)
            print(f"  Got {len(verdicts)} verdicts")

            # Mark all pairs in the batch as completed (even if a few weren't
            # returned — they're not retried automatically; they go to
            # failed_pairs so a follow-up run can target them).
            returned_keys = {pair_key(v["condition_id"], v["exercise_id"]) for v in verdicts}
            for cond, ex in batch:
                progress.completed_pair_keys.add(pair_key(cond, ex))
                if pair_key(cond, ex) not in returned_keys:
                    progress.failed_pairs.append({
                        "condition_id": cond,
                        "exercise_id": ex,
                        "reason": "missing_from_response",
                    })
            progress.verdicts.extend(verdicts)
        except Exception as e:
            # Whole-batch failure — log every pair, advance.
            print(f"  BATCH FAILED: {e}", file=sys.stderr)
            for cond, ex in batch:
                progress.completed_pair_keys.add(pair_key(cond, ex))
                progress.failed_pairs.append({
                    "condition_id": cond,
                    "exercise_id": ex,
                    "reason": f"batch_error: {type(e).__name__}: {str(e)[:200]}",
                })

        # Checkpoint
        if batch_index % CHECKPOINT_EVERY_BATCHES == 0:
            save_progress(progress)
            elapsed = time.time() - started_at
            print(f"  ✓ Checkpoint at batch {batch_index} ({len(progress.verdicts)} verdicts, {len(progress.failed_pairs)} failed, {elapsed:.0f}s elapsed)")

    # Final save
    save_progress(progress)

    # Write final draft outputs
    DRAFT_OUTPUT.write_text(json.dumps({
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "model": MODEL,
        "verdict_count": len(progress.verdicts),
        "verdicts": progress.verdicts,
    }, indent=2))
    FAILED_PAIRS_FILE.write_text(json.dumps(progress.failed_pairs, indent=2))

    elapsed = time.time() - started_at
    print(f"\n=== Done in {elapsed:.0f}s ===")
    print(f"  Verdicts:     {len(progress.verdicts)}")
    print(f"  Failed pairs: {len(progress.failed_pairs)}")
    print(f"  Draft:        {DRAFT_OUTPUT}")
    print(f"  Failures:     {FAILED_PAIRS_FILE}")
    print("\nNext step: review verdicts via")
    print("  python scripts/review_kg_candidates.py")


if __name__ == "__main__":
    main()
