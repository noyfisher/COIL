"""
Triage low-scoring images + rewrite descriptions.

For each image with pose_score < 3 (excluding API_ERROR), asks Gemini:
  - Is the image wrong, or is the description wrong, or both, or
    fundamentally unrenderable?
  - If the description is (partly) wrong, rewrite it from scratch based
    only on the exercise name + known PT biomechanics.

Updates scripts/output/all_exercises_metadata.json in place with the
rewritten descriptions for exercises classified as description_wrong or
both_wrong. Writes a full triage report to
scripts/output/failure_triage.json.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

from google import genai
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
STOCKPILE = OUTPUT_DIR / "stockpile_progress.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"
TRIAGE_OUT = OUTPUT_DIR / "failure_triage.json"


PROMPT = """You are a senior physical therapist and fitness illustration QA reviewer.

Exercise: {name}
Target area: {target_area}
Body position: {body_position}

Current "start position" description provided to the image generator:
\"\"\"
{description}
\"\"\"

I will also show you the current image that was generated for this description.

Your task has two parts:

PART 1 — Classify the problem:
  * "image_wrong": The description is biomechanically correct for the START position
    of {name}; the image simply doesn't match it. A better image would pass.
  * "description_wrong": The description is wrong or self-contradictory (e.g., it
    describes the end/held pose rather than the starting setup). The image may
    or may not be okay, but re-scoring against a corrected description would help.
  * "both_wrong": Both the description is off AND the image doesn't even match
    the description that IS there.
  * "unrenderable": The exercise is a real PT exercise but the start position is
    a nearly-still pose that is inherently hard to convey in a single still
    image (e.g., very subtle isometric or nerve-glide start positions).

PART 2 — IF the classification is description_wrong OR both_wrong, write a
NEW "start position" description from scratch, using only your knowledge of
the exercise named "{name}" (and target area / body position hints). Ignore
the existing description. The new description must:
  * Describe ONLY the starting setup, BEFORE any motion begins.
  * Be specific about body orientation, limb positions, equipment positioning.
  * Be 1-3 sentences, camera-facing.
  * Avoid naming the exercise in the description; describe only what is visible.

