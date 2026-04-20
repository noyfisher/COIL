"""
Auto-generate per-image prompts from Gemini observations, then regen with NB Pro.

For each stuck image, feeds Gemini:
  - exercise name + corrected description
  - its own prior QA observation of what went wrong
  - asks it to write an image-generation prompt that corrects the error

Then generates the image with NB Pro using that prompt, and re-QAs.

Usage:
  python scripts/regen_with_auto_prompts.py --api-key KEY
  python scripts/regen_with_auto_prompts.py --api-key KEY --only wrist-curls
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import signal
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types
from PIL import Image


class _Timeout(Exception):
    pass


def _alarm_handler(signum, frame):
    raise _Timeout("API call timed out")

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
BACKUP_DIR = OUTPUT_DIR / "_auto_prompt_backup"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
STOCKPILE = OUTPUT_DIR / "stockpile_progress.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"
GEN_MODEL = "gemini-3-pro-image-preview"

SUBJECT = (
    "An athletic young man with short dark hair, lean fit build, "
    "wearing a fitted light gray athletic t-shirt, dark navy compression "
    "shorts, white ankle socks, and gray athletic sneakers."
)

PROMPT_GEN_TEMPLATE = """You are a prompt engineer specializing in fitness illustration generation.

Exercise: {name}
Target area: {target_area}
Body position: {body_position}

CORRECT start-position description:
\"\"\"{description}\"\"\"

The PREVIOUS image was wrong. The QA reviewer observed:
\"\"\"{observation}\"\"\"

Write an image-generation prompt that will produce a CORRECT illustration.
Your prompt MUST:
1. Start with the character description: "{subject}"
2. Describe the EXACT correct pose in detail, emphasizing the specific aspects
   the previous image got wrong.
3. Include explicit ANTI-CUES: "Do NOT show [what the previous image showed]."
4. Specify the best camera angle to clearly show this exercise's distinguishing features.
5. End with: "Style: clean professional fitness illustration, soft even studio
   lighting, plain white background, no text or labels. Single figure centered,
   full body visible from head to toe."

