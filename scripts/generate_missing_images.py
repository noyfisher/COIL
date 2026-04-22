"""
Generate start images for exercises that don't have one yet.

Uses Nano Banana Pro (gemini-3-pro-image-preview) with the same prompt
structure that achieved 84% score-5 rate on existing images. Saves each
image immediately + runs QA + updates the report incrementally.

Usage:
  python scripts/generate_missing_images.py --api-key KEY
  python scripts/generate_missing_images.py --api-key KEY --limit 50   # first batch
  python scripts/generate_missing_images.py --api-key KEY --only name1,name2
"""
from __future__ import annotations

import argparse
import json
import signal
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
STOCKPILE = OUTPUT_DIR / "stockpile_progress.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"
GEN_MODEL = "gemini-3-pro-image-preview"

SUBJECT = (
    "An athletic young man with short dark hair, lean fit build, "
    "wearing a fitted light gray athletic t-shirt, dark navy compression "
    "shorts, white ankle socks, and gray athletic sneakers."
)
STYLE = (
    "Style: clean professional fitness illustration, soft even studio lighting, "
    "plain white background, no furniture or equipment unless specified in the pose. "
    "Single figure centered, full body visible from head to toe. "
    "No text, labels, watermarks, arrows, or annotations anywhere in the image. "
    "The pose must exactly match the described position."
)


class _Timeout(Exception):
    pass


def _alarm_handler(signum, frame):
    raise _Timeout("timeout")


def build_prompt(name: str, desc: str, body_pos: str) -> str:
    return (
        f"Clean professional fitness illustration of a physical therapy exercise.\n\n"
        f"Subject: {SUBJECT}\n\n"
        f"Exercise: {name}\n"
        f"Body position: {body_pos}\n"
        f"Pose: {desc}\n\n"
        f"{STYLE}"
    )


def generate_image(client: genai.Client, prompt: str) -> bytes | None:
    signal.alarm(90)
    try:
        resp = client.models.generate_content(
            model=GEN_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except _Timeout:
        print("T", end="", flush=True)
        return None
    except Exception as e:
        print(f"E({e})", end="", flush=True)
        return None
    finally:
        signal.alarm(0)
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for p in cand.content.parts:
                d = getattr(p, "inline_data", None)
                if d and d.data:
                    return d.data
    return None


def qa_image(client: genai.Client, path: Path, ex: dict) -> dict | None:
    sys.path.insert(0, str(SCRIPT_DIR))
    from qa_exercise_images import analyze_image
    signal.alarm(60)
    try:
        result = analyze_image(client, path, ex)
        return json.loads(result.model_dump_json())
    except _Timeout:
        return None
    except Exception:
        return None
    finally:
        signal.alarm(0)


def load_all_metadata() -> dict[str, dict]:
    """Merge unified metadata + stockpile into a lookup by normalized filename."""
    result = {}
    # Unified metadata first
    if METADATA.exists():
        for e in json.loads(METADATA.read_text())["exercises"]:
            result[e["normalized_filename"]] = e
    # Stockpile fills gaps
    if STOCKPILE.exists():
        stock = json.loads(STOCKPILE.read_text())
        for k, e in stock.get("all_exercises", {}).items():
            img_name = e.get("imageFileName") or k
            if img_name not in result:
                result[img_name] = {
                    "normalized_filename": img_name,
                    "name": e.get("name", img_name.replace("-", " ").title()),
                    "category": e.get("category", ""),
                    "target_area": e.get("targetArea", ""),
                    "body_position": e.get("bodyPosition", ""),
                    "pose_description": e.get("startPoseDescription", ""),
                }
    return result


def find_missing(meta: dict[str, dict]) -> list[str]:
    """Return exercise names that have metadata but no image on disk."""
    existing = set()
    for p in OUTPUT_DIR.glob("*.png"):
        stem = p.stem
        if any(stem.endswith(s) for s in ('_end', '_mask', '_mask_preview', '_contact_sheet')):
            continue
        if stem.startswith(('_tmp_', 'nb_')):
            continue
        existing.add(stem)
    return sorted(n for n in meta if n not in existing)


def update_report(name: str, qa: dict) -> None:
    report = json.loads(QA_REPORT.read_text()) if QA_REPORT.exists() else {
        "total_images": 0, "passed": 0, "failed": 0,
        "skipped": 0, "failures_by_check": {}, "results": {}
    }
    report["results"][name] = qa
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    fails = {}
    for v in report["results"].values():
        for fc in v.get("critical_failures", []):
            fails[fc] = fails.get(fc, 0) + 1
    report["failures_by_check"] = fails
    QA_REPORT.write_text(json.dumps(report, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--limit", type=int, default=0, help="Cap images to generate (0=all)")
    ap.add_argument("--only", help="Comma-separated subset")
    ap.add_argument("--skip-qa", action="store_true", help="Generate only, skip QA")
    args = ap.parse_args()

    signal.signal(signal.SIGALRM, _alarm_handler)
    meta = load_all_metadata()
    client = genai.Client(api_key=args.api_key)

    if args.only:
        targets = [n.strip() for n in args.only.split(",") if n.strip()]
    else:
        targets = find_missing(meta)
    if args.limit > 0:
        targets = targets[:args.limit]

    print(f"Generating {len(targets)} missing images...")
    t0 = time.time()
    generated = failed = 0

    for idx, name in enumerate(targets, 1):
        ex = meta.get(name)
        if not ex:
            print(f"?", end="", flush=True)
            failed += 1
            continue

        desc = ex.get("pose_description", "").strip()
        body_pos = ex.get("body_position", "standing")
        if not desc:
            print("?", end="", flush=True)
            failed += 1
            continue

        prompt = build_prompt(ex.get("name", name), desc, body_pos)
        img_bytes = generate_image(client, prompt)
        if not img_bytes:
            failed += 1
            time.sleep(1)
            continue

        out_path = OUTPUT_DIR / f"{name}.png"
        out_path.write_bytes(img_bytes)
        generated += 1

        # QA
        if not args.skip_qa:
            qa = qa_image(client, out_path, ex)
            if qa:
                update_report(name, qa)
                score = qa.get("pose_score", "?")
                sym = str(score) if score == 5 else str(score).lower()
            else:
                sym = "q"  # QA failed
        else:
            sym = "g"  # generated, no QA

        print(sym, end="", flush=True)
        if idx % 50 == 0:
            elapsed = time.time() - t0
            print(f"  [{idx}/{len(targets)}  gen={generated} fail={failed}  {elapsed:.0f}s]")

        time.sleep(1)  # gentle pacing

    elapsed = time.time() - t0
    print(f"\n\nDone. generated={generated}  failed={failed}  "
          f"total_time={elapsed:.0f}s  avg={elapsed/max(generated,1):.1f}s/img")

    # Final score distribution
    if QA_REPORT.exists():
        r = json.loads(QA_REPORT.read_text())
        from collections import Counter
        c = Counter(v.get("pose_score") for v in r["results"].values())
        t = r["total_images"]
        print(f"\nOverall: {t} images, {r['passed']} pass ({r['passed']*100//t}%)")
        for s in [5, 4, 3, 2, 1]:
            print(f"  {s}: {c[s]:3d} ({c[s]*100//t}%)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