Respond with ONLY a single JSON object, no markdown, no commentary, in this shape:
{{
  "classification": "image_wrong" | "description_wrong" | "both_wrong" | "unrenderable",
  "reasoning": "one short sentence",
  "new_description": "..."   // omit if classification is image_wrong or unrenderable
}}
"""


def pick_targets() -> list[str]:
    r = json.loads(QA_REPORT.read_text())
    return sorted(n for n, v in r["results"].items()
                  if v.get("pose_score") is not None
                  and v["pose_score"] < 3
                  and "API_ERROR" not in v.get("critical_failures", []))


def extract_json(text: str) -> dict | None:
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if m:
        text = m.group(1)
    else:
        m = re.search(r"\{.*\}", text, re.DOTALL)
        if m:
            text = m.group(0)
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def triage_one(client: genai.Client, name: str, ex: dict) -> dict | None:
    img_path = OUTPUT_DIR / f"{name}.png"
    if not img_path.exists():
        return None
    img = Image.open(img_path)
    prompt = PROMPT.format(
        name=ex.get("name", name),
        target_area=ex.get("target_area", "?"),
        body_position=ex.get("body_position", "?"),
        description=(ex.get("pose_description") or "").strip() or "(empty)",
    )
    try:
        resp = client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[img, prompt],
        )
    except Exception as e:
        return {"error": f"API: {e}"}
    if not resp.text:
        return {"error": "empty response"}
    parsed = extract_json(resp.text)
    if not parsed:
        return {"error": f"unparseable: {resp.text[:200]}"}
    return parsed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated subset")
    ap.add_argument("--sleep-between", type=float, default=1.5)
    ap.add_argument("--no-write-metadata", action="store_true",
                    help="Don't update metadata file; just write triage report")
    args = ap.parse_args()

    meta = json.loads(METADATA.read_text())
    meta_by = {e["normalized_filename"]: e for e in meta["exercises"]}
    # Track stockpile-origin entries so we can route description updates back
    # to both the stockpile file (source of truth for those exercises) and
    # meta["exercises"] (for in-place persistence on write-back).
    stock = None
    stock_entry_by_img: dict[str, dict] = {}
    if STOCKPILE.exists():
        stock = json.loads(STOCKPILE.read_text())
        for k, e in stock.get("all_exercises", {}).items():
            img_name = e.get("imageFileName") or k
            if img_name not in meta_by:
                meta_by[img_name] = {
                    "normalized_filename": img_name,
                    "name": e.get("name", img_name.replace("-", " ").title()),
                    "category": e.get("category", ""),
                    "target_area": e.get("targetArea", ""),
                    "body_position": e.get("bodyPosition", ""),
                    "pose_description": e.get("startPoseDescription", ""),
                }
                stock_entry_by_img[img_name] = e

    names = [n.strip() for n in args.only.split(",")] if args.only else pick_targets()
    if not names:
        print("No failures to triage.")
        return 0
    print(f"Triaging {len(names)} images...")

    client = genai.Client(api_key=args.api_key)
    triage = {}
    updates = 0
    updated_stock_names: set[str] = set()
    for idx, name in enumerate(names, 1):
        ex = meta_by.get(name)
        if not ex:
            print(f"[{idx}/{len(names)}] {name}: no metadata, skip")
            continue
        result = triage_one(client, name, ex)
        if not result or "error" in (result or {}):
            print(f"[{idx}/{len(names)}] {name}: ERROR {result.get('error') if result else 'no result'}")
            triage[name] = {"classification": "error", "reasoning": (result or {}).get("error", "?")}
        else:
            cls = result.get("classification", "?")
            reason = result.get("reasoning", "")
            new_desc = (result.get("new_description") or "").strip()
            print(f"[{idx}/{len(names)}] {name}: {cls}")
            print(f"    {reason}")
            if new_desc and cls in {"description_wrong", "both_wrong"} and not args.no_write_metadata:
                old = ex.get("pose_description", "")
                ex["pose_description"] = new_desc
                # If this entry came from stockpile, also update the stockpile
                # source so the change is persisted on that side.
                stock_entry = stock_entry_by_img.get(name)
                if stock_entry is not None:
                    stock_entry["startPoseDescription"] = new_desc
                    updated_stock_names.add(name)
                updates += 1
                print(f"    old desc: {old[:120]}...")
                print(f"    new desc: {new_desc[:120]}...")
            triage[name] = {
                "classification": cls,
                "reasoning": reason,
                "new_description": new_desc,
                "old_description": ex.get("pose_description") if cls in {"image_wrong","unrenderable"} else None,
            }
        time.sleep(args.sleep_between)

    TRIAGE_OUT.write_text(json.dumps(triage, indent=2))
    print(f"\nTriage written: {TRIAGE_OUT}")

    if updates and not args.no_write_metadata:
        # Only *updated* stockpile-origin entries get appended to
        # meta["exercises"] — avoids bloating the unified metadata file with
        # hundreds of unchanged stockpile exercises on every run.
        existing = {e["normalized_filename"] for e in meta["exercises"]}
        for n in updated_stock_names:
            if n not in existing:
                meta["exercises"].append(meta_by[n])
        METADATA.write_text(json.dumps(meta, indent=2))
        print(f"Updated {updates} descriptions in {METADATA}")
        # Stockpile is the source of truth for stockpile-only exercises —
        # persist description edits there too so future runs see them even
        # before the unified metadata file is rebuilt.
        if stock is not None and updated_stock_names:
            STOCKPILE.write_text(json.dumps(stock, indent=2))
            print(f"Updated {len(updated_stock_names)} stockpile descriptions in {STOCKPILE}")

    # Summary by classification
    counts = {}
    for v in triage.values():
        c = v.get("classification", "?")
        counts[c] = counts.get(c, 0) + 1
    print("\nClassification breakdown:")
    for k in ["image_wrong", "description_wrong", "both_wrong", "unrenderable", "error"]:
        print(f"  {k}: {counts.get(k, 0)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