Respond with ONLY the prompt text (no JSON, no commentary, no markdown).
Keep it under 300 words."""


def pick_stuck() -> list[str]:
    r = json.loads(QA_REPORT.read_text())
    return sorted(n for n, v in r["results"].items()
                  if v.get("pose_score") is not None
                  and v["pose_score"] < 3
                  and "API_ERROR" not in v.get("critical_failures", []))


def generate_prompt(client: genai.Client, name: str, ex: dict, obs: str) -> str | None:
    prompt = PROMPT_GEN_TEMPLATE.format(
        name=ex.get("name", name),
        target_area=ex.get("target_area", "?"),
        body_position=ex.get("body_position", "?"),
        description=(ex.get("pose_description") or "").strip(),
        observation=obs.strip(),
        subject=SUBJECT,
    )
    signal.alarm(60)
    try:
        resp = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=prompt,
        )
    except _Timeout:
        print(f"    PROMPT-GEN TIMEOUT")
        return None
    except Exception as e:
        print(f"    PROMPT-GEN ERROR: {e}")
        return None
    finally:
        signal.alarm(0)
    return resp.text.strip() if resp.text else None


def generate_image(client: genai.Client, prompt: str) -> bytes | None:
    signal.alarm(90)
    try:
        resp = client.models.generate_content(
            model=GEN_MODEL,
            contents=prompt,
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except _Timeout:
        print(f"    IMG-GEN TIMEOUT")
        return None
    except Exception as e:
        print(f"    IMG-GEN ERROR: {e}")
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


def qa_image(client: genai.Client, path: Path, ex: dict) -> dict:
    sys.path.insert(0, str(SCRIPT_DIR))
    from qa_exercise_images import analyze_image
    signal.alarm(60)
    try:
        result = analyze_image(client, path, ex)
        return json.loads(result.model_dump_json())
    except _Timeout:
        print(f"    QA TIMEOUT")
        return {"pose_score": 0, "overall_pass": False, "critical_failures": ["TIMEOUT"]}
    finally:
        signal.alarm(0)


def update_report(name: str, qa: dict) -> None:
    report = json.loads(QA_REPORT.read_text())
    report["results"][name] = qa
    total = len(report["results"])
    passed = sum(1 for v in report["results"].values() if v.get("overall_pass"))
    report["total_images"] = total
    report["passed"] = passed
    report["failed"] = total - passed
    QA_REPORT.write_text(json.dumps(report, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated subset")
    ap.add_argument("--attempts", type=int, default=2,
                    help="Attempts per image (default: 2, keeps best)")
    args = ap.parse_args()

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGALRM, _alarm_handler)
    meta = {e["normalized_filename"]: e
            for e in json.loads(METADATA.read_text())["exercises"]}
    if STOCKPILE.exists():
        stock = json.loads(STOCKPILE.read_text())
        for k, e in stock.get("all_exercises", {}).items():
            img_name = e.get("imageFileName") or k
            if img_name not in meta:
                meta[img_name] = {
                    "normalized_filename": img_name,
                    "name": e.get("name", img_name.replace("-", " ").title()),
                    "category": e.get("category", ""),
                    "target_area": e.get("targetArea", ""),
                    "body_position": e.get("bodyPosition", ""),
                    "pose_description": e.get("startPoseDescription", ""),
                }
    report = json.loads(QA_REPORT.read_text())

    names = [n.strip() for n in args.only.split(",")] if args.only else pick_stuck()
    client = genai.Client(api_key=args.api_key)

    rows = []
    for idx, name in enumerate(names, 1):
        ex = meta.get(name)
        if not ex:
            print(f"[{idx}/{len(names)}] {name}: no metadata")
            continue

        old_qa = report["results"].get(name, {})
        old_score = old_qa.get("pose_score") or 0
        obs = old_qa.get("pose_accuracy", {}).get("observation", "")
        print(f"\n[{idx}/{len(names)}] {name}  (current: {old_score}/5)")

        # Step 1: Gemini writes the prompt
        gen_prompt = generate_prompt(client, name, ex, obs)
        if not gen_prompt:
            print(f"  prompt generation FAILED")
            rows.append((name, old_score, old_score, "prompt_fail"))
            continue
        print(f"  prompt ({len(gen_prompt)} chars): {gen_prompt[:120]}...")

        # Backup current image
        src = OUTPUT_DIR / f"{name}.png"
        if src.exists():
            bk = BACKUP_DIR / f"{name}.png"
            if not bk.exists():
                shutil.copy2(src, bk)

        # Step 2: Generate image(s) and keep best
        best_score = old_score
        best_bytes = None
        best_qa = None
        for attempt in range(args.attempts):
            img_bytes = generate_image(client, gen_prompt)
            if not img_bytes:
                print(f"  attempt {attempt+1}: gen failed")
                time.sleep(2)
                continue
            # Write temp, QA
            tmp = OUTPUT_DIR / f"_tmp_{name}.png"
            tmp.write_bytes(img_bytes)
            qa = qa_image(client, tmp, ex)
            score = qa.get("pose_score") or 0
            print(f"  attempt {attempt+1}: score={score}/5")
            if score > best_score:
                best_score = score
                best_bytes = img_bytes
                best_qa = qa
            try:
                tmp.unlink()
            except OSError:
                pass
            time.sleep(2)

        # Install winner
        if best_bytes is not None:
            src.write_bytes(best_bytes)
            update_report(name, best_qa)
            print(f"  INSTALLED score {best_score}")
            rows.append((name, old_score, best_score, "installed"))
        else:
            print(f"  kept current ({old_score})")
            rows.append((name, old_score, old_score, "kept"))

        time.sleep(1)

    # Summary
    print("\n" + "=" * 72)
    print("AUTO-PROMPT REGEN SUMMARY")
    print("=" * 72)
    improved = sum(1 for _, o, n, s in rows if n > o)
    unchanged = sum(1 for _, o, n, s in rows if n == o)
    print(f"  Attempted: {len(rows)}   Improved: {improved}   Unchanged: {unchanged}")
    print()
    print(f"{'Exercise':<44} {'old':>4} {'new':>4} {'status':>12}")
    for name, old, new, status in rows:
        arrow = "->" if new > old else "=="
        print(f"{name:<44} {old:>4} {arrow} {new:>3}  {status:>12}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
