#!/usr/bin/env python3
"""
Audit exercise frequency across all rehab plans in Firestore.

Scans `users/{uid}/rehabPlans/{planId}.exercises[*].name` and produces a
ranked list of exercise names by occurrence count. Output drives the
choice of which exercises get named rules in `BiomechanicalRuleEngine`.

Usage:
  python audit_plan_exercise_frequency.py --service-account path/to/key.json
  python audit_plan_exercise_frequency.py  # uses Application Default Credentials
  python audit_plan_exercise_frequency.py --top 20  # show top N (default 20)
  python audit_plan_exercise_frequency.py --include-wellness  # also scan wellnessPlans

Output is written to `scripts/output/plan_exercise_frequency.json` with
the full ranked list; the top N is printed to stdout.
"""

import argparse
import json
import sys
from collections import Counter
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


def collect_names(db, *, include_wellness: bool) -> Counter:
    """Walk users/*/rehabPlans/* and tally exercise names."""
    counter: Counter = Counter()
    users_seen = 0
    plans_seen = 0

    users = db.collection("users").stream()
    for user_doc in users:
        users_seen += 1
        uid = user_doc.id

        subcollections = ["rehabPlans"]
        if include_wellness:
            subcollections.append("wellnessPlans")

        for sub in subcollections:
            plans = db.collection("users").document(uid).collection(sub).stream()
            for plan_doc in plans:
                plans_seen += 1
                plan = plan_doc.to_dict() or {}
                exercises = plan.get("exercises") or []
                for ex in exercises:
                    name = (ex or {}).get("name") or ""
                    name = name.strip()
                    if name:
                        counter[name] += 1

    print(f"Scanned {users_seen} users, {plans_seen} plans, "
          f"{sum(counter.values())} exercise occurrences, "
          f"{len(counter)} unique names")
    return counter


def main():
    parser = argparse.ArgumentParser(
        description="Audit exercise-name frequency across all rehab plans in Firestore"
    )
    parser.add_argument(
        "--service-account",
        help="Path to Firebase service account JSON (omit to use Application Default Credentials)",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=20,
        help="Number of top entries to print to stdout (default 20)",
    )
    parser.add_argument(
        "--include-wellness",
        action="store_true",
        help="Also scan users/*/wellnessPlans in addition to rehabPlans",
    )
    parser.add_argument(
        "--output",
        default="scripts/output/plan_exercise_frequency.json",
        help="Path for full ranked JSON output",
    )
    args = parser.parse_args()

    # Initialize Firebase
    if args.service_account:
        cred = credentials.Certificate(args.service_account)
        firebase_admin.initialize_app(cred)
    else:
        firebase_admin.initialize_app()

    db = firestore.client()

    counter = collect_names(db, include_wellness=args.include_wellness)

    # Rank
    ranked = counter.most_common()

    # Persist full ranked list
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(
            {"total_unique": len(ranked), "ranked": [[n, c] for n, c in ranked]},
            indent=2,
        )
    )
    print(f"Wrote full ranked list to {output_path}")

    # Print top N
    print(f"\nTop {args.top} exercises by plan occurrence:")
    for rank, (name, count) in enumerate(ranked[: args.top], 1):
        print(f"  {rank:2}. {name} ({count})")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
