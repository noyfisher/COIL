"""
Fill missing end_pose_description fields in all_exercises_metadata.json.

Uses Gemini 2.5 Flash to generate parallel-style end descriptions from the
exercise's start description + name + body_position + target_area + category.

Writes back to scripts/output/all_exercises_metadata.json (saving every 25
entries to survive crashes). One-time backup at all_exercises_metadata.before_end_desc.json.

Usage:
  python scripts/generate_end_descriptions.py --api-key KEY
  python scripts/generate_end_descriptions.py --api-key KEY --limit 10
"""
import argparse
import json
import shutil
import signal
import sys
import time
from pathlib import Path

from google import genai

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
BACKUP = OUT / "all_exercises_metadata.before_end_desc.json"
PROGRESS = OUT / "end_desc_progress.json"

MODEL = "gemini-2.5-flash"

PROMPT_TEMPLATE = """You are writing the END-position description for a physical therapy exercise.

The START position is described below. Write the END position in the SAME prose style and structure.
The reader is an image-generation model — they need a precise still-frame of the body at the end of one rep.

Exercise: {name}
Category: {category}
Target area: {target_area}
Body position: {body_position}
START pose description:
{start_desc}

Rules:
- Describe the body position at the end of one rep (peak of the movement).
- Same level of anatomical detail as the start description.
- Mention which muscles are visibly engaged or stretched at the end.
- Single static still — no motion words like "lifting", "rotating", "moving".
- 2-4 sentences typically. Match the start description's length.
- Plain prose only. No bullet points. No "Step 1:" / "Step 2:" labels. No commentary, no markdown.

Respond with ONLY the end-position description text."""


class _Timeout(Exception):
    pass


def _alarm(signum, frame):
    raise _Timeout()


def generate_end_desc(client: genai.Client, ex: dict) -> str | None:
    prompt = PROMPT_TEMPLATE.format(
        name=ex.get("name", ex["normalized_filename"]),
        category=ex.get("category", "?"),
        target_area=ex.get("target_area", "?"),
        body_position=ex.get("body_position", "?"),
        start_desc=ex.get("pose_description", ""),
    )
    signal.alarm(60)
    try:
        resp = client.models.generate_content(model=MODEL, contents=prompt)
    except _Timeout:
        return None
    except Exception as e:
        print(f"  ERR: {e}")
        return None
    finally:
        signal.alarm(0)
    text = (resp.text or "").strip() if resp else ""
    return text or None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    signal.signal(signal.SIGALRM, _alarm)
    meta = json.loads(META.read_text())

    if not BACKUP.exists():
        shutil.copy(META, BACKUP)
        print(f"backup -> {BACKUP.name}")

    targets = [e for e in meta["exercises"]
               if not (e.get("end_pose_description") or "").strip()]
    if args.limit > 0:
        targets = targets[: args.limit]
    print(f"need end_pose_description: {len(targets)}")

    client = genai.Client(api_key=args.api_key)
    progress = {"filled": 0, "failed": 0, "errors": []}
    t0 = time.time()

    for idx, ex in enumerate(targets, 1):
        name = ex["normalized_filename"]
        text = generate_end_desc(client, ex)
        if text:
            ex["end_pose_description"] = text
            progress["filled"] += 1
            sym = "."
        else:
            progress["failed"] += 1
            progress["errors"].append(name)
            sym = "x"
        print(sym, end="", flush=True)
        if idx % 25 == 0:
            META.write_text(json.dumps(meta, indent=2))
            elapsed = time.time() - t0
            print(f" [{idx}/{len(targets)} filled={progress['filled']} fail={progress['failed']} {elapsed:.0f}s]")
        time.sleep(0.4)

    META.write_text(json.dumps(meta, indent=2))
    PROGRESS.write_text(json.dumps(progress, indent=2))
    elapsed = time.time() - t0
    print(f"\n\nDone. filled={progress['filled']} failed={progress['failed']} {elapsed:.0f}s")
    return 0 if progress["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
