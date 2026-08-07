#!/usr/bin/env python3
"""
Tier 3B — confidence-cap recalibration analysis.

Tier 1 hardcoded `ConfidenceCalibrator.maxDisplayConfidence = 85` based
on a literature heuristic ("expert doctors are ~70-80% accurate"). Once
we've collected enough outcome ratings via the OutcomeRecorder
infrastructure (Tier 3 PR D), we can replace that heuristic with an
empirically-fit cap.

This script is the analysis pipeline. It is **runnable today** — if
there's no outcome data yet, it just reports zero samples and exits;
it doesn't blow up. Re-run periodically (recommended: monthly once
you have ≥100 outcomes, again at ≥500 for a stable curve).

What it does
  1. Pull outcome records from Firestore:
     `users/{uid}/analysisOutcomes/{analysisId}`
     Fields: { feedback, recordedAt, planId, planAgeDays }
  2. Pull the matching analysis result from local export OR Firestore
     (whichever surface persists confidence per condition):
     For PT Helper today, AnalysisResultStore is UserDefaults-only —
     so this script accepts a `--analyses-export` flag pointing at a
     JSON dump from a developer's device. Once analyses persist to
     Firestore (separate Tier 3B work), the script can pull both
     sources directly.
  3. Bucket outcomes:
     accurate           → 1.0
     partially_accurate → 0.5
     inaccurate         → 0.0
     not_applicable     → SKIP (silent dismissals don't carry signal)
  4. Pair each rating with the AI's stated max-confidence for that
     analysis (the highest condition.confidence in the result).
  5. Bucket by stated confidence in 5-point bands (50-54, 55-59, …,
     85-90). For each band, compute mean observed accuracy + 95% CI.
  6. Output:
     - JSON to scripts/output/confidence_calibration.json with the
       full curve.
     - Stdout summary including the recommended new
       maxDisplayConfidence — defined as the band where observed
       accuracy first equals stated confidence (any band where stated
       > observed by >5pts is over-confident; cap should land below
       the lowest such band's lower bound).

Usage
  GOOGLE_APPLICATION_CREDENTIALS=path/to/firebase-key.json \\
      python3 scripts/calibrate_confidence.py

  python3 scripts/calibrate_confidence.py --dry-run
      Show how many outcomes would be analyzed without making API calls.

  python3 scripts/calibrate_confidence.py --min-samples 500
      Refuse to recommend a recalibration unless there are ≥500
      outcomes (recommend running this way for the actual flag flip).

Decision rule for the cap update
  If recommended_cap differs from current 85% by >5 percentage points,
  update `ConfidenceCalibrator.maxDisplayConfidence` in
  ResponseValidationPipeline.swift and ship a single-line code change.
  Smaller deltas aren't worth the churn — the cap is a soft heuristic,
  not a precise threshold.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = REPO_ROOT / "scripts/output/confidence_calibration.json"

FEEDBACK_TO_ACCURACY = {
    "accurate": 1.0,
    "partially_accurate": 0.5,
    "inaccurate": 0.0,
    # not_applicable intentionally omitted — silent dismissals carry no signal
}

# Confidence bands. Lower bound inclusive, upper exclusive (last band
# inclusive). Tuned to match how analyses typically distribute — most
# stated confidences land 50-90.
CONFIDENCE_BANDS = [
    (50, 55), (55, 60), (60, 65), (65, 70), (70, 75),
    (75, 80), (80, 85), (85, 91),
]


def fetch_outcomes_from_firestore() -> list[dict[str, Any]]:
    """Pull every outcome record from `users/{uid}/analysisOutcomes/*`.
    Requires google-cloud-firestore installed + credentials set."""
    try:
        from google.cloud import firestore
    except ImportError:
        print("ERROR: google-cloud-firestore not installed", file=sys.stderr)
        print("       Run: pip install google-cloud-firestore", file=sys.stderr)
        sys.exit(1)

    client = firestore.Client()
    outcomes: list[dict[str, Any]] = []
    # Walk users/{uid}/analysisOutcomes/* via the collection-group query.
    # Requires a single-field index on `analysisOutcomes` if not present
    # (Firestore will print the create-index URL on first run).
    for doc in client.collection_group("analysisOutcomes").stream():
        rec = doc.to_dict() or {}
        rec["_doc_id"] = doc.id
        rec["_uid"] = doc.reference.parent.parent.id if doc.reference.parent.parent else None
        outcomes.append(rec)
    return outcomes


def load_analyses_export(path: Path) -> dict[str, float]:
    """Load `{ analysisId: max_stated_confidence }` from a developer-side
    JSON export. Until analyses persist to Firestore, this is the bridge.
    Expected shape:
        { "<analysis-uuid>": { "max_confidence": 85.0 }, ... }
    OR (more flexible) a list of analyses with a `.id` and `.conditions`:
        [ { "id": "...", "conditions": [{"confidence": ...}, ...] }, ... ]
    """
    raw = json.loads(path.read_text())
    out: dict[str, float] = {}
    if isinstance(raw, dict):
        for k, v in raw.items():
            if isinstance(v, dict) and "max_confidence" in v:
                out[k] = float(v["max_confidence"])
            elif isinstance(v, (int, float)):
                out[k] = float(v)
        return out
    if isinstance(raw, list):
        for entry in raw:
            entry_id = entry.get("id")
            conds = entry.get("conditions", [])
            if entry_id and conds:
                max_conf = max((c.get("confidence", 0) for c in conds), default=0)
                out[entry_id] = float(max_conf)
        return out
    raise ValueError("Unknown analyses-export shape")


def confidence_band(stated: float) -> tuple[int, int] | None:
    for low, high in CONFIDENCE_BANDS:
        if low <= stated < high:
            return (low, high)
    return None


def wilson_ci(p: float, n: int, z: float = 1.96) -> tuple[float, float]:
    """Wilson 95% confidence interval for a binomial proportion.
    Better than normal approx at small N. Returns (low, high)."""
    if n == 0:
        return (0.0, 0.0)
    denom = 1 + z**2 / n
    centre = (p + z**2 / (2 * n)) / denom
    margin = (z * math.sqrt((p * (1 - p) + z**2 / (4 * n)) / n)) / denom
    return (max(0.0, centre - margin), min(1.0, centre + margin))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--analyses-export", type=Path, default=None,
                        help="JSON export mapping analysisId → max stated confidence")
    parser.add_argument("--outcomes-export", type=Path, default=None,
                        help="JSON export of outcome records (skips Firestore fetch)")
    parser.add_argument("--min-samples", type=int, default=100,
                        help="Refuse to recommend a recalibration with fewer outcomes")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # Pull outcomes — Firestore by default, file if explicitly provided.
    if args.outcomes_export:
        outcomes = json.loads(args.outcomes_export.read_text())
        print(f"Loaded {len(outcomes)} outcomes from {args.outcomes_export}")
    elif args.dry_run:
        print("Dry run — would query Firestore collection_group('analysisOutcomes')")
        print("Use --outcomes-export with a JSON file for offline analysis.")
        return 0
    else:
        outcomes = fetch_outcomes_from_firestore()
        print(f"Fetched {len(outcomes)} outcomes from Firestore")

    if len(outcomes) < args.min_samples:
        print(f"\nInsufficient samples: {len(outcomes)} < min {args.min_samples}.")
        print("Wait for more outcomes to accumulate via the OutcomePromptView UI.")
        return 0

    # Map analysisId → max stated confidence.
    analyses: dict[str, float] = {}
    if args.analyses_export and args.analyses_export.exists():
        analyses = load_analyses_export(args.analyses_export)
        print(f"Loaded stated confidence for {len(analyses)} analyses")
    else:
        print("WARNING: --analyses-export not provided. Per-analysis confidence")
        print("data isn't available, so this run can't compute the calibration")
        print("curve. Until analyses persist to Firestore (Tier 3B), export from")
        print("a dev device's UserDefaults: AnalysisResultStore → JSON file.")
        return 0

    # Pair outcomes with stated confidence.
    paired: list[tuple[float, float]] = []  # (stated_confidence, accuracy)
    skipped_no_match = 0
    for rec in outcomes:
        analysis_id = rec.get("analysisId") or rec.get("_doc_id")
        feedback = rec.get("feedback")
        if not analysis_id or not feedback:
            continue
        if feedback not in FEEDBACK_TO_ACCURACY:
            continue
        stated = analyses.get(str(analysis_id))
        if stated is None:
            skipped_no_match += 1
            continue
        paired.append((stated, FEEDBACK_TO_ACCURACY[feedback]))

    print(f"\nPaired {len(paired)} outcomes with stated confidence")
    print(f"Skipped {skipped_no_match} outcomes with no matching analysis")

    if not paired:
        print("No usable pairs — nothing to calibrate.")
        return 0

    # Bucket and compute per-band stats.
    by_band: dict[tuple[int, int], list[float]] = defaultdict(list)
    for stated, accuracy in paired:
        band = confidence_band(stated)
        if band:
            by_band[band].append(accuracy)

    curve: list[dict[str, Any]] = []
    print("\n=== Calibration curve ===")
    print(f"{'Band':<12}{'N':>6}{'Mean':>8}{'95% CI':>20}{'Stated mean':>14}")
    for band in CONFIDENCE_BANDS:
        accuracies = by_band.get(band, [])
        if not accuracies:
            curve.append({"band_low": band[0], "band_high": band[1], "n": 0})
            continue
        n = len(accuracies)
        mean_acc = sum(accuracies) / n
        low, high = wilson_ci(mean_acc, n)
        stated_mean = (band[0] + band[1] - 1) / 2 / 100  # midpoint as fraction
        print(f"{band[0]}-{band[1]-1:>4} {n:>6} {mean_acc:>7.2f} [{low:.2f}, {high:.2f}] {stated_mean:>14.2f}")
        curve.append({
            "band_low": band[0],
            "band_high": band[1],
            "n": n,
            "mean_accuracy": mean_acc,
            "ci_low": low,
            "ci_high": high,
            "stated_mean": stated_mean,
        })

    # Recommend a cap: highest band where mean_accuracy ≥ stated_mean − 0.05.
    # Bands above that line are over-confident.
    recommended_cap = None
    for entry in curve:
        if entry.get("n", 0) < 10:  # skip noisy bands
            continue
        if entry["mean_accuracy"] + 0.05 >= entry["stated_mean"]:
            recommended_cap = entry["band_high"] - 1
        else:
            # First over-confident band — stop. Cap should land below it.
            break

    print("\n=== Recommendation ===")
    if recommended_cap is None:
        print("Insufficient samples in any band to make a recommendation.")
    else:
        current_cap = 85
        delta = abs(recommended_cap - current_cap)
        print(f"Recommended maxDisplayConfidence: {recommended_cap}")
        print(f"Current cap: {current_cap}")
        if delta > 5:
            print(f"DELTA: {delta} pts — worth updating the cap.")
            print("Edit ConfidenceCalibrator.maxDisplayConfidence in")
            print("ios/PT-Helper/COIL/Services/ResponseValidationPipeline.swift")
        else:
            print(f"DELTA: {delta} pts — too small to justify a code change.")

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(json.dumps({
        "n_outcomes": len(outcomes),
        "n_paired": len(paired),
        "curve": curve,
        "recommended_cap": recommended_cap,
        "current_cap": 85,
    }, indent=2))
    print(f"\nWrote {OUTPUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
