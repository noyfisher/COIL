"""
Robust QA sweep that checkpoints after each image.

- Runs QA one image at a time (no async, no hang-amplifying concurrency).
- Enforces a per-image wall-clock timeout so a single hung call never
  blocks the whole sweep.
- Writes the report file after every successful QA so partial progress
  is always persisted.
- Skips images already in the output file (unless --all).

Usage:
  python scripts/qa_sweep_robust.py --api-key KEY --output scripts/output/qa_pass_2.json
  python scripts/qa_sweep_robust.py --api-key KEY --output scripts/output/qa_pass_3.json
  python scripts/qa_sweep_robust.py --api-key KEY --output out.json --all   # re-score even if present
"""
from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from pathlib import Path

from google import genai

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"

sys.path.insert(0, str(SCRIPT_DIR))
from qa_exercise_images import analyze_image, QAResult  # noqa


class Timeout(Exception):
    pass


def _alarm_handler(signum, frame):
    raise Timeout("per-image timeout")


def load_report(path: Path) -> dict:
    if not path.exists():
        return {
            "total_images": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "failures_by_check": {},
            "results": {},
        }
    return json.loads(path.read_text())


def save_report(report: dict, path: Path) -> None:
    # Recompute aggregates
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    fails = {}
    for v in report["results"].values():
        for fc in v.get("critical_failures", []):
            fails[fc] = fails.get(fc, 0) + 1
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    report["failures_by_check"] = fails
    path.write_text(json.dumps(report, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--metadata-file", default=str(METADATA))
    ap.add_argument("--timeout", type=int, default=60,
                    help="Per-image QA timeout in seconds (default: 60)")
    ap.add_argument("--all", action="store_true",
                    help="Re-score images already present in output")
    ap.add_argument("--retry-errors", action="store_true",
                    help="Re-score images previously marked API_ERROR/TIMEOUT/EXCEPTION")
    ap.add_argument("--sleep-between", type=float, default=0.0,
                    help="Seconds to sleep between calls (for rate-limit pacing)")
    args = ap.parse_args()

    out_path = Path(args.output)
    report = load_report(out_path)

    meta = json.loads(Path(args.metadata_file).read_text())["exercises"]
    client = genai.Client(api_key=args.api_key)

    # Install a global alarm-based timeout guard (POSIX only)
    signal.signal(signal.SIGALRM, _alarm_handler)

    t0 = time.time()
    done = len(report["results"])
    attempted = 0
    new_fails = 0

    for idx, ex in enumerate(meta, 1):
        name = ex["normalized_filename"]
        img_path = OUTPUT_DIR / f"{name}.png"
        if not img_path.exists():
            continue
        if not args.all and name in report["results"]:
            if args.retry_errors:
                fails = report["results"][name].get("critical_failures", [])
                if not any(f in {"API_ERROR", "TIMEOUT"} or f.startswith("EXCEPTION")
                           for f in fails):
                    continue
            else:
                continue

        attempted += 1
        signal.alarm(args.timeout)
        try:
            result = analyze_image(client, img_path, ex)
            qa = json.loads(result.model_dump_json())
            report["results"][name] = qa
            score = qa.get("pose_score")
            pass_ = qa.get("overall_pass")
            sym = "." if pass_ else "F"
            if not pass_:
                new_fails += 1
        except Timeout:
            sym = "T"
            # Stuff a synthetic failure so we don't retry on next restart
            report["results"][name] = {
                "exercise_name": ex["name"],
                "filename": f"{name}.png",
                "pose_score": 1,
                "overall_pass": False,
                "critical_failures": ["TIMEOUT"],
                "pose_accuracy": {"observation": f"QA timed out after {args.timeout}s",
                                   "passed": False},
            }
            new_fails += 1
        except Exception as e:
            sym = "E"
            report["results"][name] = {
                "exercise_name": ex["name"],
                "filename": f"{name}.png",
                "pose_score": 1,
                "overall_pass": False,
                "critical_failures": [f"EXCEPTION: {type(e).__name__}"],
                "pose_accuracy": {"observation": f"Exception: {e}", "passed": False},
            }
            new_fails += 1
        finally:
            signal.alarm(0)

        print(sym, end="", flush=True)
        save_report(report, out_path)
        if args.sleep_between > 0:
            time.sleep(args.sleep_between)
        if idx % 50 == 0:
            elapsed = time.time() - t0
            print(f"  [{idx}/{len(meta)}  attempted={attempted}  new_fail={new_fails}  {elapsed:.0f}s]")

    elapsed = time.time() - t0
    print()
    print(f"\nDone. attempted={attempted}  failed={new_fails}  "
          f"total={len(report['results'])}  elapsed={elapsed:.0f}s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
