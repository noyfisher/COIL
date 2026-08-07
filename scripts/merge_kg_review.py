#!/usr/bin/env python3
"""
Tier 2 PR C-2 final step — merge reviewed verdicts into the production v2
knowledge graph file.

Pipeline summary (review the README of expand_knowledge_graph.py +
review_kg_candidates.py for the upstream steps):

  1. expand_knowledge_graph.py  →  scripts/output/knowledge_graph_v2_draft.json
  2. review_kg_candidates.py    →  scripts/output/kg_review_decisions.json
  3. merge_kg_review.py (THIS)  →  ios/.../Resources/medical_knowledge_graph_v2.json

Behavior
- Reads the draft + decisions.
- Applies decisions:
    APPROVE → keep verdict as-is
    REJECT  → drop the verdict (treat as unverified — pair won't appear
              in the merged file)
    FLIP    → flip safe ↔ contraindicated (verdict only; reason kept)
    EDIT    → if the reviewer supplied an edited_reason, it overrides
              the AI's reason in the merged file
    PENDING → drop. Unreviewed verdicts must NOT ship to prod. The
              script prints a count + bails unless --allow-pending is
              passed (CI guard).
- Verdicts NOT in the decisions file (e.g. ones that didn't make it
  into the review queue because they were "safe" outside the 10%
  sample) inherit `safe`. They DO ship — that's the whole point of
  sampling for review rather than reviewing every safe verdict.
- Groups verdicts by condition_id, builds the v1-shape KnowledgeGraph
  schema (matches `medical_knowledge_graph.json`):

    {
      "version": "2.0",
      "conditions": {
        "<condition_id>": {
          "names": [...],          # from draft if present, else [id]
          "icd10": "",             # not generated; left blank for v2
          "bodyRegions": [],       # not generated
          "safeExercises": [...],  # from approved/flipped-to-safe
          "unsafeExercises": [...],
          "redFlags": [],
          "referIfPresent": []
        },
        ...
      }
    }

Usage
  python3 scripts/merge_kg_review.py
  python3 scripts/merge_kg_review.py --allow-pending  # ship unreviewed
  python3 scripts/merge_kg_review.py --output path/to/file.json
  python3 scripts/merge_kg_review.py --dry-run        # print summary

After this script writes the file, flip
@AppStorage("knowledgeGraphV2Enabled") to true (default) in
KnowledgeGraphService.swift to enable v2 in production.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DRAFT_INPUT = REPO_ROOT / "scripts/output/knowledge_graph_v2_draft.json"
DECISIONS_INPUT = REPO_ROOT / "scripts/output/kg_review_decisions.json"
DEFAULT_OUTPUT = REPO_ROOT / "ios/PT-Helper/COIL/Resources/medical_knowledge_graph_v2.json"


def load_json(path: Path, label: str) -> Any:
    if not path.exists():
        print(f"ERROR: {label} not found at {path}", file=sys.stderr)
        sys.exit(2)
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as e:
        print(f"ERROR: {label} is not valid JSON: {e}", file=sys.stderr)
        sys.exit(2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Merge KG review decisions into v2 graph file")
    parser.add_argument(
        "--draft",
        type=Path,
        default=DRAFT_INPUT,
        help="Generated draft from expand_knowledge_graph.py",
    )
    parser.add_argument(
        "--decisions",
        type=Path,
        default=DECISIONS_INPUT,
        help="Review decisions JSON from review_kg_candidates.py",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Output path for the merged v2 graph",
    )
    parser.add_argument(
        "--allow-pending",
        action="store_true",
        help="Ship even when contraindicated/unclear verdicts haven't been reviewed",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print summary without writing output",
    )
    args = parser.parse_args()

    draft = load_json(args.draft, "draft")
    decisions = load_json(args.decisions, "decisions")

    verdicts = draft.get("verdicts", [])
    if not verdicts:
        print("ERROR: draft contains no verdicts — nothing to merge", file=sys.stderr)
        return 2

    # Sanity check: any contraindicated/unclear verdict that wasn't decided
    # is dangerous to ship. The reviewer is the safety gate.
    review_required = [
        v for v in verdicts
        if v.get("verdict") in ("contraindicated", "unclear")
    ]
    pending_required = []
    for v in review_required:
        key = f"{v['condition_id']}|{v['exercise_id']}"
        decision = (decisions.get(key) or {}).get("decision", "pending")
        if decision == "pending":
            pending_required.append(key)

    if pending_required and not args.allow_pending:
        print(f"ERROR: {len(pending_required)} contraindicated/unclear verdicts are unreviewed.", file=sys.stderr)
        print("Run `python3 scripts/review_kg_candidates.py` and walk the queue,", file=sys.stderr)
        print("or pass --allow-pending to ship anyway (NOT recommended).", file=sys.stderr)
        print("First 10 pending:", file=sys.stderr)
        for key in pending_required[:10]:
            print(f"  {key}", file=sys.stderr)
        return 3

    # Apply decisions: drop rejected + pending, flip flipped, override
    # edited reasons. Default-keep anything else (safe verdicts not
    # sampled for review pass through unchanged).
    accepted: list[dict[str, Any]] = []
    counts = defaultdict(int)
    for v in verdicts:
        key = f"{v['condition_id']}|{v['exercise_id']}"
        decision_record = decisions.get(key) or {}
        decision = decision_record.get("decision", "implicit-approve")

        if decision == "reject":
            counts["rejected"] += 1
            continue
        if decision == "pending" and not args.allow_pending:
            # Already short-circuited above, but safety net.
            counts["dropped_pending"] += 1
            continue

        merged = dict(v)

        if decision == "flip":
            current = merged.get("verdict")
            if current == "safe":
                merged["verdict"] = "contraindicated"
            elif current == "contraindicated":
                merged["verdict"] = "safe"
            counts["flipped"] += 1
        else:
            counts[decision] += 1

        if (edited := decision_record.get("edited_reason")) and edited.strip():
            merged["reason"] = edited.strip()
            counts["reason_edited"] += 1

        accepted.append(merged)

    # Build the v1-shape graph from accepted verdicts.
    by_condition: dict[str, dict[str, set[str]]] = defaultdict(
        lambda: {"safe": set(), "unsafe": set()}
    )
    for v in accepted:
        cid = v["condition_id"]
        ex = v["exercise_id"]
        if v["verdict"] == "safe":
            by_condition[cid]["safe"].add(ex)
        elif v["verdict"] == "contraindicated":
            by_condition[cid]["unsafe"].add(ex)
        # "unclear" verdicts intentionally don't ship — we don't have
        # evidence either way, so the graph stays silent (= unverified
        # tier at lookup time, which then escalates to cross-model).

    conditions_payload: dict[str, Any] = {}
    for cid, sets in by_condition.items():
        conditions_payload[cid] = {
            "names": [cid.replace("-", " ").replace("_", " ")],
            "icd10": "",
            "bodyRegions": [],
            "safeExercises": sorted(sets["safe"]),
            "unsafeExercises": sorted(sets["unsafe"]),
            "redFlags": [],
            "referIfPresent": [],
        }

    output_payload = {
        "_NOTE": "Generated by scripts/merge_kg_review.py from a reviewed draft. Do NOT hand-edit — re-run the merge if you need to change verdicts. v1 graph (medical_knowledge_graph.json) is still loaded as the base; this file unions on top via KnowledgeGraphService.merge.",
        "version": "2.0",
        "conditions": conditions_payload,
    }

    print("\n=== Merge summary ===")
    print(f"  Total verdicts in draft: {len(verdicts)}")
    print(f"  Reviewed contraindicated/unclear: {len(review_required)}")
    for kind, n in sorted(counts.items()):
        print(f"  {kind:>20}: {n}")
    print(f"  Conditions in output: {len(conditions_payload)}")
    print(f"  Total safe pairs:     {sum(len(c['safeExercises']) for c in conditions_payload.values())}")
    print(f"  Total unsafe pairs:   {sum(len(c['unsafeExercises']) for c in conditions_payload.values())}")

    if args.dry_run:
        print(f"\nDry run — NOT writing to {args.output}")
        return 0

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output_payload, indent=2))
    print(f"\nWrote {args.output}")
    print("\nNext: flip @AppStorage(\"knowledgeGraphV2Enabled\") default to true in")
    print("ios/PT-Helper/COIL/Services/KnowledgeGraphService.swift")
    print("(currently OFF by default — see KnowledgeGraphFeatureFlag).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
